import Testing
@testable import MarkdownUtilitiesCore

@Suite("Wrapped frontmatter parser")
struct WrappedFrontMatterParserTests {
  @Test("Extracts HTML-wrapped YAML")
  func extractsHTMLWrappedYAML() throws {
    var input: Substring = """
      <!--
      ---
      title: Example
      tags:
        - html
      ---
      -->
      <main>Example</main>
      """[...]

    let raw = try WrappedFrontMatterParser(syntax: .htmlComment).parse(&input)

    #expect(raw == "title: Example\ntags:\n  - html")
    #expect(input == "\n<main>Example</main>")
  }

  @Test("Extracts an empty YAML block")
  func extractsEmptyYAML() throws {
    var input: Substring = """
      /*
      ---
      ---
      */
      """[...]

    let raw = try WrappedFrontMatterParser(syntax: .cBlock).parse(&input)

    #expect(raw.isEmpty)
    #expect(input.isEmpty)
  }

  @Test("Does not recognize pure CRLF envelopes")
  func doesNotRecognizeCRLF() {
    let source = "/*\r\n---\r\ntitle: Example\r\n---\r\n*/\r\nbody"

    let result = WrappedFrontMatterScanner(syntax: .cBlock).scan(source)

    #expect(result.rawFrontMatter == nil)
    #expect(result.firstBlock == nil)
  }

  @Test("Scans for a complete block in the middle of source")
  func scansMiddleOfSource() throws {
    let source = """
      import Foundation

      /*
      ---
      title: Example
      ---
      */

      struct Example {}
      """

    let result = WrappedFrontMatterScanner(syntax: .cBlock).scan(source)
    let mapping = try YAMLConversion.parse(try #require(result.rawFrontMatter))

    #expect(mapping["title"]?.string == "Example")
    #expect(result.firstBlock?.openingLine == 3)
    #expect(result.firstBlock?.closingLine == 7)
    #expect(result.additionalBlocks.isEmpty)
  }

  @Test("Ignores incomplete candidates and finds a later complete block")
  func ignoresIncompleteCandidates() {
    let source = """
      /*
      not frontmatter
      */

      /*
      ---
      title: Complete
      ---
      */
      """

    let result = WrappedFrontMatterScanner(syntax: .cBlock).scan(source)

    #expect(result.rawFrontMatter == "title: Complete")
    #expect(result.firstBlock?.openingLine == 5)
    #expect(result.additionalBlocks.isEmpty)
  }

  @Test("Reports later blocks without exposing their YAML")
  func reportsAdditionalBlocks() {
    let source = [
      "\"\"\"",
      "---",
      "title: First",
      "---",
      "\"\"\"",
      "",
      "value = 1",
      "",
      "\"\"\"",
      "---",
      "this: is: not: valid: yaml",
      "---",
      "\"\"\"",
    ].joined(separator: "\n")

    let result = WrappedFrontMatterScanner(syntax: .pythonDocstring).scan(source)

    #expect(result.rawFrontMatter == "title: First")
    #expect(result.firstBlock?.openingLine == 1)
    #expect(result.hasMultipleBlocks)
    #expect(result.additionalBlocks.map(\.openingLine) == [9])
  }

  @Test("Does not close on delimiter text in a YAML value")
  func delimiterTextInValue() throws {
    var input: Substring = """
      <!--
      ---
      title: "contains --- text"
      description: still YAML
      ---
      -->
      """[...]

    let raw = try WrappedFrontMatterParser(syntax: .htmlComment).parse(&input)

    #expect(raw == "title: \"contains --- text\"\ndescription: still YAML")
  }

  @Test("Requires comment delimiters to occupy complete lines")
  func requiresCompleteDelimiterLines() {
    let source = """
      prefix <!--
      ---
      title: Not Frontmatter
      ---
      --> suffix
      """

    let result = WrappedFrontMatterScanner(syntax: .htmlComment).scan(source)

    #expect(result.rawFrontMatter == nil)
    #expect(result.firstBlock == nil)
  }

  @Test("Does not recognize a Pandoc-style closing marker")
  func doesNotRecognizePandocClosingMarker() {
    let source = """
      /*
      ---
      title: Not Frontmatter
      ...
      */
      """

    let result = WrappedFrontMatterScanner(syntax: .cBlock).scan(source)

    #expect(result.rawFrontMatter == nil)
    #expect(result.firstBlock == nil)
  }

  @Test("Built-in presets infer the approved common extensions case-insensitively")
  func builtInPresetInference() {
    #expect(WrappedFrontMatterPreset.inferred(forExtension: ".SWIFT") == .cBlock)
    #expect(WrappedFrontMatterPreset.inferred(forExtension: "html") == .htmlComment)
    #expect(WrappedFrontMatterPreset.inferred(forExtension: "PY") == .pythonDocstring)
    #expect(WrappedFrontMatterPreset.inferred(forExtension: "ps1") == .powershellBlock)
    #expect(WrappedFrontMatterPreset.inferred(forExtension: "lua") == .luaBlock)
    #expect(WrappedFrontMatterPreset.inferred(forExtension: "json") == nil)
  }

  @Test("Scans a representative directory-scale source workload")
  func scansRepresentativeDirectoryScaleWorkload() {
    let prefix = (0..<400).map { "let value\($0) = \($0)" }.joined(separator: "\n")
    let source = """
      \(prefix)
      /*
      ---
      title: Example
      ---
      */
      """
    let scanner = WrappedFrontMatterScanner(syntax: .cBlock)
    var discovered = 0

    for _ in 0..<250 {
      if scanner.scan(source).rawFrontMatter == "title: Example" {
        discovered += 1
      }
    }

    #expect(discovered == 250)
  }
}
