import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownSlugGeneratorTests {
  @Test(arguments: [
    (" Hello,\tWorld! \n", "hello-world"),
    ("Café 世界", "café-世界"),
    ("one__two---three", "one-two-three"),
    ("Book 123", "book-123"),
  ])
  func unicode(source: String, expected: String) throws {
    #expect(try MarkdownSlugGenerator.generate(from: source) == expected)
    #expect(try MarkdownSlugGenerator.generate(from: source) == expected)
    #expect(MarkdownSlugPolicy.unicode.isValid(expected))
  }

  @Test func asciiPolicies() throws {
    #expect(try MarkdownSlugGenerator.generate(from: "Hello_WORLD", policy: .strictASCII) == "hello-world")
    #expect(try MarkdownSlugGenerator.generate(from: "Hello_WORLD", policy: .preserve) == "Hello-WORLD")
    for policy in [MarkdownSlugPolicy.strictASCII, .preserve] {
      #expect(throws: MarkdownSlugGenerator.Failure.unrepresentable) {
        try MarkdownSlugGenerator.generate(from: "Café", policy: policy)
      }
    }
  }

  @Test(arguments: ["", " \t\n", "!—_😀"])
  func empty(source: String) {
    #expect(throws: MarkdownSlugGenerator.Failure.emptyResult) {
      try MarkdownSlugGenerator.generate(from: source)
    }
  }

  @Test func suppliedValues() throws {
    #expect(try MarkdownSlugGenerator.resolve(provided: "old_slug", from: "New Title") == "old_slug")
    #expect(try MarkdownSlugGenerator.resolve(provided: "My-Slug", from: "", policy: .preserve) == "My-Slug")
    #expect(try MarkdownSlugGenerator.resolve(provided: nil, from: "New Title") == "new-title")
    for invalid in ["", "Bad Slug", "two--hyphens"] {
      #expect(throws: MarkdownSlugGenerator.Failure.invalidProvidedValue) {
        try MarkdownSlugGenerator.resolve(provided: invalid, from: "Valid Source")
      }
    }
  }

  @Test func historicalHeadingRules() {
    #expect(HeadingTextExtractor.generateSlug(from: "Hello  World!") == "hello--world")
    #expect(HeadingTextExtractor.generateSlug(from: "Hello_world") == "hello_world")
    #expect(HeadingTextExtractor.generateSlug(from: "!!!") == "section")
    #expect(HeadingTextExtractor.generateSlug(from: "Hello", existingSlugs: ["hello", "hello-1"]) == "hello-2")
  }
}
