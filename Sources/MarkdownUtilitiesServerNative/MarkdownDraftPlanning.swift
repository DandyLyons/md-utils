import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesServer
import PathKit

/// Read-only configuration and authoritative source access; never initializes an index.
struct MarkdownDraftPlanning: Sendable {
  let root: URL
  let configurationFile: String?
  let planning: NativeEditPlanning
  let fingerprint: String

  init(root: URL, configurationFile: String?) throws {
    self.root = root; self.configurationFile = configurationFile
    let configuration = try MarkdownServerProjectLoader(projectRoot: Path(root.path),
      configurationFile: configurationFile.map { Path($0) }).loadConfiguration()
    let settings = try IndexConfiguration.load(root: root.path)
    let evaluator = try IndexProjectEvaluator(root: Path(root.path),
      configPath: Path(settings.configurationPath ?? root.appendingPathComponent(".md-utils/md-utils.json").path))
    let plan = try EndpointPlanCompiler(ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]),
      typeRegistry: evaluator.types).compile(configuration)
    planning = NativeEditPlanning(plan: plan, evaluator: evaluator)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    fingerprint = IndexFingerprint.combined([evaluator.fingerprint, String(decoding: try encoder.encode(plan), as: UTF8.self)])
  }

  func record(_ path: MarkdownRecordPath) throws -> MarkdownRecord? {
    guard !path.rawValue.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
      throw MarkdownMutationError(422, "draft.path-unsupported", "Draft sources must be visible to collection discovery.")
    }
    guard ["md", "markdown"].contains(URL(fileURLWithPath: path.rawValue).pathExtension.lowercased()) else {
      throw MarkdownMutationError(422, "source.unsupported", "Drafts require a Markdown file.")
    }
    let url = try NativeMutationFiles.url(root: root, path: path)
    guard let data = try NativeMutationFiles.read(url) else { return nil }
    guard let content = String(data: data, encoding: .utf8) else {
      throw MarkdownMutationError(422, "source.encoding", "Source must be UTF-8.")
    }
    let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    return MarkdownRecord(identity: .init(rawValue: path.rawValue), content: content,
      context: .init(path: path, modificationDate: modified), revision: .init(rawValue: IndexFingerprint.hash(data)))
  }

  func uuid(_ record: MarkdownRecord) async throws -> String? {
    guard let path = planning.plan.persistentIdentity?.path else { return nil }
    let analyzed = await MarkdownRecordAnalyzer.analyze(record)
    guard !analyzed.parseDiagnostics.contains(where: { $0.severity == .error }) else {
      throw MarkdownMutationError(503, "identity.incomplete", "Cannot establish identity from malformed source.")
    }
    let assessment = MarkdownRecordIdentityIndex.assess(analyzed,
      policy: .init(source: .frontmatter(path: path, format: .uuid)))
    guard assessment.status != .invalid else {
      throw MarkdownMutationError(422, "identity.invalid", "Configured persistent UUID is invalid.")
    }
    return assessment.primaryIdentity?.rawValue
  }

  func evidence<T>(_ body: (Database) throws -> T) throws -> T? {
    let url = root.appendingPathComponent(".md-utils/index.sqlite")
    try MarkdownDraftStore(root: root).safe(url)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    var config = Configuration(); config.readonly = true
    let queue = try DatabaseQueue(path: url.path, configuration: config)
    return try queue.read(body)
  }

  func epoch() throws -> String? {
    try evidence { db in
      guard try db.tableExists("index_metadata") else { return nil as String? }
      return try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'")
    } ?? nil
  }

  /// Retained coordinator move events can connect an original locator to a current one.
  /// Rebuilt/pruned epochs and ambiguous chains never authorize automatic following.
  func verifiedMove(_ draft: MarkdownDraft, to target: MarkdownRecordPath) throws -> Bool {
    guard let epoch = draft.provenanceEpoch else { return false }
    return try evidence { db in
      guard try db.tableExists("managed_events"), try db.tableExists("index_metadata"),
        try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'") == epoch,
        try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='provenance_pruned'") != "1" else { return false }
      var path = draft.path.rawValue
      var visited = Set<String>()
      var since = draft.created.timeIntervalSince1970
      for _ in 0..<64 {
        guard visited.insert(path).inserted else { return false }
        let rows = try Row.fetchAll(db, sql: "SELECT payload FROM managed_events WHERE source_path=? AND observed_at>=? ORDER BY observed_at LIMIT 257",
          arguments: [path, since])
        guard rows.count <= 256 else { return false }
        var moves: [ManagedDocumentEvent] = []
        for row in rows {
          let payload: Data = row["payload"]
          guard payload.count <= 32_768 else { return false }
          let event = try JSONDecoder().decode(ManagedDocumentEvent.self, from: payload)
          if event.kind == .move, event.confirmation == .coordinator,
            event.sourceRevision == draft.baseline.rawValue, event.revision == draft.baseline.rawValue {
            moves.append(event)
          }
        }
        guard moves.count == 1, let move = moves.first else { return false }
        guard move.observedAt >= since else { return false }
        since = move.observedAt
        path = move.path
        if path == target.rawValue { return true }
      }
      return false
    } ?? false
  }

  func checkReceipts(path: MarkdownRecordPath, excluding attempt: String? = nil) throws {
    let directory = root.appendingPathComponent(".md-utils/mutations/", isDirectory: true)
    try MarkdownDraftStore(root: root).safe(directory)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let cursor = try IndexSourceCursor(directory: directory, includeNonMarkdown: true)
    var count = 0
    while let url = try cursor.next() {
      guard url.pathExtension == "json" else { continue }
      count += 1
      guard count <= 10_000 else { throw MarkdownMutationError(503, "draft.receipt-limit", "Too many receipts to establish a safe target.") }
      let receipt = try readReceipt(url)
      if receipt.id != attempt, receipt.state != .completed, receipt.state != .abandoned,
        receipt.path == path || receipt.sourcePath == path {
        throw MarkdownMutationError(409, "recovery.required", "An unresolved mutation reserves this path; resolve it before applying drafts.")
      }
    }
  }

  func readReceipt(_ url: URL) throws -> MarkdownMutationReceipt {
    try MarkdownDraftStore(root: root).safe(url)
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let data = try handle.read(upToCount: 64 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 64 * 1024 * 1024 else { throw MarkdownMutationError(413, "receipt.too-large", "Receipt exceeds 64 MiB.") }
    return try JSONDecoder().decode(MarkdownMutationReceipt.self, from: data)
  }

  func resolve(_ draft: MarkdownDraft) async throws -> (MarkdownRecord, String) {
    guard draft.configurationFingerprint == fingerprint, draft.uuidPath == planning.plan.persistentIdentity?.path else {
      throw MarkdownMutationError(409, "draft.configuration-changed", "Resource or validation configuration changed; discard and restage after review.")
    }
    let original = try record(draft.path)
    if let original, try await uuid(original) != draft.uuid {
      throw MarkdownMutationError(409, "draft.target-replaced", "The original path now has a different persistent identity.")
    }
    guard let uuid = draft.uuid else {
      guard let original else { throw MarkdownMutationError(409, "draft.target-missing", "The source is missing; no UUID is available to resolve relocation.") }
      guard original.revision == draft.baseline else { throw stale() }
      return (original, "Original path and baseline bytes match; no persistent UUID was recorded.")
    }
    let cursor = try IndexSourceCursor(directory: root)
    var holders: [MarkdownRecordPath] = []
    while let url = try cursor.next() {
      let path = try MarkdownRecordPath(String(url.path.dropFirst(root.path.count + 1)))
      guard let record = try record(path) else { throw MarkdownMutationError(503, "identity.incomplete", "A file disappeared during identity discovery.") }
      if try await self.uuid(record) == uuid {
        guard holders.count < 256 else { throw MarkdownMutationError(409, "identity.ambiguous", "Too many UUID holders; select and repair the intended target.") }
        holders.append(path)
      }
    }
    guard holders.count == 1, let path = holders.first else {
      if holders.isEmpty { throw MarkdownMutationError(409, "draft.target-missing", "Complete discovery found no current UUID holder; the draft remains unresolved.") }
      throw MarkdownMutationError(409, "identity.ambiguous", "Multiple files hold the draft UUID: \(holders.map(\.rawValue).sorted().joined(separator: ", ")). Inspect index provenance and select the intended target.")
    }
    guard let current = try record(path), try await self.uuid(current) == uuid else {
      throw MarkdownMutationError(409, "draft.target-changed", "The discovered target changed during reconciliation.")
    }
    guard current.revision == draft.baseline else { throw stale() }
    if path == draft.path { return (current, "Original path, persistent UUID, and baseline bytes match.") }
    guard try verifiedMove(draft, to: path) else {
      throw MarkdownMutationError(409, "draft.relocation-unconfirmed", "UUID found at \(path.rawValue), but retained evidence does not confirm a managed move. Explicitly restage against that path after review.")
    }
    return (current, "Coordinator-confirmed managed move from \(draft.path.rawValue) to \(path.rawValue); UUID and baseline bytes match.")
  }

  func preview(_ draft: MarkdownDraft) async throws -> MarkdownDraftReport {
    var report = MarkdownDraftReport(draft)
    let (source, resolution) = try await resolve(draft)
    guard let path = source.context.path else { throw RecordStoreError.unavailable }
    report.path = path; report.resolution = resolution; report.originalSource = source.content
    try checkReceipts(path: draft.path, excluding: draft.attemptID)
    try checkReceipts(path: path, excluding: draft.attemptID)
    guard let resource = planning.plan.resources.first(where: { $0.name == draft.resource }) else {
      throw MarkdownMutationError(405, "operation.disabled", "The configured resource no longer exists.")
    }
    let validation = try await planning.edit(draft.request(),
      source: ResourceMutationSource(record: source, expectedRevision: draft.baseline), resource: resource)
    report.proposedSource = validation.proposal.record.content
    report.proposedRevision = .init(rawValue: IndexFingerprint.hash(Data(validation.proposal.record.content.utf8)))
    report.diagnostics = validation.diagnostics; report.conformanceChanges = validation.changes
    if !validation.isValid {
      report.failureCode = "record.invalid"; report.failureMessage = "The complete proposal failed validation."
      return report
    }
    let proposed = validation.proposal.record
    let checks = try await planning.constraints(proposed, projection: planning.project(proposed))
    let cursor = try IndexSourceCursor(directory: root)
    while let url = try cursor.next() {
      let otherPath = try MarkdownRecordPath(String(url.path.dropFirst(root.path.count + 1)))
      if otherPath == path { continue }
      guard let other = try record(otherPath) else { throw MarkdownMutationError(503, "identity.incomplete", "A file disappeared during constraint assessment.") }
      try await planning.validateOther(other, checks: checks)
    }
    guard try record(path)?.revision == draft.baseline else { throw stale() }
    let current = try MarkdownDraftPlanning(root: root, configurationFile: configurationFile)
    guard current.fingerprint == fingerprint else {
      throw MarkdownMutationError(409, "draft.configuration-changed", "Configuration changed during planning.")
    }
    return report
  }

  private func stale() -> MarkdownMutationError {
    MarkdownMutationError(412, "revision.stale", "Source differs from the draft's original SHA-256 baseline; no automatic merge or rebase was performed.")
  }
}
