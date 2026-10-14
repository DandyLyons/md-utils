import MarkdownUtilities
import MarkdownUtilitiesCore
import Testing

struct MarkdownFixItReviewTokenTests {
  @Test func `token is stable across dictionary insertion order`() throws {
    let first = try review(records: ["Alice.md": "a", "Bob.md": "b"])
    var records: [String: String] = [:]
    records["Bob.md"] = "b"
    records["Alice.md"] = "a"
    let second = try review(records: records)
    let token = try MarkdownFixItReviewToken.token(for: first)
    #expect(token.hasPrefix("fix-review-v1-"))
    #expect(token.count == "fix-review-v1-".count + 64)
    #expect(try MarkdownFixItReviewToken.token(for: second) == token)
    try MarkdownFixItReviewToken.verify(token, against: second)
  }

  @Test(arguments: ["source", "support", "candidate", "definition", "scope", "collection", "proposal", "order"])
  func `changed evidence or proposals invalidate old numbers`(_ change: String) throws {
    let original = try review()
    let token = try MarkdownFixItReviewToken.token(for: original)
    var records = ["Alice.md": "a", "Bob.md": "b"]
    if change == "source" { records["Alice.md"] = "a2" }
    if change == "support" { records["Bob.md"] = "b2" }
    let current = try review(records: records,
      resolution: change == "candidate" ? "new-duplicate-path" : "paths-v1",
      configuration: change == "definition" ? "config-v2" : "config-v1",
      scope: change == "scope" ? "incomplete" : "complete",
      collection: change == "collection" ? "another-vault" : "vault",
      replacement: change == "proposal" ? "[[Carol]]" : "[[Bob]]",
      reverse: change == "order",
    )
    #expect(throws: MarkdownFixItReviewError.staleReview) {
      try MarkdownFixItReviewToken.verify(token, against: current)
    }
  }

  @Test func `empty and shortened tokens do not verify`() throws {
    let current = try review()
    for token in ["", "abc123", String(try MarkdownFixItReviewToken.token(for: current).prefix(20))] {
      #expect(throws: MarkdownFixItReviewError.staleReview) {
        try MarkdownFixItReviewToken.verify(token, against: current)
      }
    }
  }

  @Test func `stale review is rejected before numbered selections are interpreted`() throws {
    let original = try review()
    let token = try MarkdownFixItReviewToken.token(for: original)
    #expect(try MarkdownFixItReviewToken.select(token, from: original, numbers: [2, 1, 2]) == [1, 2])
    let changed = try review(reverse: true)
    #expect(throws: MarkdownFixItReviewError.staleReview) {
      try MarkdownFixItReviewToken.select(token, from: changed, numbers: [999])
    }
  }

  private func review(
    records: [String: String] = ["Alice.md": "a", "Bob.md": "b"],
    resolution: String = "paths-v1",
    configuration: String = "config-v1",
    scope: String = "complete",
    collection: String = "vault",
    replacement: String = "[[Bob]]",
    reverse: Bool = false,
  ) throws -> MarkdownFixItReview {
    let proposals = try ["spouse", "parent"].map { key in
      MarkdownFixItProposal(path: try MarkdownRecordPath("Alice.md"),
        fixIt: .init(id: key, title: "Set \(key)", safety: .requiresInput,
          edits: [.setFrontmatterValue(path: [key], value: .string(replacement))],
        ), diagnostic: .init(code: "relationship.policy.return", severity: .error, domain: .frontmatter,
          location: key, message: "Missing return link",
        ), rule: "people")
    }
    return try .init(evidence: .init(collection: collection, configuration: configuration,
      records: records.mapValues { .init(rawValue: $0) }, resolution: resolution, scope: scope,
    ), proposals: reverse ? Array(proposals.reversed()) : proposals)
  }
}
