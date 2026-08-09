# Testing Standards

## Test Framework: Swift Testing

**IMPORTANT**: This project uses **native Swift Testing framework**, NOT XCTest.

## Test Naming Convention

Tests MUST use raw identifiers (backticks) for function names:

```swift
@Test
func `initializes MarkdownDocument with content`() throws {
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
- **Effects**: Add `async` and `throws` only when the test body needs them
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
  func `initializes MarkdownDocument with content`() throws {
    let content = "# Hello World\n\nThis is a test."
    let doc = try MarkdownDocument(content: content)

    #expect(doc.body == content)
    #expect(doc.frontMatter.isEmpty)
  }

  @Test
  func `parses the Markdown AST`() async throws {
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

CLI commands are tested in `Tests/md-utilsTests/Commands/`:

- Each command group has its own test file (e.g., `BodyTests.swift`, `LinesTests.swift`)
- FrontMatter subcommands have individual test files under `Commands/FrontMatterCommands/`
- Tests use temporary files and directories for integration testing
  - Some tests have a `Fixtures/` directory
- Follow the same Swift Testing conventions (backtick naming, `#expect`, `try #require`)

### Choose the Smallest Appropriate CLI Boundary

Use these test boundaries in order of preference:

1. Parse commands with `parseAsRoot`, cast with `try #require`, and call `run()` directly. This is the default for argument parsing and command behavior.
2. Test extracted library or support types directly when command parsing is irrelevant.
3. Use `CLIProcessTestHelper.run` only for behavior that belongs to the executable process boundary:
   - termination status;
   - interactive standard input;
   - standard output and standard error routing;
   - top-level ArgumentParser error rendering.

Do not create command-specific `Process` wrappers. Shared black-box CLI tests use
`Tests/md-utilsTests/TestHelpers/CLIProcessTestHelper.swift`, which supplies a
deterministic terminal environment and captures both output streams.

### CLI Assertions

- Assert filesystem state directly after mutating commands.
- Prefer structured output parsing over substring matching when the command emits JSON, YAML, or a property list.
- For human diagnostics, assert the stable semantic fragment rather than timing text, ANSI escapes, or an entire rendered message unless the complete text is the contract.
- Assert failure types or `ExitCode` values for in-process commands. Assert numeric termination status only in black-box process tests.

## Isolation and Fixtures

- Give every test its own files or directory. Never reuse mutable fixture inputs directly.
- Copy fixture `input/` contents into an isolated workspace and compare the result against `expected/` byte-for-byte when preservation is part of the contract.
- Store test-created temporary data under the project-level `tmp/` directory and remove it with `defer`.
- Add `.serialized` only when tests truly share process-global or external state. Independent temporary workspaces should remain parallelizable.
- Set environment-dependent behavior explicitly. CLI process tests default to `NO_COLOR=1` and `TERM=dumb`.

## Regression Tests

- A bug fix should include a test that fails for the original defect and passes for the corrected behavior.
- Cover both success and refusal/error paths when a command promises filesystem safety.
- For parsers, include absent, empty, malformed, incomplete, repeated, and delimiter-like input where applicable.
- Preserve exact bytes outside the edited range when that is part of the feature contract.

## Test Files

- No `.xctestplan` files - those are Xcode-specific
- Simple directory structure: Tests/[TargetName]Tests/
- Test files use suffix: `*Tests.swift`
- Match the file they're testing with "Tests" suffix
  - Example: `MarkdownDocument.swift` → `MarkdownDocumentTests.swift`
