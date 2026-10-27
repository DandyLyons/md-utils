import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

/// Snapshot-only survey evidence. Reading this type never inspects sources or definitions.
public struct SurveyIndexSnapshot: Sendable {
  public var observations: [MarkdownSurveyObservation]
  public var generation: Int
  public var limitations: [String]

  public static func read(
    root: Path, selections: [String], includeNonMarkdown: Bool, maxFiles: Int = 100_000,
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
      for scope in needed.sorted() {
        let cursor = try Row.fetchCursor(db, sql: "SELECT path,detail FROM assessments WHERE scope_id=? ORDER BY path", arguments: [scope])
        while let row = try cursor.next() {
          try Task.checkCancellation()
          let path: String = row["path"]
          guard selections.contains(where: { $0.isEmpty || path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }),
            seen.insert(path).inserted else { continue }
          let detail: String = row["detail"]
          bytes += detail.utf8.count
          guard result.observations.count < maxFiles, bytes <= 256 * 1024 * 1024 else {
            result.limitations.append("Survey snapshot budget exhausted")
            return result
          }
          do { result.observations.append(try JSONDecoder().decode(MarkdownSurveyObservation.self, from: Data(detail.utf8))) }
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
    let snapshot = try read(root: root, selections: directories, includeNonMarkdown: includeNonMarkdown, maxFiles: maxFiles)
    guard snapshot.generation == refresh.generation else { throw IndexProjectError("Survey generation changed; retry") }
    // Malformed frontmatter is legitimate evidence; operational failures lack an observation.
    guard snapshot.limitations.isEmpty else { throw IndexProjectError(snapshot.limitations.joined(separator: "; ")) }
    return snapshot
  }
}
