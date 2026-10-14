import Foundation
import MarkdownUtilitiesCore
import Testing

struct MarkdownFixItReviewTests {
  @Test func `comma separated and repeated selections deduplicate in review order`() throws {
    #expect(try MarkdownFixItReview.parseSelections(["5,1,4", "4,2"]) == [1, 2, 4, 5])
    #expect(try MarkdownFixItReview.parseSelections([]).isEmpty)
  }

  @Test(arguments: ["", "0", "-1", "+1", "1,", ",1", "1,,4", "1 4", "1, 4", "1-4", "1x", "999999999999999999999", "١"])
  func `malformed selections are rejected`(_ argument: String) {
    #expect(throws: MarkdownFixItReviewError.invalidSelection(argument)) {
      try MarkdownFixItReview.parseSelections([argument])
    }
  }

  @Test func `automatic selection never approves known input required assertions`() throws {
    let review = try makeReview([
      proposal("a", safety: .automatic),
      proposal("b", safety: .requiresInput),
      proposal("c", safety: .automatic, severity: .advisory),
      proposal("d", safety: .advisoryOnly),
    ])
    #expect(try review.select().isEmpty)
    #expect(try review.select(automatic: true) == [1])
    #expect(try review.select(automatic: true, includeRecommendations: true) == [1, 3])
    #expect(try review.select(numbers: [2, 2], automatic: true) == [1, 2])
    #expect(throws: MarkdownFixItReviewError.recommendationRequiresOptIn(3)) {
      try review.select(numbers: [3])
    }
    #expect(throws: MarkdownFixItReviewError.explanatoryOnly(4)) {
      try review.select(numbers: [4], includeRecommendations: true)
    }
  }

  @Test func `automatic label cannot approve a requested input or an empty edit`() throws {
    let review = try makeReview([
      proposal("a", safety: .automatic, edits: [.requestFrontmatterValue(path: ["a"])]),
      proposal("b", safety: .automatic, edits: []),
    ])
    #expect(try review.select(automatic: true).isEmpty)
    // Explicit selection is allowed, but the existing fixer still requires input.
    #expect(try review.select(numbers: [1]) == [1])
    #expect(throws: MarkdownTypeFixerError.missingInput(path: "a")) {
      try MarkdownTypeFixer.apply([review.proposals[0].fixIt], to: MarkdownRecord(content: "# Note\n"))
    }
  }

  @Test(arguments: [-1, 0, 2, Int.max])
  func `unknown numbers never silently disappear`(_ number: Int) throws {
    let review = try makeReview([proposal("a")])
    #expect(throws: MarkdownFixItReviewError.unknownSelection(number)) {
      try review.select(numbers: [number])
    }
  }

  @Test func `alternatives across different files are mutually exclusive`() throws {
    let review = try makeReview([
      proposal("a", file: "Alice.md", group: "return-1"),
      proposal("b", file: "Bob.md", group: "return-1"),
    ])
    #expect(try review.select(numbers: [2]) == [2])
    #expect(throws: MarkdownFixItReviewError.conflictingSelections(1, 2)) {
      try review.select(numbers: [1, 2])
    }
  }

  @Test(arguments: [false, true])
  func `ancestor descendant edits conflict in either order`(_ reverse: Bool) throws {
    let parent = try proposal("parent", edits: [.setFrontmatterValue(path: ["metadata"], value: .object([:]))])
    let child = try proposal("child", edits: [.setFrontmatterValue(path: ["metadata", "spouse"], value: .string("[[Alice]]"))])
    let review = try makeReview(reverse ? [child, parent] : [parent, child])
    #expect(throws: MarkdownFixItReviewError.conflictingSelections(1, 2)) {
      try review.select(numbers: [1, 2])
    }
  }

  @Test func `literal dotted keys do not collide with nested property paths`() throws {
    let review = try makeReview([
      proposal("a", edits: [.setFrontmatterValue(path: ["metadata.spouse"], value: .string("[[Alice]]"))]),
      proposal("b", edits: [.setFrontmatterValue(path: ["metadata", "spouse"], value: .string("[[Alice]]"))]),
      proposal("c", file: "Bob.md", edits: [.setFrontmatterValue(path: ["metadata.spouse"], value: .null)]),
    ])
    #expect(try review.select(numbers: [1, 2, 3]) == [1, 2, 3])
  }

  @Test func `same property edits are not silently merged even when values agree`() throws {
    let review = try makeReview([proposal("a"), proposal("a")])
    #expect(throws: MarkdownFixItReviewError.conflictingSelections(1, 2)) {
      try review.select(numbers: [1, 2])
    }
  }

  @Test func `evidence is required for every destination`() throws {
    let evidence = MarkdownFixItReviewEvidence(collection: "vault", configuration: "config",
      records: [:], resolution: "candidates", scope: "complete",
    )
    let suggestion = try proposal("a")
    #expect(throws: MarkdownFixItReviewError.missingRevision("Alice.md")) {
      try MarkdownFixItReview(evidence: evidence, proposals: [suggestion])
    }
  }

  @Test func `malformed edit paths fail before selection`() throws {
    #expect(throws: MarkdownTypeFixerError.emptyPath) {
      try makeReview([proposal("a", edits: [.setFrontmatterValue(path: [], value: .null)])])
    }
  }

  @Test func `empty supporting revisions and missing fingerprints are rejected`() throws {
    let missingFingerprint = MarkdownFixItReviewEvidence(collection: "vault", configuration: "",
      records: [:], resolution: "paths", scope: "complete",
    )
    #expect(throws: MarkdownFixItReviewError.incompleteEvidence) {
      try MarkdownFixItReview(evidence: missingFingerprint, proposals: [])
    }
    let missingRevision = MarkdownFixItReviewEvidence(collection: "vault", configuration: "config",
      records: ["Bob.md": .init(rawValue: "")], resolution: "paths", scope: "complete",
    )
    #expect(throws: MarkdownFixItReviewError.missingRevision("Bob.md")) {
      try MarkdownFixItReview(evidence: missingRevision, proposals: [])
    }
  }

  @Test func `review bounds reject excessive edits paths and selections`() throws {
    #expect(throws: MarkdownFixItReviewError.limitExceeded) {
      try makeReview([proposal("a", edits: Array(repeating: .ensureFrontmatter, count: 100_001))])
    }
    #expect(throws: MarkdownFixItReviewError.limitExceeded) {
      try makeReview([proposal("a", edits: [.requestFrontmatterValue(path: Array(repeating: "key", count: 129))])])
    }
    #expect(throws: MarkdownFixItReviewError.limitExceeded) {
      try MarkdownFixItReview.parseSelections(Array(repeating: "1", count: 10_001))
    }
  }

  @Test func `canonical review includes supporting evidence and numbered proposals`() throws {
    let review = try makeReview([proposal("a"), proposal("b")])
    let data = try review.canonicalData()
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let evidence = try #require(json["evidence"] as? [String: Any])
    let records = try #require(evidence["records"] as? [String: Any])
    #expect(records["Bob.md"] != nil)
    #expect(try #require(json["proposals"] as? [Any]).count == 2)
    #expect(try review.canonicalData() == data)
  }

  private func makeReview(_ proposals: [MarkdownFixItProposal]) throws -> MarkdownFixItReview {
    try MarkdownFixItReview(evidence: .init(collection: "vault", configuration: "definitions-v1",
      records: ["Alice.md": .init(rawValue: "alice-v1"), "Bob.md": .init(rawValue: "bob-v1")],
      resolution: "complete-candidates-v1", scope: "people-reachable-complete",
    ), proposals: proposals)
  }

  private func proposal(
    _ key: String,
    file: String = "Alice.md",
    safety: MarkdownFixItSafety = .requiresInput,
    severity: MarkdownDiagnosticSeverity = .error,
    group: String? = nil,
    edits: [MarkdownRecordEdit]? = nil,
  ) throws -> MarkdownFixItProposal {
    .init(path: try MarkdownRecordPath(file), fixIt: .init(id: key, title: "Set \(key)", safety: safety,
      edits: edits ?? [.setFrontmatterValue(path: [key], value: .string("[[Bob]]"))],
    ), diagnostic: .init(code: "relationship.policy.return", severity: severity, domain: .frontmatter,
      location: key, message: "Missing return link",
    ), rule: "people", alternativeGroup: group)
  }
}
