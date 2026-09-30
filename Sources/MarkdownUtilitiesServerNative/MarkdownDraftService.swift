import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer
import PathKit

/// Stages and applies explicit edits without an HTTP process or authoritative SQLite rows.
///
/// Drafts live under `.md-utils/drafts/`; receipts remain under `.md-utils/mutations/`.
/// Mutating calls coordinate through the collection OS writer lease. Read-only calls
/// do not initialize, refresh, repair, or prune an index. External editors do not
/// honor the lease and can still race final filesystem checks.
public struct MarkdownDraftService: Sendable {
  /// Canonical native collection root used for all relative document paths.
  public let root: URL
  /// Optional server resource configuration file; nil uses the conventional location.
  public let configurationFile: String?
  // Test-only fault injection reuses the coordinator's durable boundary checkpoints.
  var mutationCheckpoint: (@Sendable (MutationBoundary) throws -> Void)?
  private var store: MarkdownDraftStore { .init(root: root) }

  /// Binds a service without creating any directories or opening SQLite.
  /// - Parameters:
  ///   - projectRoot: Native project directory, absolute or working-directory-relative.
  ///   - configurationFile: Optional resource configuration path accepted by the server loader.
  public init(projectRoot: String, configurationFile: String? = nil) {
    root = URL(fileURLWithPath: Path(projectRoot).absolute().string).resolvingSymlinksInPath()
    self.configurationFile = configurationFile
  }

  /// Returns stored draft IDs in lexicographic order without loading source or changing state.
  /// - Returns: At most 10,000 lowercase UUIDs, including completed drafts.
  /// - Throws: Enumeration, unsafe-path, or count-limit errors.
  public func draftIDs() throws -> [String] { try store.ids() }

  /// Reads one versioned draft without updating its lifecycle or baseline.
  /// - Parameter id: Lowercase draft UUID.
  /// - Returns: The independently persisted draft envelope.
  /// - Throws: Missing, malformed, oversized, or unsupported drafts and native read errors.
  public func draft(_ id: String) throws -> MarkdownDraft { try store.load(id) }

  /// Persists one explicit patch/replace intent against a caller-supplied source revision.
  ///
  /// Failed content validation can be staged for later inspection. Source identity,
  /// baseline, resource opt-ins, and the request envelope must be valid. No source
  /// or index is changed. Another active draft for the same path or UUID is rejected.
  /// - Parameters:
  ///   - path: Collection-relative visible Markdown source locator.
  ///   - resource: Explicit configured writable resource name.
  ///   - revision: SHA-256 of the exact source against which the edit was authored.
  ///   - request: Shared patch or replacement envelope; defaults are not invented.
  /// - Returns: A durably staged pending draft with captured identity/configuration evidence.
  /// - Throws: Stale baseline, invalid identity, disabled operation, duplicate draft, or persistence errors.
  public func stage(path: MarkdownRecordPath, resource: String, revision: MarkdownRecordRevision,
    request: MarkdownMutationRequest,
  ) async throws -> MarkdownDraft {
    guard request.operation == .patch || request.operation == .replace else {
      throw MarkdownMutationError(400, "draft.operation", "Drafts support patch and replace only.")
    }
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    let context = try MarkdownDraftPlanning(root: root, configurationFile: configurationFile)
    guard let selected = context.planning.plan.resources.first(where: { $0.name == resource }),
      selected.mutations?.operations.contains(request.operation) == true else {
      throw MarkdownMutationError(405, "operation.disabled", "The resource must explicitly enable this operation.")
    }
    guard let source = try context.record(path) else { throw MarkdownMutationError(404, "record.not-found", "Source does not exist.") }
    guard source.revision == revision else { throw MarkdownMutationError(412, "revision.stale", "Source differs from the supplied baseline.") }
    guard try await context.planning.project(source)?.memberships.contains(where: { $0.resourceName == resource }) == true else {
      throw MarkdownMutationError(404, "record.not-found", "The resource does not select this document.")
    }
    try context.checkReceipts(path: path)
    let uuid = try await context.uuid(source)
    for id in try store.ids() {
      let draft = try store.load(id)
      if draft.state != .completed && (draft.path == path || (uuid != nil && draft.uuid == uuid)) {
        throw MarkdownMutationError(409, "draft.duplicate", "An active draft already addresses this path or UUID.")
      }
    }
    guard try context.record(path)?.revision == revision else {
      throw MarkdownMutationError(412, "revision.stale", "Source changed during staging.")
    }
    let draft = MarkdownDraft(path: path, resource: resource, baseline: revision, uuid: uuid,
      uuidPath: context.planning.plan.persistentIdentity?.path, epoch: try context.epoch(),
      fingerprint: context.fingerprint, request: request)
    try store.save(draft)
    return draft
  }

  /// Removes an unsubmitted or completed draft, preserving canonical source and receipts.
  /// - Parameter id: Lowercase draft UUID.
  /// - Throws: Submitted/unresolved attempts, missing drafts, or filesystem errors.
  public func discard(_ id: String) async throws {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    try store.discard(store.load(id))
  }

  /// Plans one draft from current authoritative source without persistent side effects.
  /// - Parameter id: Lowercase draft UUID.
  /// - Returns: Concrete before/after source and assessments, or an explicit conflict/recovery report.
  /// - Throws: Malformed drafts, cancellation, or unavailable configuration. Planning conflicts are returned.
  public func preview(_ id: String) async throws -> MarkdownDraftReport {
    let draft = try store.load(id)
    if draft.state == .completed { return MarkdownDraftReport(draft) }
    let context = try MarkdownDraftPlanning(root: root, configurationFile: configurationFile)
    if draft.attemptID != nil { return try attemptReport(draft, context: context) }
    do { return try await context.preview(draft) }
    catch is CancellationError { throw CancellationError() }
    catch { return failure(draft, error: error) }
  }

  /// Preflights and sequentially applies drafts, streaming bounded per-draft reports.
  ///
  /// Dry-run performs no persistent writes, including no draft updates, refreshes,
  /// recovery, receipt pruning, or lock-file creation. Apply holds the collection
  /// lease, recovers confirmed existing commits, preflights all selected drafts,
  /// then replans each file immediately before its shared mutation. The first
  /// execution failure stops later writes; already committed files are not rolled back.
  /// - Parameters:
  ///   - ids: Specific draft UUIDs; an empty list selects all noncompleted stored drafts.
  ///   - dryRun: Whether to produce previews without persisting anything.
  ///   - report: Synchronously receives each result; throwing stops execution without rollback.
  /// - Returns: True when all selected drafts planned successfully or completed publication.
  /// - Throws: Cancellation, malformed selection/storage, setup errors, or report callback errors.
  public func apply(ids: [String] = [], dryRun: Bool = false,
    report: @Sendable (MarkdownDraftReport) throws -> Void,
  ) async throws -> Bool {
    let selected = try selection(ids)
    if dryRun {
      var success = true
      for id in selected {
        try Task.checkCancellation()
        let result = try await preview(id)
        try report(result); success = success && result.succeeded
      }
      return success
    }
    guard !selected.isEmpty else { return true }
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    let repository = try IndexedMarkdownRepository(projectRoot: root.path, configurationFile: configurationFile)
    await repository.setMutationCheckpoint(mutationCheckpoint)
    try await repository.recoverMutations(lease: lease)
    var ready = true
    var paths = Set<MarkdownRecordPath>()
    var reported = Set<String>()
    for id in selected {
      var draft = try store.load(id)
      if draft.state == .completed { try report(MarkdownDraftReport(draft)); reported.insert(id); continue }
      let result = try await preview(id)
      if let receipt = result.receipt, receipt.state == .completed {
        draft.state = .completed; draft.failureCode = nil; draft.failureMessage = nil
        try store.save(draft)
        if let attempt = draft.attemptID { try store.pin(attempt, retain: false) }
        try report(result)
        reported.insert(id)
        continue
      }
      if !result.succeeded || result.receipt != nil {
        draft.state = result.state == .pending ? .conflict : result.state
        draft.failureCode = result.failureCode; draft.failureMessage = result.failureMessage
        try store.save(draft); try report(result); reported.insert(id); ready = false
      } else if let path = result.path, !paths.insert(path).inserted {
        let result = failure(draft, error: MarkdownMutationError(409, "draft.duplicate", "Selected drafts resolve to the same source path."))
        draft.state = .conflict; draft.failureCode = result.failureCode; draft.failureMessage = result.failureMessage
        try store.save(draft); try report(result); reported.insert(id); ready = false
      }
    }
    guard ready else {
      for id in selected where !reported.contains(id) {
        var result = MarkdownDraftReport(try store.load(id))
        result.failureCode = "draft.unattempted"
        result.failureMessage = "Preflight found a blocker; this draft was not submitted."
        try report(result)
      }
      return false
    }
    for id in selected {
      try Task.checkCancellation()
      var draft = try store.load(id)
      if draft.state == .completed { continue }
      let result = try await preview(id)
      guard result.succeeded, let path = result.path else {
        draft.state = .conflict; draft.failureCode = result.failureCode; draft.failureMessage = result.failureMessage
        try store.save(draft); try report(result)
        try reportUnattempted(selected, after: id, report: report)
        return false
      }
      let attempt = UUID().uuidString.lowercased()
      draft.state = .submitted; draft.attemptID = attempt; draft.resolvedPath = path
      draft.failureCode = nil; draft.failureMessage = nil
      // Pin before submitting: a completed receipt must survive a crash before draft acknowledgement.
      try store.pin(attempt, retain: true)
      try store.save(draft)
      var output: MarkdownDraftReport
      do {
        let receipt = try await repository.mutate(resource: draft.resource, identity: nil, path: path,
          request: draft.request(), revision: draft.baseline, idempotencyKey: nil, lease: lease, attemptID: attempt)
        var result = result
        result.originalSource = nil; result.proposedSource = nil
        result.receipt = receipt
        update(&draft, receipt: receipt)
        try store.save(draft)
        if draft.state == .completed { try store.pin(attempt, retain: false) }
        result.state = draft.state
        if draft.state != .completed {
          result.failureCode = draft.failureCode; result.failureMessage = draft.failureMessage
        }
        output = result
      } catch {
        // Only a missing journal immediately after a rejected fresh submission proves no write began.
        let receiptURL = root.appendingPathComponent(".md-utils/mutations/\(attempt).json")
        if !FileManager.default.fileExists(atPath: receiptURL.path) {
          draft.attemptID = nil; draft.resolvedPath = nil; draft.state = .conflict
          try store.pin(attempt, retain: false)
        } else { draft.state = .recoveryRequired }
        let result = failure(draft, error: error)
        draft.failureCode = result.failureCode; draft.failureMessage = result.failureMessage
        try store.save(draft); try report(result)
        try reportUnattempted(selected, after: id, report: report)
        if error is CancellationError { throw CancellationError() }
        return false
      }
      try report(output)
      if draft.state != .completed {
        try reportUnattempted(selected, after: id, report: report)
        return false
      }
    }
    return true
  }

  /// Resolves a submitted attempt using the existing operator-confirmation contract.
  ///
  /// An abandoned attempt becomes pending with the original baseline. A confirmed
  /// commit republishes and completes without reapplying its edit. A missing receipt
  /// permits only explicit confirmNotCommitted with unchanged baseline source.
  /// - Parameters:
  ///   - id: Lowercase draft UUID.
  ///   - decision: Explicit operator assertion, verified against authoritative bytes.
  /// - Returns: Updated durable draft state.
  /// - Throws: Inconsistent current source, missing attempt, recovery, or persistence errors.
  public func resolve(_ id: String, decision: MarkdownRecoveryDecision) async throws -> MarkdownDraft {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    var draft = try store.load(id)
    guard let attempt = draft.attemptID, let path = draft.resolvedPath else {
      throw MarkdownMutationError(409, "draft.no-attempt", "This draft has no submitted attempt to resolve.")
    }
    let context = try MarkdownDraftPlanning(root: root, configurationFile: configurationFile)
    let url = root.appendingPathComponent(".md-utils/mutations/\(attempt).json")
    if FileManager.default.fileExists(atPath: url.path) {
      let repository = try IndexedMarkdownRepository(projectRoot: root.path, configurationFile: configurationFile)
      let receipt = try await repository.resolveOperation(resource: draft.resource, id: attempt, decision: decision, lease: lease)
      if receipt.state == .abandoned {
        draft.state = .pending; draft.attemptID = nil; draft.resolvedPath = nil
      } else { update(&draft, receipt: receipt) }
    } else {
      guard decision == .confirmNotCommitted, try context.record(path)?.revision == draft.baseline else {
        throw MarkdownMutationError(409, "draft.receipt-missing", "Missing receipt requires explicit confirmNotCommitted and unchanged baseline source.")
      }
      draft.state = .pending; draft.attemptID = nil; draft.resolvedPath = nil
    }
    if draft.state == .pending || draft.state == .completed {
      draft.failureCode = nil; draft.failureMessage = nil
    }
    try store.save(draft)
    if draft.state == .pending || draft.state == .completed { try store.pin(attempt, retain: false) }
    return draft
  }

  private func selection(_ ids: [String]) throws -> [String] {
    guard Set(ids).count == ids.count else { throw MarkdownMutationError(400, "draft.selection", "Draft IDs must be unique.") }
    if !ids.isEmpty {
      for id in ids { _ = try store.load(id) }
      return ids.sorted()
    }
    return try store.ids().filter { try store.load($0).state != .completed }
  }

  private func attemptReport(_ draft: MarkdownDraft, context: MarkdownDraftPlanning) throws -> MarkdownDraftReport {
    var report = MarkdownDraftReport(draft)
    guard let attempt = draft.attemptID else { return report }
    let url = root.appendingPathComponent(".md-utils/mutations/\(attempt).json")
    guard FileManager.default.fileExists(atPath: url.path) else {
      return failure(draft, error: MarkdownMutationError(409, "draft.receipt-missing", "The submitted attempt has no receipt; explicit recovery is required."))
    }
    let receipt = try context.readReceipt(url)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard receipt.id == attempt, receipt.resource == draft.resource, receipt.operation == draft.operation,
      receipt.path == draft.resolvedPath, receipt.baseline == draft.baseline,
      receipt.requestHash == IndexFingerprint.hash(try encoder.encode(draft.payload)) else {
      return failure(draft, error: MarkdownMutationError(409, "draft.attempt-mismatch", "Draft and receipt intent do not match."))
    }
    report.receipt = receipt; report.path = receipt.path
    var reconciled = draft; update(&reconciled, receipt: receipt)
    report.state = reconciled.state
    report.failureCode = reconciled.failureCode; report.failureMessage = reconciled.failureMessage
    return report
  }

  private func update(_ draft: inout MarkdownDraft, receipt: MarkdownMutationReceipt) {
    switch receipt.state {
    case .completed: draft.state = .completed; draft.failureCode = nil; draft.failureMessage = nil
    case .committed:
      draft.state = .publicationPending; draft.failureCode = "mutation.publication-pending"
      draft.failureMessage = "Source committed; publication must finish without rewriting source."
    case .prepared, .recoveryRequired, .abandoned:
      draft.state = .recoveryRequired; draft.failureCode = "mutation.recovery-required"
      draft.failureMessage = "Inspect the receipt and explicitly resolve the attempt before retrying."
    }
  }

  private func failure(_ draft: MarkdownDraft, error: any Error) -> MarkdownDraftReport {
    var report = MarkdownDraftReport(draft)
    report.state = draft.attemptID == nil ? .conflict : .recoveryRequired
    report.failureCode = (error as? MarkdownMutationError)?.code
      ?? (error as? ResourceCodecError)?.diagnostic.code ?? "draft.planning-failed"
    report.failureMessage = error.localizedDescription
    if let codec = error as? ResourceCodecError { report.diagnostics = [codec.diagnostic] }
    else { report.diagnostics = (error as? MarkdownMutationError)?.diagnostics ?? [] }
    return report
  }

  private func reportUnattempted(_ ids: [String], after id: String,
    report: @Sendable (MarkdownDraftReport) throws -> Void,
  ) throws {
    guard let index = ids.firstIndex(of: id) else { return }
    for next in ids.dropFirst(index + 1) {
      let draft = try store.load(next)
      if draft.state == .completed { continue }
      var result = MarkdownDraftReport(draft)
      result.failureCode = "draft.unattempted"; result.failureMessage = "An earlier draft stopped this batch; this draft was not submitted."
      try report(result)
    }
  }
}
