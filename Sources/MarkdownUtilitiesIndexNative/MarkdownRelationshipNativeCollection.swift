import Foundation
import GRDB
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit
import SystemPackage

/// Native snapshot construction using the existing index refresh/publication contract.
/// Relationship results are deliberately not persisted; #180 owns their invalidation.
public enum MarkdownRelationshipNativeCollection {
  public static func load(
    root: Path, noIndex: Bool = false, indexedOnly: Bool = false, verifyHashes: Bool = false,
    includeNonMarkdown: Bool = false, requestedScopes: [IndexScope]? = nil,
    configPath: Path? = nil,
    limits: MarkdownRelationshipLimits = .init(),
    warning: (String) -> Void = { _ in },
  ) async throws -> MarkdownRelationshipCollection {
    guard !(noIndex && indexedOnly) else { throw IndexProjectError("--no-index conflicts with --indexed-only") }
    let url = URL(fileURLWithPath: root.absolute().string).resolvingSymlinksInPath()
    let databaseURL = url.appendingPathComponent(".md-utils/index.sqlite")
    let hasIndex = FileManager.default.fileExists(atPath: databaseURL.path)
    if indexedOnly && !hasIndex { throw IndexProjectError("--indexed-only requires an existing compatible index and registered scopes") }
    if hasIndex && !noIndex {
      do {
        guard databaseURL.resolvingSymlinksInPath() == databaseURL else { throw IndexProjectError("Index must not be a symlink") }
        let database = try SQLiteIndexDatabase(path: databaseURL.path)
        let evaluator = try IndexProjectEvaluator(root: Path(url.path), configPath: configPath ?? Path(url.appendingPathComponent(".md-utils/md-utils.json").path))
        let scopes = try requestedScopes ?? (indexedOnly ? database.scopes() : [IndexScope(includeNonMarkdown: includeNonMarkdown)])
        guard !scopes.isEmpty else { throw IndexProjectError("--indexed-only requires registered scopes") }
        let lease = try await CollectionWriterLease.acquire(root: url)
        defer { withExtendedLifetime(lease) {} }
        let indexer = try CollectionIndexer(database: database, root: url)
        let report = try await indexer.updateMany(refreshing: scopes, indexedOnly: indexedOnly,
          writerLease: lease, fingerprint: evaluator.fingerprint, verifyHashes: verifyHashes,
          evaluate: evaluator.evaluate)
        // Cached relationship assessments intentionally lack collection context until #180.
        // Their unavailability does not invalidate successfully refreshed source evidence.
        if !indexedOnly && report.sourceErrorCount > 0 {
          throw IndexProjectError(report.errors.first ?? "Index refresh failed")
        }
        let baselines: [(String, String, Double, String)] = try database.serverRead { db in
          guard try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='published_generation'") == report.generation else {
            throw IndexProjectError("Index generation changed")
          }
          let placeholders = scopes.map { _ in "?" }.joined(separator: ",")
          let cursor = try Row.fetchCursor(db, sql: """
            SELECT DISTINCT f.path,f.hash,f.mtime,f.state FROM files f JOIN assessments a ON a.path=f.path
            WHERE a.scope_id IN (\(placeholders)) ORDER BY f.path
            """, arguments: StatementArguments(scopes.map(\.id)))
          var result: [(String, String, Double, String)] = []
          while let row = try cursor.next() {
            guard result.count < limits.records else { throw IndexProjectError("relationship.limit.exceeded: indexed record budget") }
            result.append((row["path"], row["hash"], row["mtime"], row["state"]))
          }
          return result
        }
        var records: [String: MarkdownRecord] = [:]
        var limitations = indexedOnly ? ["New files were not discovered. Coverage is limited to recorded candidates."] : []
        var bytes = 0
        for (path, hash, _, state) in baselines {
          try Task.checkCancellation()
          guard state == "ok", isMarkdown(path) || includeNonMarkdown else {
            if state != "ok" { limitations.append("Unavailable recorded candidate: \(path)") }
            continue
          }
          do {
            let record = try read(path: path, root: url, maximum: limits.bytes - bytes)
            guard record.revision?.rawValue == hash else { throw IndexProjectError("Source changed since index refresh: \(path)") }
            bytes += record.content.utf8.count
            records[path] = record
          } catch is CancellationError { throw CancellationError() }
          catch { limitations.append("\(path): \(error.localizedDescription)") }
        }
        // Basename coverage includes attachments. Indexed-only never performs this discovery.
        let paths = indexedOnly ? Set(baselines.filter { $0.3 == "ok" }.map(\.0)) : try discover(root: url, maximum: limits.candidates)
        try verify(records: &records, root: url, maximum: limits.bytes, limitations: &limitations)
        if !indexedOnly && Set(paths.filter { isMarkdown($0) || includeNonMarkdown }) != Set(records.keys) {
          limitations.append("Source coverage has unavailable or changed records")
        }
        let namespaceStable = indexedOnly ? false : try paths == discover(root: url, maximum: limits.candidates)
        if !indexedOnly && !namespaceStable { limitations.append("Candidate namespace changed during snapshot construction") }
        let generation = try database.freshness().generation
        guard generation == report.generation else { throw IndexProjectError("Index generation changed during materialization") }
        let retainedPaths = indexedOnly ? paths.filter { !isMarkdown($0) || records[$0] != nil } : paths
        return .init(identity: url.path, generation: String(generation), records: records, paths: retainedPaths,
          sourcesComplete: !indexedOnly && limitations.isEmpty,
          candidatesComplete: namespaceStable, completeExactPaths: Set(records.keys), limitations: limitations)
      } catch is CancellationError { throw CancellationError() }
      catch {
        if indexedOnly { throw error }
        warning("Warning: index relationship query unavailable (\(error)); reading source files directly.")
      }
    }
    return try await direct(root: url, limits: limits, includeNonMarkdown: includeNonMarkdown)
  }

  private static func direct(root: URL, limits: MarkdownRelationshipLimits, includeNonMarkdown: Bool) async throws -> MarkdownRelationshipCollection {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    return try await readOnly(root: root, limits: limits, includeNonMarkdown: includeNonMarkdown)
  }

  /// Authoritative bounded discovery without creating locks or touching an index.
  /// Callers applying edits already own the writer lease; previews own no lease.
  public static func readOnly(root: URL, limits: MarkdownRelationshipLimits = .init(),
    includeNonMarkdown: Bool = false,
  ) async throws -> MarkdownRelationshipCollection {
    let paths = try discover(root: root, maximum: limits.candidates)
    var records: [String: MarkdownRecord] = [:]
    var limitations: [String] = []
    var bytes = 0
    for path in paths.sorted() where isMarkdown(path) || includeNonMarkdown {
      try Task.checkCancellation()
      guard records.count < limits.records else {
        limitations.append("relationship.limit.exceeded: record budget")
        break
      }
      do {
        let record = try read(path: path, root: root, maximum: limits.bytes - bytes)
        bytes += record.content.utf8.count
        records[path] = record
      } catch is CancellationError { throw CancellationError() }
      catch { limitations.append("\(path): \(error.localizedDescription)") }
    }
    let generation = IndexFingerprint.combined(records.keys.sorted().map { $0 + (records[$0]?.revision?.rawValue ?? "") } + paths.sorted())
    try verify(records: &records, root: root, maximum: limits.bytes, limitations: &limitations)
    let namespaceStable = try paths == discover(root: root, maximum: limits.candidates)
    if !namespaceStable { limitations.append("Candidate namespace changed during snapshot construction") }
    return .init(identity: root.path, generation: generation, records: records, paths: paths,
      sourcesComplete: limitations.isEmpty, candidatesComplete: namespaceStable, limitations: limitations)
  }

  private static func verify(records: inout [String: MarkdownRecord], root: URL, maximum: Int,
    limitations: inout [String],
  ) throws {
    for path in records.keys.sorted() {
      do {
        let current = try read(path: path, root: root, maximum: maximum)
        guard current == records[path] else { throw IndexProjectError("Source revision changed during snapshot construction") }
      } catch is CancellationError { throw CancellationError() }
      catch {
        records.removeValue(forKey: path)
        limitations.append("\(path): \(error.localizedDescription)")
      }
    }
  }

  private static func discover(root: URL, maximum: Int) throws -> Set<String> {
    let cursor = try IndexSourceCursor(directory: root, includeNonMarkdown: true)
    var paths: Set<String> = []
    while let file = try cursor.next() {
      guard paths.count < maximum else { throw IndexProjectError("relationship.limit.exceeded: candidate discovery budget") }
      paths.insert(String(file.path.dropFirst(root.path.count + 1)))
    }
    return paths
  }

  private static func isMarkdown(_ path: String) -> Bool {
    ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
  }

  /// Bounded no-follow reads preserve raw text/native kinds and verify a stable read baseline.
  private static func read(path: String, root: URL, maximum: Int) throws -> MarkdownRecord {
    _ = try MarkdownRecordPath(path)
    let file = root.appendingPathComponent(path)
    guard maximum > 0, file.resolvingSymlinksInPath() == file else { throw IndexProjectError("Unavailable or over-budget source") }
    let before = try Stat(FilePath(file.path), followTargetSymlink: false)
    guard before.type == .regular else { throw IndexProjectError("Not a regular source file") }
    let handle = try FileDescriptor.open(FilePath(file.path), .readOnly, options: [.noFollow, .nonBlocking])
    defer { try? handle.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while data.count <= maximum {
      try Task.checkCancellation()
      let remaining = min(buffer.count, maximum + 1 - data.count)
      let count = try buffer.withUnsafeMutableBytes {
        try handle.read(into: UnsafeMutableRawBufferPointer(rebasing: $0.prefix(remaining)))
      }
      if count == 0 { break }
      data.append(contentsOf: buffer.prefix(count))
    }
    let after = try Stat(FilePath(file.path), followTargetSymlink: false)
    guard data.count <= maximum, before.size == after.size, before.st_mtim.tv_sec == after.st_mtim.tv_sec,
      before.st_mtim.tv_nsec == after.st_mtim.tv_nsec, let content = String(data: data, encoding: .utf8) else {
      throw IndexProjectError("Source changed, is not UTF-8, or exceeds byte budget")
    }
    let modified = Double(after.st_mtim.tv_sec) + Double(after.st_mtim.tv_nsec) / 1_000_000_000
    return .init(identity: .init(rawValue: path), content: content,
      context: .init(path: try MarkdownRecordPath(path), modificationDate: Date(timeIntervalSince1970: modified)),
      revision: .init(rawValue: IndexFingerprint.hash(data)))
  }
}
