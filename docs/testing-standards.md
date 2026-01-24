# Testing Standards

## Test Framework: Swift Testing

**IMPORTANT**: This project uses **native Swift Testing framework**, NOT XCTest.

## Test Naming Convention

Tests MUST use raw identifiers (backticks) for function names:

```swift
@Test
func `Initialize MarkdownDocument with content`() async throws {
  // Test implementation
}
```

**DO NOT** use this pattern:
```swift
// WRONG - Don't do this!
@Test("Initialize MarkdownDocument with content")
func initializeWithContent() async throws {
  // ...
}
```

## Test Structure

- **Suites**: Use `@Suite` with descriptive names
- **Tests**: Use `@Test` with raw identifier function names
- **Assertions**: Use `#expect()` macro (not XCTAssert)
- **Async**: All tests are marked `async throws`
- **Type Checking**: Use `is` keyword for type assertions only
- **Unwrapping Optionals**: Use `try #require()` to unwrap optionals (replaces XCTest's `XCTUnwrap`)

## Unwrapping Optionals

Use `#require` to safely unwrap optionals in tests:

```swift
// CORRECT - Use #require to unwrap optionals
let heading = try #require(root.children[0] as? Heading)
#expect(heading.depth == .h1)

// WRONG - Don't use optional chaining
let heading = root.children[0] as? Heading
#expect(heading?.depth == .h1)
```

## Type Checking

Use `is` when you only need to verify type, not access properties:

```swift
#expect(root.children[1] is Paragraph)
```

## Complete Example

```swift
@Suite("MarkdownDocument Tests")
struct MarkdownDocumentTests {

  @Test
  func `Initialize MarkdownDocument with content`() async throws {
    let content = "# Hello World\n\nThis is a test."
    let doc = try MarkdownDocument(content: content)

    #expect(doc.body == content)
    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `Parse markdown AST`() async throws {
    let content = "# Hello\n\nParagraph text."
    let doc = try MarkdownDocument(content: content)

    let root = try await doc.parseAST()

    #expect(root.children.count == 2)
    let heading = try #require(root.children[0] as? Heading)
    #expect(heading.depth == .h1)
  }
}
```

## CLI Testing

When CLI functionality is implemented:
- Will likely follow FrontRange pattern using Command library
- Test helpers will go in Tests/md-utilsTests/CLI Test Helpers.swift
- Temporary file creation utilities for integration tests

## Test Files

- No `.xctestplan` files - those are Xcode-specific
- Simple directory structure: Tests/[TargetName]Tests/
- Test files use suffix: `*Tests.swift`
- Match the file they're testing with "Tests" suffix
  - Example: `MarkdownDocument.swift` → `MarkdownDocumentTests.swift`
