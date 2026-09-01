import MarkdownUtilitiesCore
import Parsing
import Testing

@Suite("Wrapped frontmatter parser")
struct WrappedFrontMatterParserTests {
  @Test
  func `conforms to Parsing Parser and consumes its complete input`() throws {
    let source = "/*\n---\ntitle: Example\n---\n*/\nbody"
    var input = source[...]
    let scan = try parseThroughProtocol(
      WrappedFrontMatterParser(syntax: .cBlock),
      input: &input
    )
    let block = try #require(scan.firstBlock)

    #expect(input.isEmpty)
    #expect(String(source[block.range]) == "/*\n---\ntitle: Example\n---\n*/")
  }

  @Test(
    arguments: [
      (FrontMatterSyntax.cBlock, "/*", "*/"),
      (FrontMatterSyntax.htmlComment, "<!--", "-->"),
      (FrontMatterSyntax.pythonDocstring, "\"\"\"", "\"\"\""),
      (FrontMatterSyntax.powershellBlock, "<#", "#>"),
      (FrontMatterSyntax.luaBlock, "--[[", "]]"),
    ]
  )
  func `discovers each shipped wrapper anywhere in LF text`(
    syntax: FrontMatterSyntax,
    opening: String,
    closing: String
  ) throws {
    let source = "prefix\n\(opening)\n---\ntitle: Example\nnested:\n  enabled: true\n---\n\(closing)\nsuffix\n"
    let scan = WrappedFrontMatterParser(syntax: syntax).parse(source)
    let block = try #require(scan.firstBlock)

    #expect(block.openingLine == 2)
    #expect(block.rawYAML == "title: Example\nnested:\n  enabled: true\n")
    #expect(String(source[block.range]) == "\(opening)\n---\ntitle: Example\nnested:\n  enabled: true\n---\n\(closing)")
    #expect(scan.additionalOpeningLines.isEmpty)
  }

  @Test
  func `reports later blocks by their 1-based opening lines`() throws {
    let source = """
      /*
      ---
      title: First
      ---
      */

      body
      /*
      ---
      this: is: deliberately invalid later YAML
      ---
      */
      """
    let scan = WrappedFrontMatterParser(syntax: .cBlock).parse(source)

    #expect(try #require(scan.firstBlock).openingLine == 1)
    #expect(scan.additionalOpeningLines == [8])
  }

  @Test
  func `discovers wrapped TOML frontmatter`() throws {
    let source = "/*\n+++\ntitle = \"Example\"\n+++\n*/\nstruct Example {}\n"
    let block = try #require(WrappedFrontMatterParser(syntax: .cBlock).parse(source).firstBlock)

    #expect(block.format == .toml)
    #expect(block.rawFrontMatter == "title = \"Example\"\n")
  }

  @Test
  func `treats incomplete candidates as absent`() {
    let missingYAMLCloser = "/*\n---\ntitle: Example\n*/\n"
    let missingWrapperCloser = "/*\n---\ntitle: Example\n---\n"

    #expect(WrappedFrontMatterParser(syntax: .cBlock).parse(missingYAMLCloser).firstBlock == nil)
    #expect(WrappedFrontMatterParser(syntax: .cBlock).parse(missingWrapperCloser).firstBlock == nil)
  }

  @Test
  func `accepts empty frontmatter and preserves payload indentation`() throws {
    let empty = WrappedFrontMatterParser(syntax: .htmlComment).parse("<!--\n---\n---\n-->\n")
    #expect(try #require(empty.firstBlock).rawYAML == "")

    let indented = WrappedFrontMatterParser(syntax: .pythonDocstring).parse(
      "\"\"\"\n---\nvalue: |\n  first\n  second\n---\n\"\"\"\n"
    )
    #expect(try #require(indented.firstBlock).rawYAML == "value: |\n  first\n  second\n")
  }

  @Test
  func `does not treat delimiter substrings or non-closing marker lines as closers`() throws {
    let source = """
      /*
      ---
      title: contains --- inside
      note: keep scanning
      ---
      not-the-wrapper
      ---
      */
      """
    let block = try #require(WrappedFrontMatterParser(syntax: .cBlock).parse(source).firstBlock)
    #expect(block.rawYAML.contains("not-the-wrapper"))
  }

  @Test
  func `maps extensions case-insensitively and leaves unsupported formats unmapped`() {
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: ".SWIFT") == .cBlock)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "JSONC") == .cBlock)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "html") == .htmlComment)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "PY") == .pythonDocstring)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "ps1") == .powershellBlock)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "lua") == .luaBlock)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "json") == nil)
    #expect(FrontMatterSyntax.shippedSyntax(forExtension: "toml") == nil)
  }
}

private func parseThroughProtocol<P: Parsing.Parser>(
  _ parser: P,
  input: inout P.Input
) throws -> P.Output {
  try parser.parse(&input)
}
