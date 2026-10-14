import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesServer
import PathKit

public struct MarkdownRuleFixReview: Sendable {
  public let review: MarkdownFixItReview
  public let suggestions: MarkdownRelationshipFixSuggestions
  public let token: String
  public let collection: MarkdownRelationshipCollection
  let evaluator: IndexProjectEvaluator
}

/// Preview-first rule fixing over authoritative snapshots. Explicit application
/// extends shared drafts, leased record writes and receipts, including recovery.
public struct MarkdownRuleFixService: Sendable {
  public let root: URL
  public let configPath: String
  public let rules: [String]?
  var mutationCheckpoint: (@Sendable (MutationBoundary) throws -> Void)?
  private var store: MarkdownDraftStore { .init(root: root) }
  private var journal: NativeMutationJournal { .init(root: root) }

  public init(projectRoot: String, configPath: String, rules: [String]? = nil) {
    root = URL(fileURLWithPath: Path(projectRoot).absolute().string).resolvingSymlinksInPath()
    self.configPath = Path(configPath).absolute().string
    self.rules = rules
  }

  public func review(includeRecommendations: Bool = false) async throws -> MarkdownRuleFixReview {
    let (evaluator, collection, evidence) = try await snapshot()
    guard let registry = evaluator.rules else { throw IndexProjectError("No configured rules.") }
    let suggestions = try await MarkdownRelationshipFixPlanner(registry: registry).suggest(collection: collection,
      ruleNames: rules, includeRecommendations: includeRecommendations,
    )
    let review = try MarkdownFixItReview(evidence: evidence, proposals: suggestions.proposals)
    return .init(review: review, suggestions: suggestions, token: try MarkdownFixItReviewToken.token(for: review),
      collection: collection, evaluator: evaluator,
    )
  }

  public func preview(_ current: MarkdownRuleFixReview, numbers: [Int], automatic: Bool = false,
    includeRecommendations: Bool = false,
  ) async throws -> MarkdownFixItOverlay {
    let selected = try current.review.select(numbers: numbers, automatic: automatic, includeRecommendations: includeRecommendations)
    guard let registry = current.evaluator.rules else { throw IndexProjectError("No configured rules.") }
    let result = try await MarkdownRelationshipFixPlanner(registry: registry).preview(collection: current.collection,
      proposals: selected.map { current.review.proposals[$0 - 1] },
    )
    for path in result.records.keys where result.records[path]?.content != current.collection.records[path]?.content {
      guard (result.records[path]?.content.utf8.count ?? 0) <= 8 * 1024 * 1024,
        (current.collection.records[path]?.content.utf8.count ?? 0) <= 8 * 1024 * 1024 else {
        throw IndexProjectError("Fix-It source or proposed document exceeds the shared 8 MiB mutation limit: \(path)")
      }
    }
    try await validateServerProtection(before: current.collection.records, after: result.records, evaluator: current.evaluator)
    // Preview the same ordered intermediate states that persistence will use.
    // This makes partial-state blockers visible before any draft is staged.
    var intermediate = current.collection
    var blockers: [String] = []
    for path in result.records.keys.sorted() where result.records[path]?.content != current.collection.records[path]?.content {
      guard let record = result.records[path] else { continue }
      let next = MarkdownRelationshipFixPlanner.replacing([path: record], in: intermediate)
      let check = try await MarkdownRelationshipFixPlanner(registry: registry).assessTransition(from: intermediate, to: next)
      blockers += check.blockers.map { "After writing \(path): " + $0 }
      intermediate = next
    }
    return result.addingBlockers(blockers)
  }

  /// Rebuild and verify the review before persisting any draft or source. Batch
  /// preflight includes every intermediate state, so no known-invalid partial
  /// state is deliberately written merely because the final overlay passes.
  public func apply(token: String, numbers: [Int], automatic: Bool = false, includeRecommendations: Bool = false,
    report: @Sendable (MarkdownDraftReport) throws -> Void,
  ) async throws -> Bool {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    let current = try await review(includeRecommendations: includeRecommendations)
    let selected = try MarkdownFixItReviewToken.select(token, from: current.review, numbers: numbers,
      automatic: automatic, includeRecommendations: includeRecommendations,
    )
    guard !selected.isEmpty else { throw IndexProjectError("No fixes selected; no files changed.") }
    let proposals = selected.map { current.review.proposals[$0 - 1] }
    let overlay = try await preview(current, numbers: selected, includeRecommendations: includeRecommendations)
    guard overlay.blockers.isEmpty else { throw IndexProjectError(overlay.blockers.joined(separator: "\n")) }
    let changed = overlay.records.keys.sorted().filter { overlay.records[$0]?.content != current.collection.records[$0]?.content }
    if changed.isEmpty { return true }
    try assertUnowned(changed)
    let grouped = Dictionary(grouping: proposals, by: { $0.path.rawValue })
    var drafts: [MarkdownDraft] = []
    var revisions: [String: MarkdownRecordRevision] = [:]
    for path in changed {
      guard let original = current.collection.records[path], let proposed = overlay.records[path], let baseline = original.revision else {
        throw MarkdownFixItReviewError.missingRevision(path)
      }
      let payload = try await patch(before: original, after: proposed)
      let request = try MarkdownMutationRequest(operation: .patch, data: JSONEncoder().encode(payload))
      drafts.append(.init(path: try MarkdownRecordPath(path), resource: "__rules_fix__", baseline: baseline,
        uuid: nil, uuidPath: nil, epoch: nil, fingerprint: current.review.evidence.configuration, request: request,
      ))
      revisions[path] = .init(rawValue: IndexFingerprint.hash(Data(proposed.content.utf8)))
    }
    let batch = UUID().uuidString.lowercased()
    let ids = drafts.map(\.id)
    var bytes = 0
    for index in drafts.indices {
      drafts[index].fixItContext = .init(version: 1, batch: batch, draftIDs: ids, configPath: configPath, rules: rules,
        evidence: current.review.evidence, contexts: current.collection.records.mapValues(\.context),
        edits: grouped[drafts[index].path.rawValue]?.map(\.fixIt) ?? [],
        originalContent: current.collection.records[drafts[index].path.rawValue]?.content ?? "", expectedRevisions: revisions,
      )
      bytes += try JSONEncoder().encode(drafts[index]).count
      guard bytes <= 64 * 1024 * 1024 else { throw IndexProjectError("Selected durable drafts exceed 64 MiB; review a smaller selection.") }
    }
    var saved: [MarkdownDraft] = []
    do {
      for draft in drafts { try store.save(draft); saved.append(draft) }
    } catch {
      for draft in saved {
        var result = MarkdownDraftReport(draft); result.path = draft.path
        result.failureCode = "fix.staging-incomplete"
        result.failureMessage = "No source writes began. Discard this unsubmitted draft and preview again: " + error.localizedDescription
        try report(result)
      }
      throw error
    }
    return try await resume(ids: ids, lease: lease, report: report)
  }

  /// Resume an entire stored batch. Confirmed receipts advance expected evidence;
  /// matching proposed bytes without a receipt never establish a prior commit.
  func resume(ids: [String], lease: CollectionWriterLease, report: @Sendable (MarkdownDraftReport) throws -> Void) async throws -> Bool {
    let drafts = try batch(ids)
    var stopped = false
    for initial in drafts {
      var draft = try store.load(initial.id)
      if stopped {
        var result = MarkdownDraftReport(draft); result.path = draft.path
        result.failureCode = "draft.unattempted"; result.failureMessage = "An earlier Fix-It stopped this batch."
        try report(result); continue
      }
      do {
        if draft.attemptID != nil {
          let recovered = try await recover(&draft, lease: lease)
          try report(recovered)
          if !recovered.succeeded { stopped = true }
          continue
        }
        let planning = try await plan(draft)
        guard planning.result.succeeded, let proposed = planning.proposed else {
          draft.state = .conflict; draft.failureCode = planning.result.failureCode; draft.failureMessage = planning.result.failureMessage
          try store.save(draft); try report(planning.result); stopped = true; continue
        }
        let attempt = UUID().uuidString.lowercased()
        draft.state = .submitted; draft.attemptID = attempt; draft.resolvedPath = draft.path
        try store.pin(attempt, retain: true)
        try store.save(draft)
        var receipt = MarkdownMutationReceipt(id: attempt, resource: draft.resource, operation: .patch, path: draft.path,
          revision: planning.result.proposedRevision, baseline: draft.baseline,
          requestHash: try requestHash(draft), keyHash: nil,
        )
        receipt.fixItDraftID = draft.id
        try journal.write(receipt)
        do {
          try mutationCheckpoint?(.prepared)
          // Recheck every supporting record/candidate after durable intent and
          // immediately before the existing atomic per-file revision check.
          _ = try await verifiedSnapshot(draft, allowPrepared: true)
          var write = proposed; write.revision = nil
          _ = try CoordinatedNativeRecordStore.persist(write, revision: draft.baseline, root: root, lease: lease)
          receipt.fixItCommittedContext = try await MarkdownRelationshipNativeCollection.readOnly(root: root).records[draft.path.rawValue]?.context
          try mutationCheckpoint?(.persisted)
          receipt.state = .committed; receipt.sourceCommitted = true
          try journal.write(receipt)
          try mutationCheckpoint?(.committed)
        } catch {
          if !receipt.sourceCommitted { receipt.state = .recoveryRequired }
          try journal.write(receipt)
          if error is CancellationError { throw CancellationError() }
        }
        let result = try await recover(&draft, lease: lease)
        try report(result)
        if !result.succeeded { stopped = true }
      } catch {
        draft.state = draft.attemptID == nil ? .conflict : ((try? checkedReceipt(draft).sourceCommitted) == true ? .publicationPending : .recoveryRequired)
        draft.failureCode = "fix.apply.failed"; draft.failureMessage = error.localizedDescription
        try store.save(draft)
        var result = MarkdownDraftReport(draft); result.path = draft.path
        result.failureCode = draft.failureCode; result.failureMessage = draft.failureMessage
        try report(result); stopped = true
        if error is CancellationError { throw CancellationError() }
      }
    }
    if stopped { return false }
    let (evaluator, collection, _) = try await snapshot()
    guard let registry = evaluator.rules else { throw IndexProjectError("No configured rules.") }
    return try await MarkdownRuleCollectionEvaluator(registry: registry).evaluate(collection: collection, ruleNames: rules).outcome == .pass
  }

  func previewDraft(_ draft: MarkdownDraft) async throws -> MarkdownDraftReport {
    if draft.attemptID != nil { return try receiptReport(draft) }
    return try await plan(draft).result
  }

  func resolve(_ draft: MarkdownDraft, decision: MarkdownRecoveryDecision, lease: CollectionWriterLease) async throws -> MarkdownDraft {
    guard let attempt = draft.attemptID else { throw IndexProjectError("Draft has no submitted attempt.") }
    var draft = draft
    let url = try journal.url(attempt)
    let actual = try NativeMutationFiles.read(NativeMutationFiles.url(root: root, path: draft.path)).map(IndexFingerprint.hash)
    if FileManager.default.fileExists(atPath: url.path) {
      var receipt = try checkedReceipt(draft)
      let expected = decision == .confirmCommitted ? receipt.revision : receipt.baseline
      guard actual == expected?.rawValue else { throw IndexProjectError("Source does not match the selected recovery outcome.") }
      if decision == .confirmCommitted {
        receipt.fixItCommittedContext = try await MarkdownRelationshipNativeCollection.readOnly(root: root).records[draft.path.rawValue]?.context
        receipt.state = .committed; receipt.sourceCommitted = true; receipt.provenanceOperatorConfirmed = true
        try journal.write(receipt)
        _ = try await recover(&draft, lease: lease)
        return draft
      }
      guard !receipt.sourceCommitted else { throw IndexProjectError("A confirmed commit cannot be abandoned.") }
      receipt.state = .abandoned; receipt.completedAt = Date(); try journal.write(receipt)
    } else {
      guard decision == .confirmNotCommitted, actual == draft.baseline.rawValue else {
        throw IndexProjectError("Missing receipt requires confirmNotCommitted and unchanged baseline source.")
      }
    }
    draft.state = .pending; draft.attemptID = nil; draft.resolvedPath = nil
    draft.failureCode = nil; draft.failureMessage = nil
    try store.save(draft); try store.pin(attempt, retain: false)
    return draft
  }

  private func plan(_ draft: MarkdownDraft) async throws -> (result: MarkdownDraftReport, proposed: MarkdownRecord?) {
    let (evaluator, collection, _) = try await verifiedSnapshot(draft)
    guard let context = draft.fixItContext, let source = collection.records[draft.path.rawValue],
      let registry = evaluator.rules else { throw IndexProjectError("Incomplete Fix-It draft context.") }
    let proposed = try MarkdownTypeFixer.apply(context.edits, to: source)
    let revision = MarkdownRecordRevision(rawValue: IndexFingerprint.hash(Data(proposed.content.utf8)))
    guard revision == context.expectedRevisions[draft.path.rawValue] else { throw MarkdownFixItReviewError.staleReview }
    let overlay = try await MarkdownRelationshipFixPlanner(registry: registry).assessTransition(from: collection,
      to: MarkdownRelationshipFixPlanner.replacing([draft.path.rawValue: proposed], in: collection),
    )
    try await validateServerProtection(before: collection.records, after: overlay.records, evaluator: evaluator)
    var result = MarkdownDraftReport(draft)
    result.path = draft.path; result.originalSource = source.content; result.proposedSource = proposed.content; result.proposedRevision = revision
    result.diagnostics = remainingDiagnostics(overlay.after)
    if !overlay.blockers.isEmpty {
      result.failureCode = "fix.validation.failed"; result.failureMessage = overlay.blockers.joined(separator: "\n")
    }
    return (result, proposed)
  }

  private func verifiedSnapshot(_ draft: MarkdownDraft, allowPrepared: Bool = false) async throws -> (IndexProjectEvaluator, MarkdownRelationshipCollection, MarkdownFixItReviewEvidence) {
    guard let context = draft.fixItContext else { throw IndexProjectError("Missing Fix-It context.") }
    let (evaluator, collection, evidence) = try await snapshot()
    var expected = context.evidence.records
    var contexts = context.contexts
    for item in try batch(context.draftIDs) where item.attemptID != nil {
      let receipt = try checkedReceipt(item)
      if allowPrepared && item.id == draft.id && receipt.state == .prepared { continue }
      if receipt.sourceCommitted && (receipt.state == .committed || receipt.state == .completed) {
        expected[item.path.rawValue] = receipt.revision
        guard let committedContext = receipt.fixItCommittedContext else { throw IndexProjectError("Receipt lacks committed source context.") }
        contexts[item.path.rawValue] = committedContext
      } else { throw IndexProjectError("Resolve submitted Fix-It draft \(item.id) before continuing.") }
    }
    guard evidence.collection == context.evidence.collection, evidence.configuration == context.evidence.configuration,
      evidence.resolution == context.evidence.resolution, evidence.scope == (try scopeFingerprint(contexts, complete: true)),
      evidence.records == expected else { throw MarkdownFixItReviewError.staleReview }
    return (evaluator, collection, evidence)
  }

  private func recover(_ draft: inout MarkdownDraft, lease: CollectionWriterLease) async throws -> MarkdownDraftReport {
    var receipt = try checkedReceipt(draft)
    if receipt.state == .committed {
      do {
        let (evaluator, collection, _) = try await verifiedSnapshot(draft)
        guard collection.records[draft.path.rawValue]?.revision == receipt.revision else { throw MarkdownFixItReviewError.staleReview }
        guard let context = draft.fixItContext, let registry = evaluator.rules else { throw IndexProjectError("Missing recovery evidence.") }
        var originals = collection.records
        for item in try batch(context.draftIDs) {
          guard let intent = item.fixItContext, let originalContext = intent.contexts[item.path.rawValue] else {
            throw IndexProjectError("Missing baseline context.")
          }
          originals[item.path.rawValue] = .init(identity: .init(rawValue: item.path.rawValue), content: intent.originalContent,
            context: originalContext, revision: item.baseline,
          )
        }
        let reassessed = try await MarkdownRelationshipFixPlanner(registry: registry).assessTransition(
          from: MarkdownRelationshipFixPlanner.replacing(originals, in: collection), to: collection,
        )
        guard reassessed.blockers.isEmpty else { throw IndexProjectError(reassessed.blockers.joined(separator: "\n")) }
        receipt.diagnostics = remainingDiagnostics(reassessed.after)
        try await publish(evaluator: evaluator, lease: lease)
        try mutationCheckpoint?(.published)
        // Publication and external editors may take time; verify again afterwards.
        _ = try await verifiedSnapshot(draft)
        receipt.state = .completed; receipt.completedAt = Date()
        try journal.write(receipt)
      } catch {
        draft.failureCode = "fix.publication-pending"; draft.failureMessage = error.localizedDescription
        if error is CancellationError { throw CancellationError() }
      }
    }
    draft.state = receipt.state == .completed ? .completed : (receipt.state == .committed ? .publicationPending : .recoveryRequired)
    if draft.state == .completed { draft.failureCode = nil; draft.failureMessage = nil }
    try store.save(draft)
    // Other members may still need this receipt to advance their baseline.
    // Keep it pinned until the completed batch's drafts are explicitly discarded.
    return try receiptReport(draft)
  }

  private func receiptReport(_ draft: MarkdownDraft) throws -> MarkdownDraftReport {
    let receipt = try checkedReceipt(draft)
    var result = MarkdownDraftReport(draft); result.path = draft.path; result.receipt = receipt
    result.diagnostics = receipt.diagnostics
    result.state = receipt.state == .completed ? .completed : (receipt.state == .committed ? .publicationPending : .recoveryRequired)
    if result.state != .completed {
      result.failureCode = draft.failureCode ?? "fix.recovery-required"
      result.failureMessage = draft.failureMessage ?? "Inspect the receipt and use index draft resolve before resuming this batch."
    }
    return result
  }

  private func remainingDiagnostics(_ assessment: MarkdownRuleCollectionAssessment) -> [MarkdownDiagnostic] {
    assessment.rules.flatMap { rule in
      rule.records.filter { $0.membership != .notMatched }.flatMap { $0.assessment.diagnostics + $0.assessment.applicabilityDiagnostics }
        + rule.policies.flatMap { $0.diagnostics.map(\.diagnostic) }
    }
  }

  private func checkedReceipt(_ draft: MarkdownDraft) throws -> MarkdownMutationReceipt {
    guard let attempt = draft.attemptID else { throw IndexProjectError("Missing submitted attempt.") }
    let receipt = try journal.read(journal.url(attempt))
    guard receipt.fixItDraftID == draft.id, receipt.path == draft.path, receipt.resource == draft.resource,
      receipt.baseline == draft.baseline, receipt.revision == draft.fixItContext?.expectedRevisions[draft.path.rawValue],
      receipt.requestHash == (try requestHash(draft)) else { throw IndexProjectError("Fix-It draft and receipt intent do not match.") }
    return receipt
  }

  private func batch(_ ids: [String]) throws -> [MarkdownDraft] {
    let drafts = try ids.map(store.load)
    guard let first = drafts.first?.fixItContext, Set(ids) == Set(first.draftIDs), Set(ids).count == ids.count,
      drafts.allSatisfy({ $0.fixItContext?.batch == first.batch && $0.fixItContext?.draftIDs == first.draftIDs
        && $0.fixItContext?.evidence == first.evidence && $0.fixItContext?.expectedRevisions == first.expectedRevisions
        && $0.fixItContext?.contexts == first.contexts && $0.fixItContext?.configPath == configPath && $0.fixItContext?.rules == rules }) else {
      throw IndexProjectError("Select every draft in this Fix-It batch when resuming; inspect index draft show for draftIDs.")
    }
    return drafts.sorted { $0.path.rawValue < $1.path.rawValue }
  }

  private func snapshot() async throws -> (IndexProjectEvaluator, MarkdownRelationshipCollection, MarkdownFixItReviewEvidence) {
    let evaluator = try IndexProjectEvaluator(root: Path(root.path), configPath: Path(configPath))
    let fingerprint = try configurationFingerprint(evaluator)
    let collection = try await MarkdownRelationshipNativeCollection.readOnly(root: root)
    let current = try IndexProjectEvaluator(root: Path(root.path), configPath: Path(configPath))
    guard try configurationFingerprint(current) == fingerprint else { throw MarkdownFixItReviewError.staleReview }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let contexts = collection.records.mapValues(\.context)
    let evidence = MarkdownFixItReviewEvidence(collection: root.path, configuration: fingerprint,
      records: collection.records.compactMapValues(\.revision),
      resolution: IndexFingerprint.hash(try encoder.encode(collection.resolver.paths.sorted())) + ":\(collection.resolver.namespaceComplete)",
      scope: try scopeFingerprint(contexts, complete: collection.sourcesComplete),
    )
    guard collection.sourcesComplete, collection.resolver.namespaceComplete else {
      throw IndexProjectError("Fix-It review requires complete source evidence: " + collection.limitations.joined(separator: "; "))
    }
    return (evaluator, collection, evidence)
  }

  private func scopeFingerprint(_ contexts: [String: MarkdownRecordContext], complete: Bool) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return IndexFingerprint.combined([String(decoding: try encoder.encode(contexts), as: UTF8.self),
      String(decoding: try encoder.encode(rules?.sorted()), as: UTF8.self), "\(complete)"])
  }

  private func configurationFingerprint(_ evaluator: IndexProjectEvaluator) throws -> String {
    var components = [evaluator.fingerprint]
    for relative in [MarkdownServerProjectLoader.defaultConfigurationPath] {
      let file = root.appendingPathComponent(relative)
      try store.safe(file)
      if FileManager.default.fileExists(atPath: file.path) {
        components.append(IndexFingerprint.hash(try Data(contentsOf: file)))
      } else { components.append("absent:" + relative) }
    }
    return IndexFingerprint.combined(components)
  }

  private func requestHash(_ draft: MarkdownDraft) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return IndexFingerprint.combined([String(decoding: try encoder.encode(draft.payload), as: UTF8.self),
      String(decoding: try encoder.encode(draft.fixItContext), as: UTF8.self)])
  }

  private func assertUnowned(_ paths: [String]) throws {
    let paths = Set(paths)
    for id in try store.ids() {
      let draft = try store.load(id)
      if draft.state != .completed && paths.contains(draft.path.rawValue) { throw IndexProjectError("An active draft owns \(draft.path.rawValue): \(id)") }
    }
    for file in try journal.files() {
      let receipt = try journal.read(file)
      if receipt.state != .completed && receipt.state != .abandoned,
        paths.contains(receipt.path.rawValue) || receipt.sourcePath.map({ paths.contains($0.rawValue) }) == true {
        throw IndexProjectError("An unresolved receipt owns an affected path: \(receipt.id)")
      }
    }
  }

  private func patch(before: MarkdownRecord, after: MarkdownRecord) async throws -> [String: JSONValue] {
    let old = await MarkdownRecordAnalyzer.analyze(before)
    let new = await MarkdownRecordAnalyzer.analyze(after)
    let a = old.userFrontmatter ?? [:], b = new.userFrontmatter ?? [:]
    let set = b.filter { a[$0.key] != $0.value }
    let removed = a.keys.filter { b[$0] == nil }.sorted()
    return ["frontmatter": .object(["set": .object(set), "remove": .array(removed.map(JSONValue.string))])]
  }

  private func publish(evaluator: IndexProjectEvaluator, lease: CollectionWriterLease) async throws {
    if FileManager.default.fileExists(atPath: root.appendingPathComponent(MarkdownServerProjectLoader.defaultConfigurationPath).path) {
      let repository = try IndexedMarkdownRepository(projectRoot: root.path)
      try await repository.refresh(lease: lease)
    } else if FileManager.default.fileExists(atPath: root.appendingPathComponent(".md-utils/index.sqlite").path) {
      let database = try SQLiteIndexDatabase(path: root.appendingPathComponent(".md-utils/index.sqlite").path)
      let report = try await CollectionIndexer(database: database, root: root).updateMany(adding: IndexScope(),
        writerLease: lease, fingerprint: evaluator.fingerprint, verifyHashes: true, evaluate: evaluator.evaluate,
      )
      guard report.sourceErrorCount == 0 else { throw IndexProjectError(report.errors.joined(separator: "; ")) }
    }
  }

  private func validateServerProtection(before: [String: MarkdownRecord], after: [String: MarkdownRecord], evaluator: IndexProjectEvaluator) async throws {
    guard FileManager.default.fileExists(atPath: root.appendingPathComponent(MarkdownServerProjectLoader.defaultConfigurationPath).path) else { return }
    let configuration = try MarkdownServerProjectLoader(projectRoot: Path(root.path)).loadConfiguration()
    let endpoint = try EndpointPlanCompiler(ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]), typeRegistry: evaluator.types).compile(configuration)
    let planning = NativeEditPlanning(plan: endpoint, evaluator: evaluator)
    for path in after.keys.sorted() {
      guard let old = before[path], let new = after[path], old.content != new.content else { continue }
      let a = await MarkdownRecordAnalyzer.analyze(old), b = await MarkdownRecordAnalyzer.analyze(new)
      let oldProjection = try await planning.project(old), newProjection = try await planning.project(new)
      let names = Set((oldProjection?.memberships ?? []).map(\.resourceName) + (newProjection?.memberships ?? []).map(\.resourceName))
      try FileEditPolicy(revision: old.revision, memberships: names, plan: endpoint, contracts: [])
        .validate(before: a.userFrontmatter ?? [:], after: b.userFrontmatter ?? [:])
      let checks = try await planning.constraints(new, projection: newProjection)
      for other in after.keys.sorted() where other != path {
        if let record = after[other] { try await planning.validateOther(record, checks: checks) }
      }
    }
  }
}
