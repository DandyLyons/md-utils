import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer
@testable import MarkdownUtilitiesServerNative
import PathKit
import Synchronization
import Testing

@Suite("Revision-checked pending drafts")
struct MarkdownDraftTests {
  private let persistentUUID = "11111111-1111-4111-8111-111111111111"

  private func fixture() throws -> Path {
    let root = Path("tmp/drafts/\(UUID().uuidString)/").absolute()
    try (root + ".md-utils/server/").mkpath()
    try (root + "books/").mkpath()
    try (root + ".md-utils/md-utils.json").write("""
      {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
      {"name":"books","match":{"paths":["books/**"]},"checks":[{"type":"requiredHeading","heading":"Book"}]}]}
      """)
    try (root + ".md-utils/server/server.yaml").write("""
      serverConfigVersion: "3"
      persistentIdentity: {path: [uuid]}
      resources:
        - name: books
          route: /books
          operations: [list, get]
          selection: {mode: rule, rule: books}
          identityPolicy: {source: frontmatter, path: [slug], format: string}
          lookups: [{name: uuid, source: persistentIdentity}]
          writable:
            codec: {frontmatterFields: [title, subtitle], bodyWritable: true}
          mutations:
            operations: [patch, replace, move]
            creation: {directory: books/}
        - name: library
          route: /library
          operations: [list, get]
          selection: {mode: rule, rule: books}
          identityPolicy: {source: frontmatter, path: [slug], format: string}
      """)
    try (root + "books/one.md").write(source())
    return root
  }

  private func source(uuid: String? = nil, slug: String = "one") -> String {
    "---\n# keep comment for body-only edits\nuuid: \(uuid ?? persistentUUID)\nslug: \(slug)\ntitle: Old\nsubtitle: retained\n---\n# Book\n\nOriginal body.\r\n"
  }

  private func request(_ json: String = #"{"frontmatter":{"set":{"title":"New"}}}"#,
    operation: MarkdownMutationOperation = .patch,
  ) throws -> MarkdownMutationRequest { try .init(operation: operation, data: Data(json.utf8)) }

  private func stage(_ root: Path, json: String = #"{"frontmatter":{"set":{"title":"New"}}}"#,
    path: String = "books/one.md", operation: MarkdownMutationOperation = .patch,
  ) async throws -> MarkdownDraft {
    let content = try (root + path).read(.utf8)
    return try await MarkdownDraftService(projectRoot: root.string).stage(path: MarkdownRecordPath(path), resource: "books",
      revision: .init(rawValue: IndexFingerprint.hash(Data(content.utf8))), request: request(json, operation: operation))
  }

  private func snapshot(_ root: Path) throws -> [String: Data] {
    guard let entries = FileManager.default.enumerator(atPath: root.string) else { throw CocoaError(.fileReadUnknown) }
    var result: [String: Data] = [:]
    while let path = entries.nextObject() as? String {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: (root + path).string, isDirectory: &isDirectory), !isDirectory.boolValue {
        result[path] = try Data(contentsOf: URL(fileURLWithPath: (root + path).string))
      }
    }
    return result
  }

  @Test(arguments: [false, true])
  func dryRunAndApplyShareSourceAndPublishAllResources(fts: Bool) async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    if fts {
      let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
      try db.prepareCollection(root: root.string); try db.setBodyMode(.fts)
    }
    try await repository.refresh()
    let draft = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    let before = try snapshot(root)
    let preview = try await service.preview(draft.id)
    #expect(preview.succeeded)
    #expect(preview.originalSource == source())
    #expect(preview.proposedSource?.hasSuffix("# Book\n\nOriginal body.\r\n") == true)
    #expect(try await service.apply(dryRun: true, report: { _ in }))
    #expect(try snapshot(root) == before)
    #expect(try service.draft(draft.id).state == .pending)
    #expect(try await service.apply(report: { _ in }))
    #expect(try (root + "books/one.md").read(.utf8) == preview.proposedSource)
    let completed = try service.draft(draft.id)
    #expect(completed.state == .completed)
    let attempt = try #require(completed.attemptID)
    let receipt = try await repository.operation(resource: "books", id: attempt)
    #expect(receipt.revision == preview.proposedRevision)
    #expect(Set(receipt.record?.memberships.map(\.resourceName) ?? []) == ["books", "library"])
    #expect(try await service.apply(report: { _ in }))
    #expect(try (root + "books/one.md").read(.utf8) == preview.proposedSource)
    let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    #expect(try db.storagePolicy().bodyMode == (fts ? .fts : .metadataOnly))
  }

  @Test func dryRunDoesNotInitializeMissingIndexOrReceiptJournal() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    let before = try snapshot(root)
    #expect(try await service.preview(draft.id).succeeded)
    #expect(try await service.apply(dryRun: true, report: { _ in }))
    #expect(try snapshot(root) == before)
    #expect(!(root + ".md-utils/index.sqlite").exists)
    #expect(!(root + ".md-utils/mutations/").exists)
  }

  @Test func externalEditsAfterSuccessfulPreviewConflictAndRetainBaseline() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    #expect(try await service.preview(draft.id).succeeded)
    let changed = source() + "External edit.\n"
    try (root + "books/one.md").write(changed)
    #expect(try await service.preview(draft.id).failureCode == "revision.stale")
    #expect(!(try await service.apply(report: { _ in })))
    #expect(try (root + "books/one.md").read(.utf8) == changed)
    let retained = try service.draft(draft.id)
    #expect(retained.baseline == draft.baseline)
    #expect(retained.state == .conflict)
    #expect(retained.failureCode == "revision.stale")
  }

  @Test(arguments: [false, true])
  func managedMoveFollowsUUIDButExternalMoveNeedsReview(managed: Bool) async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let draft = try await stage(root)
    if managed {
      let receipt = try await repository.mutate(resource: "books", identity: nil, path: draft.path,
        request: request(#"{"filename":"Moved.md"}"#, operation: .move), revision: draft.baseline, idempotencyKey: "move")
      #expect(receipt.state == .completed)
    } else {
      try FileManager.default.moveItem(atPath: (root + "books/one.md").string, toPath: (root + "books/Moved.md").string)
    }
    let service = MarkdownDraftService(projectRoot: root.string)
    let preview = try await service.preview(draft.id)
    if managed {
      #expect(preview.path?.rawValue == "books/Moved.md")
      #expect(preview.succeeded)
      #expect(try await service.apply(report: { _ in }))
      #expect(try (root + "books/Moved.md").read(.utf8) == preview.proposedSource)
    } else {
      #expect(preview.failureCode == "draft.relocation-unconfirmed")
      #expect(!(try await service.apply(report: { _ in })))
      #expect(try (root + "books/Moved.md").read(.utf8) == source())
    }
    #expect(!(root + "books/one.md").exists)
  }

  @Test func copiesReplacementsAndMissingTargetsNeverSelectArbitrarily() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    try (root + "books/copy.md").write(source(slug: "copy"))
    #expect(try await service.preview(draft.id).failureCode == "identity.ambiguous")
    try (root + "books/copy.md").delete()
    try (root + "books/one.md").write(source(uuid: UUID().uuidString))
    #expect(try await service.preview(draft.id).failureCode == "draft.target-replaced")
    try (root + "books/one.md").delete()
    #expect(try await service.preview(draft.id).failureCode == "draft.target-missing")
    #expect(try service.draft(draft.id).baseline == draft.baseline)
  }

  @Test func codecsPreserveBodyAndFrontmatterAndRejectProtectedEdits() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let service = MarkdownDraftService(projectRoot: root.string)
    let bodyDraft = try await stage(root, json: ##"{"body":"# Book\n\nNew body.\n"}"##)
    let preview = try await service.preview(bodyDraft.id)
    #expect(preview.proposedSource?.hasPrefix("---\n# keep comment for body-only edits\n") == true)
    #expect(try await service.apply(report: { _ in }))
    try await service.discard(bodyDraft.id)
    let protected = try await stage(root, json: #"{"frontmatter":{"set":{"uuid":"changed"}}}"#)
    #expect(!(try await service.preview(protected.id).succeeded))
    try await service.discard(protected.id)
    let invalid = try await stage(root, json: #"{"body":"Removed required heading"}"#)
    let invalidPreview = try await service.preview(invalid.id)
    #expect(invalidPreview.failureCode == "record.invalid")
    #expect(!invalidPreview.diagnostics.isEmpty)
    #expect(invalidPreview.proposedSource?.hasSuffix("Removed required heading") == true)
  }

  @Test func duplicateDraftsAndStaleStagingAreRejected() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    await #expect(throws: MarkdownMutationError.self) { _ = try await stage(root) }
    await #expect(throws: MarkdownMutationError.self) {
      _ = try await MarkdownDraftService(projectRoot: root.string).stage(path: draft.path, resource: "books",
        revision: .init(rawValue: "stale"), request: request())
    }
  }

  @Test func actualDraftSchemaSurvivesRefreshModesAndTextRebuild() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    try (root + "books/one.md").write(source() + "External edit")
    #expect(!(try await service.apply(report: { _ in })))
    let url = URL(fileURLWithPath: (root + ".md-utils/drafts/\(draft.id).json").string)
    let bytes = try Data(contentsOf: url)
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    #expect(try Data(contentsOf: url) == bytes)
    let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try db.setBodyMode(.fts)
    try await repository.refresh()
    #expect(try Data(contentsOf: url) == bytes)
    try db.setBodyMode(.metadataOnly)
    try await repository.refresh()
    try await db.rebuildAsText(root: root.string, scratchDirectory: URL(fileURLWithPath: (root + "tmp/").string)) { fresh, lease in
      _ = try await CollectionIndexer(database: fresh, root: URL(fileURLWithPath: root.string)).update(
        writerLease: lease, fingerprint: "test", verifyHashes: true,
        evaluate: { _, _, content, _ in .init(metadata: "{}", body: content, assessment: .init(selected: true, status: "selected")) })
    }
    #expect(try Data(contentsOf: url) == bytes)
    let retained = try service.draft(draft.id)
    #expect(retained.baseline == draft.baseline)
    #expect(retained.uuid == draft.uuid)
    #expect(retained.failureCode == "revision.stale")
    #expect(try await service.preview(draft.id).failureCode == "revision.stale")
  }

  @Test(arguments: [MutationBoundary.prepared, .persisted, .committed, .published])
  func interruptionsRecoverWithoutApplyingTwice(boundary: MutationBoundary) async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    var service = MarkdownDraftService(projectRoot: root.string)
    service.mutationCheckpoint = { if $0 == boundary { throw CancellationError() } }
    #expect(!(try await service.apply(report: { _ in })))
    let interrupted = try service.draft(draft.id)
    #expect(interrupted.attemptID != nil)
    let restart = MarkdownDraftService(projectRoot: root.string)
    if boundary == .prepared || boundary == .persisted {
      #expect(!(try await restart.apply(report: { _ in })))
      await #expect(throws: MarkdownMutationError.self) { try await restart.discard(draft.id) }
      let resolution = boundary == .prepared ? MarkdownRecoveryDecision.confirmNotCommitted : .confirmCommitted
      _ = try await restart.resolve(draft.id, decision: resolution)
    }
    #expect(try await restart.apply(report: { _ in }))
    let completed = try restart.draft(draft.id)
    #expect(completed.state == .completed)
    let content = try (root + "books/one.md").read(.utf8)
    #expect(content.contains("title: New"))
    #expect(try await restart.apply(report: { _ in }))
    #expect(try (root + "books/one.md").read(.utf8) == content)
  }

  @Test func missingReceiptRequiresExplicitResolutionAndDoesNotBlindlyRetry() async throws {
    let root = try fixture(); defer { try? root.delete() }
    var draft = try await stage(root)
    let store = MarkdownDraftStore(root: URL(fileURLWithPath: root.string))
    draft.attemptID = UUID().uuidString.lowercased(); draft.resolvedPath = draft.path; draft.state = .submitted
    try store.save(draft)
    let service = MarkdownDraftService(projectRoot: root.string)
    #expect(try await service.preview(draft.id).failureCode == "draft.receipt-missing")
    #expect(!(try await service.apply(report: { _ in })))
    #expect(try (root + "books/one.md").read(.utf8) == source())
    let reset = try await service.resolve(draft.id, decision: .confirmNotCommitted)
    #expect(reset.attemptID == nil)
    #expect(reset.baseline == draft.baseline)
    #expect(try await service.apply(report: { _ in }))
  }

  @Test func configurationChangesAreExplicitConflicts() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    let config = root + ".md-utils/server/server.yaml"
    try config.write(try config.read(.utf8).replacingOccurrences(of: "[title, subtitle]", with: "[title]"))
    #expect(try await MarkdownDraftService(projectRoot: root.string).preview(draft.id).failureCode == "draft.configuration-changed")
  }

  @available(macOS 15.0, *)
  @Test func interruptedBatchReportsCompletedUnresolvedAndUnattemptedWork() async throws {
    let root = try fixture(); defer { try? root.delete() }
    try (root + "books/two.md").write(source(uuid: UUID().uuidString, slug: "two"))
    try (root + "books/three.md").write(source(uuid: UUID().uuidString, slug: "three"))
    _ = try await stage(root)
    _ = try await stage(root, path: "books/two.md")
    _ = try await stage(root, path: "books/three.md")
    var service = MarkdownDraftService(projectRoot: root.string)
    let ids = try service.draftIDs()
    let count = Mutex(0)
    service.mutationCheckpoint = { boundary in
      if boundary == .prepared {
        let stop = count.withLock { value in value += 1; return value == 2 }
        if stop { throw CancellationError() }
      }
    }
    let reports = Mutex<[MarkdownDraftReport]>([])
    #expect(!(try await service.apply(report: { result in reports.withLock { $0.append(result) } })))
    #expect(try service.draft(ids[0]).state == .completed)
    #expect(try service.draft(ids[1]).state == .recoveryRequired)
    #expect(try service.draft(ids[2]).state == .pending)
    let output = reports.withLock { $0 }
    #expect(output.count == 3)
    #expect(output.last?.failureCode == "draft.unattempted")
    let third = try service.draft(ids[2])
    #expect(IndexFingerprint.hash(Data(try (root + third.path.rawValue).read(.utf8).utf8)) == third.baseline.rawValue)
  }

  @Test func finalSourceCheckRejectsChangesAfterPlanning() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    var service = MarkdownDraftService(projectRoot: root.string)
    let changed = source() + "Changed immediately before persistence."
    let sourcePath = (root + "books/one.md").string
    service.mutationCheckpoint = { boundary in
      if boundary == .prepared { try Path(sourcePath).write(changed) }
    }
    #expect(!(try await service.apply(report: { _ in })))
    let retained = try service.draft(draft.id)
    #expect(retained.failureCode == "revision.stale")
    #expect(retained.attemptID == nil)
    #expect(try (root + "books/one.md").read(.utf8) == changed)
  }

  @Test func managedMoveEvidenceIsLostAfterRebuildWithoutLosingDraftIdentity() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let draft = try await stage(root)
    _ = try await repository.mutate(resource: "books", identity: nil, path: draft.path,
      request: request(#"{"filename":"Moved.md"}"#, operation: .move), revision: draft.baseline, idempotencyKey: "move")
    let service = MarkdownDraftService(projectRoot: root.string)
    #expect(try await service.preview(draft.id).succeeded)
    let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try await db.rebuild(root: root.string) { fresh, lease in
      _ = try await CollectionIndexer(database: fresh, root: URL(fileURLWithPath: root.string)).update(
        writerLease: lease, fingerprint: "test", verifyHashes: true,
        evaluate: { _, _, content, _ in .init(metadata: "{}", body: content, assessment: .init(selected: true, status: "selected")) })
    }
    #expect(try service.draft(draft.id).uuid == draft.uuid)
    #expect(try await service.preview(draft.id).failureCode == "draft.relocation-unconfirmed")
  }

  @Test func replacementNullAndRemovalUseTheSharedCodecContract() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let service = MarkdownDraftService(projectRoot: root.string)
    let draft = try await stage(root, json: ##"{"frontmatter":{"title":"Replacement"},"body":"# Book\nNew body\n"}"##,
      operation: .replace)
    #expect(try await service.apply(report: { _ in }))
    let content = try (root + "books/one.md").read(.utf8)
    #expect(!content.contains("subtitle:"))
    #expect(content.contains("uuid: \(persistentUUID)"))
    #expect(content.hasSuffix("# Book\nNew body\n"))
    try await service.discard(draft.id)
    let null = try await stage(root, json: #"{"frontmatter":{"set":{"subtitle":null}}}"#)
    #expect(try await service.apply(report: { _ in }))
    #expect(try (root + "books/one.md").read(.utf8).contains("subtitle: null"))
    try await service.discard(null.id)
    _ = try await stage(root, json: #"{"frontmatter":{"remove":["subtitle"]}}"#)
    #expect(try await service.apply(report: { _ in }))
    #expect(!(try (root + "books/one.md").read(.utf8).contains("subtitle:")))
  }

  @Test func completedReceiptPinSurvivesRetentionUntilDraftAcknowledgement() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let staged = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    #expect(try await service.apply(report: { _ in }))
    var interrupted = try service.draft(staged.id)
    let attempt = try #require(interrupted.attemptID)
    let store = MarkdownDraftStore(root: URL(fileURLWithPath: root.string))
    interrupted.state = .submitted
    try store.pin(attempt, retain: true); try store.save(interrupted)
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    var receipt = try await repository.operation(resource: "books", id: attempt)
    receipt.completedAt = Date(timeIntervalSince1970: 0)
    let receiptPath = root + ".md-utils/mutations/\(attempt).json"
    try JSONEncoder().encode(receipt).write(to: URL(fileURLWithPath: receiptPath.string), options: .atomic)
    let laterContent = try (root + "books/one.md").read(.utf8) + "Later independent edit."
    try (root + "books/one.md").write(laterContent)
    let secondSource = source(uuid: UUID().uuidString, slug: "two")
    try (root + "books/two.md").write(secondSource)
    _ = try await repository.mutate(resource: "books", identity: nil, path: MarkdownRecordPath("books/two.md"),
      request: request(), revision: .init(rawValue: IndexFingerprint.hash(Data(secondSource.utf8))), idempotencyKey: nil)
    #expect(receiptPath.exists)
    #expect(try await service.apply(report: { _ in }))
    #expect(try service.draft(staged.id).state == .completed)
    #expect(try (root + "books/one.md").read(.utf8) == laterContent)
    #expect(!(root + ".md-utils/mutations/pins/\(attempt)").exists)
  }

  @Test func throwingReportDoesNotReclassifyACompletedCommit() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let draft = try await stage(root)
    let service = MarkdownDraftService(projectRoot: root.string)
    await #expect(throws: CocoaError.self) {
      _ = try await service.apply(report: { _ in throw CocoaError(.fileWriteUnknown) })
    }
    #expect(try service.draft(draft.id).state == .completed)
    #expect(try (root + "books/one.md").read(.utf8).contains("title: New"))
  }
}
