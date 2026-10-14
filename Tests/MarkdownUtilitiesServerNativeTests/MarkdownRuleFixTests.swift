import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesServer
import PathKit
import Testing
@testable import MarkdownUtilitiesServerNative

struct MarkdownRuleFixTests {
  @Test func `preview is read only and application adds a reviewed reciprocal assertion`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let files = try fixture.contents()
    let current = try await fixture.service.review()
    let number = try fixture.addition(current, path: "Bob.md")
    #expect(try current.review.select(automatic: true).isEmpty)
    let overlay = try await fixture.service.preview(current, numbers: [number])
    #expect(overlay.blockers.isEmpty)
    #expect(overlay.after.outcome == .pass)
    #expect(try fixture.contents() == files)
    #expect((fixture.root + ".md-utils/writer.lock").exists == false)
    let result = try await apply(fixture.service, current.token, [number])
    #expect(result.0)
    #expect(result.1.map(\.state) == [.completed])
    #expect(try (fixture.root + "Bob.md").read(.utf8).contains("[[Alice]]"))
    #expect(try (fixture.root + "Bob.md").read(.utf8).hasSuffix("# Bob\n\nBody stays exact.\n"))
    #expect(try (fixture.root + "Alice.md").read(.utf8) == files["Alice.md"])
    #expect(try await fixture.service.review().suggestions.assessment.outcome == .pass)
    #expect(try await fixture.service.review().review.proposals.isEmpty)
  }

  @Test(arguments: ["source", "target", "candidate", "definition"])
  func `stale source supporting evidence candidates and declarations reject application`(_ change: String) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let review = try await fixture.service.review()
    let number = try fixture.addition(review, path: "Bob.md")
    switch change {
    case "source": try (fixture.root + "Alice.md").write("---\nspouse: '[[Bob]]'\nname: changed\n---\n")
    case "target": try (fixture.root + "Bob.md").write("# Changed\n")
    case "candidate":
      try (fixture.root + "Other/").mkpath()
      try (fixture.root + "Other/Alice.md").write("# Other Alice\n")
    default:
      let path = fixture.root + ".md-utils/rules/people.mdrule.json"
      try path.write(try path.read(.utf8) + "\n")
    }
    let before = try fixture.contents()
    await #expect(throws: MarkdownFixItReviewError.staleReview) {
      try await fixture.service.apply(token: review.token, numbers: [number], report: { _ in })
    }
    let after = try fixture.contents().filter { $0.key != ".md-utils/writer.lock" }
    #expect(after == before)
    #expect((fixture.root + ".md-utils/drafts/").exists == false)
  }

  @Test func `conflicting scalar values are explicit alternatives and new violations block replacement`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try (fixture.root + "Bob.md").write("---\nspouse: '[[Carol]]'\n---\n")
    try (fixture.root + "Carol.md").write("---\nspouse: '[[Bob]]'\n---\n")
    let review = try await fixture.service.review()
    let replacement = try fixture.addition(review, path: "Bob.md")
    let suggestion = review.review.proposals[replacement - 1]
    #expect(suggestion.changes.first?.before == .string("[[Carol]]"))
    let overlay = try await fixture.service.preview(review, numbers: [replacement])
    #expect(overlay.blockers.isEmpty == false)
    let remove = try #require(review.review.proposals.indices.first { index in
      review.review.proposals[index].path.rawValue == "Alice.md"
    }) + 1
    #expect(throws: MarkdownFixItReviewError.conflictingSelections(min(replacement, remove), max(replacement, remove))) {
      try review.review.select(numbers: [replacement, remove])
    }
    #expect(try await fixture.service.preview(review, numbers: [remove]).blockers.isEmpty)
  }

  @Test(arguments: [false, true])
  func `missing or ambiguous forward targets never produce assertion repairs`(_ missing: Bool) async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    if missing { try (fixture.root + "Bob.md").delete() }
    else {
      try (fixture.root + "Other/").mkpath()
      try (fixture.root + "Other/Bob.md").write("# Bob\n")
    }
    let review = try await fixture.service.review()
    #expect(review.review.proposals.isEmpty)
    #expect(review.suggestions.assessment.outcome != .pass)
  }

  @Test func `publication failure retains receipts and resumes without rewriting source`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let review = try await fixture.service.review()
    var service = fixture.service
    service.mutationCheckpoint = { boundary in if boundary == .published { throw Injected.failure } }
    let applied = try await apply(service, review.token, [fixture.addition(review, path: "Bob.md")])
    #expect(applied.0 == false)
    let report = try #require(applied.1.first)
    #expect(report.state == .publicationPending)
    #expect(report.receipt?.sourceCommitted == true)
    let bytes = try (fixture.root + "Bob.md").read(.utf8)
    let modified = try FileManager.default.attributesOfItem(atPath: (fixture.root + "Bob.md").string)[.modificationDate] as? Date
    let drafts = MarkdownDraftService(projectRoot: fixture.root.string)
    let dry = try await drafts.preview(report.draftID)
    #expect(dry.state == .publicationPending)
    #expect(try await drafts.apply(ids: [report.draftID], report: { _ in }))
    #expect(try drafts.draft(report.draftID).state == .completed)
    #expect(try (fixture.root + "Bob.md").read(.utf8) == bytes)
    #expect(try FileManager.default.attributesOfItem(atPath: (fixture.root + "Bob.md").string)[.modificationDate] as? Date == modified)
  }

  @Test func `indeterminate writes require explicit recovery and retain unattempted files`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try (fixture.root + "Carol.md").write("---\nspouse: '[[Dave]]'\n---\n")
    try (fixture.root + "Dave.md").write("# Dave\n")
    let review = try await fixture.service.review()
    var service = fixture.service
    let dave = (fixture.root + "Dave.md").string
    service.mutationCheckpoint = { boundary in
      if boundary == .persisted, (try Path(dave).read(.utf8)).contains("[[Carol]]") { throw Injected.failure }
    }
    let applied = try await apply(service, review.token, [fixture.addition(review, path: "Bob.md"), fixture.addition(review, path: "Dave.md")])
    #expect(applied.0 == false)
    #expect(applied.1.map(\.state) == [.completed, .recoveryRequired])
    let uncertain = try #require(applied.1.last)
    let drafts = MarkdownDraftService(projectRoot: fixture.root.string)
    let completed = try #require(applied.1.first)
    let attempt = try #require(completed.receipt?.id)
    let pin = fixture.root + ".md-utils/mutations/pins/\(attempt)"
    #expect(pin.exists)
    await #expect(throws: Error.self) { try await drafts.discard(completed.draftID) }
    #expect(try await drafts.apply(ids: applied.1.map(\.draftID), report: { _ in }) == false)
    #expect(try await drafts.resolve(uncertain.draftID, decision: .confirmCommitted).state == .completed)
    #expect(try await drafts.apply(ids: applied.1.map(\.draftID), report: { _ in }))
    #expect(try await fixture.service.review().suggestions.assessment.outcome == .pass)
    #expect(pin.exists)
    try await drafts.discard(completed.draftID)
    #expect(pin.exists == false)
  }

  @Test func `unsubmitted remainder can be abandoned without deleting active recovery evidence`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try (fixture.root + "Carol.md").write("---\nspouse: '[[Dave]]'\n---\n")
    try (fixture.root + "Dave.md").write("# Dave\n")
    let review = try await fixture.service.review()
    var service = fixture.service
    let bob = (fixture.root + "Bob.md").string
    service.mutationCheckpoint = { boundary in
      if boundary == .prepared, (try Path(bob).read(.utf8)).contains("[[Alice]]") { throw Injected.failure }
    }
    let applied = try await apply(service, review.token, [fixture.addition(review, path: "Bob.md"), fixture.addition(review, path: "Dave.md")])
    #expect(applied.1.map(\.state) == [.completed, .recoveryRequired])
    let completed = try #require(applied.1.first)
    let unfinished = try #require(applied.1.last)
    let drafts = MarkdownDraftService(projectRoot: fixture.root.string)
    await #expect(throws: Error.self) { try await drafts.discard(completed.draftID) }
    #expect(try await drafts.resolve(unfinished.draftID, decision: .confirmNotCommitted).state == .pending)
    await #expect(throws: Error.self) { try await drafts.discard(completed.draftID) }
    try await drafts.discard(unfinished.draftID)
    try await drafts.discard(completed.draftID)
    let current = try await fixture.service.review()
    #expect(try await apply(fixture.service, current.token, [fixture.addition(current, path: "Dave.md")]).0)
  }

  @Test func `supporting changes after durable intent are caught before a source write`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let review = try await fixture.service.review()
    let original = try (fixture.root + "Bob.md").read(.utf8)
    var service = fixture.service
    let source = (fixture.root + "Alice.md").string
    service.mutationCheckpoint = { boundary in
      if boundary == .prepared { try Path(source).write("# Alice no longer declares spouse\n") }
    }
    let applied = try await apply(service, review.token, [fixture.addition(review, path: "Bob.md")])
    #expect(applied.0 == false)
    #expect(try (fixture.root + "Bob.md").read(.utf8) == original)
    #expect(applied.1.first?.state == .recoveryRequired)
  }

  @Test func `indexed previews preserve bytes and apply refreshes registered evidence`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let root = URL(fileURLWithPath: fixture.root.string).resolvingSymlinksInPath()
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: root.path)
    let evaluator = try IndexProjectEvaluator(root: fixture.root, configPath: fixture.root + ".md-utils/md-utils.json")
    _ = try await CollectionIndexer(database: database, root: root).updateMany(adding: IndexScope(),
      fingerprint: evaluator.fingerprint, evaluate: evaluator.evaluate,
    )
    func bytes() throws -> [String: Data] {
      try Dictionary(uniqueKeysWithValues: fixture.root.recursiveChildren().filter(\.isFile).map { path in
        (path.string, try Data(contentsOf: URL(fileURLWithPath: path.string)))
      })
    }
    let original = try bytes()
    let generation = try database.freshness().generation
    let current = try await fixture.service.review()
    let number = try fixture.addition(current, path: "Bob.md")
    _ = try await fixture.service.preview(current, numbers: [number])
    #expect(try bytes() == original)
    let applied = try await apply(fixture.service, current.token, [number])
    #expect(applied.0, "\(applied.1)")
    #expect(try database.freshness().generation > generation)
  }

  @Test func `failure before first persistence leaves later drafts explicitly unattempted`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try (fixture.root + "Carol.md").write("---\nspouse: '[[Dave]]'\n---\n")
    try (fixture.root + "Dave.md").write("# Dave\n")
    let review = try await fixture.service.review()
    var service = fixture.service
    service.mutationCheckpoint = { boundary in if boundary == .prepared { throw Injected.failure } }
    let applied = try await apply(service, review.token, [fixture.addition(review, path: "Bob.md"), fixture.addition(review, path: "Dave.md")])
    #expect(applied.0 == false)
    #expect(applied.1.last?.failureCode == "draft.unattempted")
    #expect(try (fixture.root + "Dave.md").read(.utf8) == "# Dave\n")
    let first = try #require(applied.1.first)
    let drafts = MarkdownDraftService(projectRoot: fixture.root.string)
    #expect(try await drafts.resolve(first.draftID, decision: .confirmNotCommitted).state == .pending)
    #expect(try await drafts.apply(ids: applied.1.map(\.draftID), report: { _ in }))
  }

  private enum Injected: Error { case failure }

  private func apply(_ service: MarkdownRuleFixService, _ token: String, _ numbers: [Int]) async throws -> (Bool, [MarkdownDraftReport]) {
    let stream = AsyncStream<MarkdownDraftReport>.makeStream()
    let success = try await service.apply(token: token, numbers: numbers, report: { stream.continuation.yield($0) })
    stream.continuation.finish()
    var results: [MarkdownDraftReport] = []
    for await result in stream.stream { results.append(result) }
    return (success, results)
  }

  private struct Fixture {
    let root: Path
    var service: MarkdownRuleFixService {
      .init(projectRoot: root.string, configPath: (root + ".md-utils/md-utils.json").string, rules: ["people"])
    }
    init() throws {
      root = Path(#filePath).parent().parent().parent() + "tmp/rule-fix-\(UUID().uuidString)/"
      try (root + ".md-utils/types/").mkpath()
      try (root + ".md-utils/rules/").mkpath()
      try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
      try (root + ".md-utils/types/person.mdtype.json").write("""
        {"md-utils-type-schema":"2","name":"Person","version":"1","requires":["document-relationships"],
        "frontmatter":{"schemas":[]},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
        "relationships":{"spouse":{"select":["spouse"],"target":{"type":"person.mdtype.json"},"cardinality":{"max":1}}}}
        """)
      try (root + ".md-utils/rules/people.mdrule.json").write("""
        {"md-utils-rule-schema":"1","name":"people","match":{"paths":["*.md"]},"types":"person.mdtype.json",
        "relationshipPolicies":[{"id":"spouse-return","kind":"reciprocity","relation":{"type":"person.mdtype.json","name":"spouse"},"scope":"reachable"}]}
        """)
      try (root + "Alice.md").write("---\nspouse: '[[Bob]]'\n---\n# Alice\n")
      try (root + "Bob.md").write("# Bob\n\nBody stays exact.\n")
    }
    func remove() { try? root.delete() }
    func addition(_ review: MarkdownRuleFixReview, path: String) throws -> Int {
      try #require(review.review.proposals.indices.first { index in
        let proposal = review.review.proposals[index]
        return proposal.path.rawValue == path && proposal.changes.contains { $0.after != nil }
      }) + 1
    }
    func contents() throws -> [String: String] {
      var values: [String: String] = [:]
      for path in try root.recursiveChildren() where path.isFile {
        let base = URL(fileURLWithPath: root.string).standardizedFileURL.path
        let file = URL(fileURLWithPath: path.string).standardizedFileURL.path
        values[String(file.dropFirst(base.count + 1))] = try path.read(.utf8)
      }
      return values
    }
  }
}
