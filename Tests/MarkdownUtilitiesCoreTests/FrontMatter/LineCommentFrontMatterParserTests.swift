import MarkdownUtilitiesCore
import Parsing
import Testing

@Suite("Line-comment frontmatter parser")
struct LineCommentFrontMatterParserTests {
  private let parser = LineCommentFrontMatterParser()

  @Test
  func `conforms to Parsing Parser and consumes its complete input`() throws {
    let source = "# ---\n# title: Example\n# ---\nbody"
    var input = source[...]
    let scan = try parseLineCommentThroughProtocol(parser, input: &input)
    let block = try #require(scan.frontMatter)

    #expect(input.isEmpty)
    #expect(String(source[block.range]) == "# ---\n# title: Example\n# ---")
  }

  @Test
  func `parses YAML while preserving logical bytes and indentation`() throws {
    let source = "# ---\n# title: Example\n# nested:\n#   enabled: true\n# literal: |\n#   # retained\n# ---\necho body\r\nnext\r"
    let block = try #require(parser.parse(source).frontMatter)

    #expect(block.format == .yaml)
    #expect(
      block.rawFrontMatter
        == "title: Example\nnested:\n  enabled: true\nliteral: |\n  # retained"
    )
    #expect(block.openingLine == 1)
    #expect(block.lineEnding == "\n")
    #expect(String(source[block.range]) == String(source.dropLast("\necho body\r\nnext\r".count)))
  }

  @Test
  func `parses TOML and canonical empty logical line spellings`() throws {
    let source = "# +++\n# title = \"Example\"\n#\n# \n\n# enabled = true\n# +++\nbody"
    let block = try #require(parser.parse(source).frontMatter)

    #expect(block.format == .toml)
    #expect(block.rawFrontMatter == "title = \"Example\"\n\n\n\nenabled = true")
  }

  @Test
  func `supports BOM and both approved shebang-relative placements`() throws {
    let sources = [
      "\u{FEFF}# ---\n# title: BOM\n# ---\nbody",
      "#!/bin/sh\n# ---\n# title: Immediate\n# ---\nbody",
      "#!/bin/sh\n\n# ---\n# title: Gap\n# ---\nbody",
    ]

    for (offset, source) in sources.enumerated() {
      let block = try #require(parser.parse(source).frontMatter)
      #expect(block.openingLine == offset + 1)
    }

    let bomShebang = "\u{FEFF}#!/bin/sh\n# ---\n# title: BOM shebang\n# ---\nbody"
    #expect(try #require(parser.parse(bomShebang).frontMatter).openingLine == 2)
  }

  @Test
  func `rejects unapproved prologues and later delimiters`() {
    let sources = [
      " \n# ---\n# title: Later\n# ---\n",
      "#!/bin/sh\n \n# ---\n# title: Later\n# ---\n",
      "#!/bin/sh\n\n\n# ---\n# title: Later\n# ---\n",
      "body\n# ---\n# title: Later\n# ---\n",
    ]

    for source in sources {
      let scan = parser.parse(source)
      #expect(scan.frontMatter == nil)
      #expect(scan.recognizedRange == nil)
      #expect(scan.diagnostic == nil)
    }
  }

  @Test
  func `treats a lone opener and a delimiter beyond host content as absent`() {
    let sources = [
      "# ---\n# title: Alone\n",
      "# ---\n# title: Stops\nhost body\n# ---\n",
      "# ---",
    ]

    for source in sources {
      let scan = parser.parse(source)
      #expect(scan.frontMatter == nil)
      #expect(scan.recognizedRange == nil)
      #expect(scan.diagnostic == nil)
    }
  }

  @Test
  func `diagnoses a mismatched delimiter only after recognizing the pair`() throws {
    let source = "# ---\n# title: Example\n# +++\nbody"
    let scan = parser.parse(source)
    let range = try #require(scan.recognizedRange)

    #expect(scan.frontMatter == nil)
    #expect(
      scan.diagnostic
        == .mismatchedDelimiter(opening: .yaml, closing: .toml, closingLine: 3)
    )
    #expect(String(source[range]) == "# ---\n# title: Example\n# +++")
  }

  @Test
  func `diagnoses the first malformed prefix only inside a recognized pair`() throws {
    let source = "#!/usr/bin/env bash\n# ---\n# valid: true\n#invalid\n# ---\necho body"
    let scan = parser.parse(source)
    let range = try #require(scan.recognizedRange)

    #expect(scan.frontMatter == nil)
    #expect(scan.diagnostic == .invalidCommentPrefix(line: 4))
    #expect(String(source[range]).hasSuffix("# ---"))
  }

  @Test
  func `follows the existing LF-only frontmatter policy`() {
    let source = "# ---\r\n# title: Example\r\n# ---\r\nbody\nnext\r"
    let scan = parser.parse(source)

    #expect(scan.frontMatter == nil)
    #expect(scan.recognizedRange == nil)
    #expect(scan.diagnostic == nil)
  }

  @Test
  func `accepts empty YAML and exits before a large ordinary body`() throws {
    let body = String(repeating: "ordinary host bytes\n", count: 100_000)
    let source = "# ---\n# ---\n" + body
    let block = try #require(parser.parse(source).frontMatter)

    #expect(block.rawFrontMatter == "")
    #expect(String(source[block.range]) == "# ---\n# ---")
  }

  @Test
  func `ordinary large single-line input takes the no-opener early exit`() {
    let source = "ordinary=" + String(repeating: "x", count: 1_000_000)
    let scan = parser.parse(source)

    #expect(scan.frontMatter == nil)
    #expect(scan.recognizedRange == nil)
    #expect(scan.diagnostic == nil)
  }

  @Test
  func `large lone-opener header remains absent without materializing physical lines`() {
    let source = "# ---\n" + String(repeating: "# ordinary comment\n", count: 100_000)
    let scan = parser.parse(source)

    #expect(scan.frontMatter == nil)
    #expect(scan.recognizedRange == nil)
    #expect(scan.diagnostic == nil)
  }
}

private func parseLineCommentThroughProtocol<P: Parsing.Parser>(
  _ parser: P,
  input: inout P.Input
) throws -> P.Output {
  try parser.parse(&input)
}

@Suite("Non-Markdown frontmatter registry")
struct NonMarkdownFrontMatterRegistryTests {
  @Test
  func `maps every issue 129 exact basename case-sensitively`() {
    let basenames = [
      ".gitignore", ".dockerignore", ".ignore", ".npmignore", ".prettierignore",
      ".eslintignore", ".stylelintignore", ".helmignore", ".gcloudignore",
      ".vercelignore", ".cursorignore", ".git-blame-ignore-revs", "Makefile",
      "GNUmakefile", "CMakeLists.txt", "Justfile", "Gemfile", "Rakefile", "Brewfile",
      "Vagrantfile", "Podfile", "Fastfile", "Appfile", "Dangerfile", "Guardfile",
      "Pipfile", "requirements.txt", "constraints.txt", ".Rprofile", ".Renviron",
      ".env.schema",
    ]

    #expect(Set(basenames) == NonMarkdownFrontMatterSyntax.shippedLineCommentBasenames)
    for basename in basenames {
      #expect(
        NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: basename) == .lineComment
      )
    }
    #expect(NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: "makefile") == nil)
    #expect(NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: ".ENV.SCHEMA") == nil)
  }

  @Test
  func `maps every issue 129 extension case-insensitively`() {
    let extensions = [
      "sh", "bash", "zsh", "fish", "rb", "rake", "gemspec", "r", "yaml", "yml",
      "toml", "mk", "cmake", "properties", "nix", "bzl", "bazel", "tf", "tfvars",
    ]

    #expect(Set(extensions) == NonMarkdownFrontMatterSyntax.shippedLineCommentExtensions)
    for fileExtension in extensions {
      #expect(
        NonMarkdownFrontMatterSyntax.shippedSyntax(
          forFileName: "example.\(fileExtension.uppercased())"
        ) == .lineComment
      )
    }
  }

  @Test
  func `keeps exact basename and wrapped mappings authoritative`() {
    #expect(
      NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: "requirements.txt")
        == .lineComment
    )
    #expect(NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: "notes.txt") == nil)
    #expect(
      NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: "script.py")
        == .wrapped(.pythonDocstring)
    )
    #expect(
      NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: "script.ps1")
        == .wrapped(.powershellBlock)
    )
    #expect(NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: ".env") == nil)
    #expect(NonMarkdownFrontMatterSyntax.shippedSyntax(forFileName: ".env.local") == nil)
  }
}
