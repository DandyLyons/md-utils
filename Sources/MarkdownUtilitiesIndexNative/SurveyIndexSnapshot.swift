import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

/// Snapshot-only survey evidence. Reading this type never inspects sources or definitions.
public struct FrontmatterIndexSnapshot: Sendable {
  /// Projection occurs in SQLite before transferring or decoding observation JSON.
  public enum Projection: Sendable {
    case full, coverage, keys, selected(Set<String>)
  }
  public var observations: [MarkdownSurveyObservation]
  public var generation: Int
  public var limitations: [String]
  /// Actual JSON bytes transferred from SQLite for decoding, after projection.
  public var decodedBytes = 0

  public static func read(
    root: Path, selections: [String], includeNonMarkdown: Bool, maxFiles: Int = 100_000,
    projection: Projection = .full, requireQueryEvidence: Bool = false,
    acceptsPath: (String) -> Bool = { _ in true },
  ) throws -> Self {
    let database = try SQLiteIndexDatabase(readOnlyPath: (root + ".md-utils/index.sqlite").string)
    return try database.serverRead { db in
      let generation = try SQLiteIndexDatabase.publishedGeneration(in: db)
      guard try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='root'") == root.string else {
        throw IndexProjectError("Snapshot belongs to another project root")
      }
      var scopes: [(IndexScope, String)] = []
      for row in try Row.fetchAll(db, sql: "SELECT definition,state FROM scopes") {
        let scope = try JSONDecoder().decode(IndexScope.self, from: Data((row["definition"] as String).utf8))
        if scope.kind == .directory && (!includeNonMarkdown || scope.includeNonMarkdown) { scopes.append((scope, row["state"])) }
      }
      var result = Self(observations: [], generation: generation, limitations: [])
      var needed: Set<String> = []
      for selection in selections {
        let candidates = scopes.filter { $0.0.path.isEmpty || selection == $0.0.path || selection.hasPrefix($0.0.path) }
        guard let best = candidates.sorted(by: { $0.0.path.count > $1.0.path.count }).first else {
          result.limitations.append("No published directory coverage for \(selection.isEmpty ? "." : selection)")
          continue
        }
        needed.insert(best.0.id)
        if best.1 != "complete" { result.limitations.append("Incomplete indexed scope: \(best.0.path)") }
      }
      var seen: Set<String> = []
      var bytes = 0
      var textFiles = 0
      for scope in needed.sorted() {
        let frontmatter: String
        let metadata: String
        var arguments: [DatabaseValue] = []
        switch projection {
        case .full:
          frontmatter = "json_extract(detail,'$.frontmatter')"
          metadata = "json_extract(detail,'$.valueMetadata')"
        case .coverage:
          frontmatter = "NULL"; metadata = "NULL"
        case .keys:
          // Kind-preserving sentinels avoid decoding unrelated nested values.
          frontmatter = "(SELECT json_group_object(j.key, CASE j.type WHEN 'object' THEN json('{}') WHEN 'array' THEN json('[]') WHEN 'text' THEN '' WHEN 'integer' THEN 0 WHEN 'real' THEN 0.5 WHEN 'true' THEN json('true') WHEN 'false' THEN json('false') ELSE NULL END) FROM json_each(detail,'$.frontmatter') j)"
          metadata = "json_extract(detail,'$.valueMetadata')"
        case .selected(let keys):
          let encoded = String(decoding: try JSONEncoder().encode(keys.sorted()), as: UTF8.self)
          arguments.append(encoded.databaseValue)
          frontmatter = "(SELECT json_group_object(j.key, CASE WHEN j.type IN ('object','array') THEN json(j.value) ELSE j.value END) FROM json_each(detail,'$.frontmatter') j WHERE j.key IN (SELECT value FROM json_each(?)))"
          let pointers = keys.map { "/" + $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }.sorted()
          arguments.append(String(decoding: try JSONEncoder().encode(pointers), as: UTF8.self).databaseValue)
          metadata = "(SELECT json_group_object(m.key,json(m.value)) FROM json_each(detail,'$.valueMetadata') m WHERE EXISTS (SELECT 1 FROM json_each(?) p WHERE m.key=p.value OR substr(m.key,1,length(p.value)+1)=p.value||'/'))"
        }
        let projected = """
          json_object('path',path,'state',json_extract(detail,'$.state'),
            'frontmatter',\(frontmatter),'format',json_extract(detail,'$.format'),
            'diagnostics',json_extract(detail,'$.diagnostics'),
            'nativeTemporalPaths',CASE WHEN json_extract(detail,'$.evidenceVersion')=1 THEN json('[]') ELSE json_extract(detail,'$.nativeTemporalPaths') END,
            'nativeTemporalKinds',CASE WHEN json_extract(detail,'$.evidenceVersion')=1 THEN json('{}') ELSE json_extract(detail,'$.nativeTemporalKinds') END,
            'evidenceVersion',json_extract(detail,'$.evidenceVersion'),
            'valueMetadata',\(metadata))
          """
        arguments.append(scope.databaseValue)
        let cursor = try Row.fetchCursor(db, sql: "SELECT path,\(projected) AS detail FROM assessments WHERE scope_id=? ORDER BY path", arguments: StatementArguments(arguments))
        while let row = try cursor.next() {
          try Task.checkCancellation()
          let path: String = row["path"]
          guard acceptsPath(path) else { continue }
          if !includeNonMarkdown && !["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) { continue }
          guard selections.contains(where: { $0.isEmpty || path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }),
            seen.insert(path).inserted else { continue }
          let detail: String = row["detail"]
          bytes += detail.utf8.count
          result.decodedBytes = bytes
          guard bytes <= DocumentReadBudgets.aggregateBytes else {
            result.limitations.append("Survey snapshot budget exhausted")
            return result
          }
          do {
            var observation = try JSONDecoder().decode(MarkdownSurveyObservation.self, from: Data(detail.utf8))
            if observation.evidenceVersion == 1 {
              observation.nativeTemporalKinds = (observation.valueMetadata ?? [:]).filter { !["number", "integer"].contains($0.value.kind) }.mapValues(\.kind)
              observation.nativeTemporalPaths = Set(observation.nativeTemporalKinds.keys)
            }
            if requireQueryEvidence && observation.evidenceVersion != 1 && observation.state != .binary {
              observation.state = .unsupported
              observation.frontmatter = nil
              observation.diagnostics.append(.init(code: "query.snapshot.incompatible-evidence", severity: .error,
                domain: .frontmatter, location: "frontmatter", message: "Missing query-compatible typed evidence; refresh the index with a current md-utils before querying this file.",
              ))
            }
            // Non-text skips do not consume the source text-file budget. Apply
            // Markdown filtering before budgeting, matching direct survey scope.
            if observation.state != .binary {
              guard textFiles < maxFiles else {
                result.limitations.append("Survey snapshot budget exhausted")
                return result
              }
              textFiles += 1
            }
            result.observations.append(observation)
          }
          catch { result.limitations.append("Missing survey extraction evidence: \(path)") }
        }
      }
      result.observations.sort { $0.path < $1.path }
      return result
    }
  }

  /// Refreshes only explicitly requested directory scopes in an existing index.
  public static func refresh(
    root: Path, config: Path, directories: [String], includeNonMarkdown: Bool,
    verifyHashes: Bool, maxFiles: Int,
    projection: Projection = .full, requireQueryEvidence: Bool = false,
    acceptsPath: (String) -> Bool = { _ in true },
  ) async throws -> Self {
    let location = root + ".md-utils/index.sqlite"
    guard location.exists else { throw IndexProjectError("No existing index") }
    let url = URL(fileURLWithPath: location.string)
    guard url.resolvingSymlinksInPath() == url else { throw IndexProjectError("Index must not be a symlink") }
    let database = try SQLiteIndexDatabase(path: location.string)
    let evaluator = try IndexProjectEvaluator(root: root, configPath: config)
    let scopes = directories.map { IndexScope(path: $0, includeNonMarkdown: includeNonMarkdown) }
    let indexer = try CollectionIndexer(database: database, root: URL(fileURLWithPath: root.string))
    let refresh = try await indexer.updateMany(refreshing: scopes, fingerprint: evaluator.fingerprint,
      verifyHashes: verifyHashes, evaluate: evaluator.evaluate)
    let snapshot = try read(root: root, selections: directories, includeNonMarkdown: includeNonMarkdown, maxFiles: maxFiles, projection: projection, requireQueryEvidence: requireQueryEvidence, acceptsPath: acceptsPath)
    guard snapshot.generation == refresh.generation else { throw IndexProjectError("Survey generation changed; retry") }
    // Malformed frontmatter is legitimate evidence; operational failures lack an observation.
    guard snapshot.limitations.isEmpty else { throw IndexProjectError(snapshot.limitations.joined(separator: "; ")) }
    return snapshot
  }
}

public typealias SurveyIndexSnapshot = FrontmatterIndexSnapshot
