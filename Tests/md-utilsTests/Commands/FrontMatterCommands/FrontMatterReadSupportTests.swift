import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

@Suite("wrapped frontmatter CLI read support")
struct FrontMatterReadSupportTests {
  @Test
  func `Built-in extension preset reads a block anywhere in Swift source`() throws {
    let file = try temporaryFile(
      named: "example.swift",
      content: """
        import Foundation

        /*
        ---
        title: Embedded metadata
        ---
        */

        print("hello")
        """
    )
    defer { try? file.parent().delete() }
    let reader = try makeReader()

    let document = try reader.document(at: file)

    #expect(document.getValue(forKey: "title")?.string == "Embedded metadata")
  }

  @Test
  func `Additional complete blocks produce a line diagnostic without parsing later YAML`() throws {
    let file = try temporaryFile(
      named: "duplicate.swift",
      content: """
        /*
        ---
        title: First
        ---
        */
        let value = 1
        /*
        ---
        definitely: [invalid
        ---
        */
        """
    )
    defer { try? file.parent().delete() }
    let reader = try makeReader()

    do {
      _ = try reader.document(at: file)
      Issue.record("Expected duplicate wrapped frontmatter to fail")
    } catch {
      #expect(error.localizedDescription.contains(file.string))
      #expect(error.localizedDescription.contains("additional blocks begin on line(s) 7"))
    }
  }

  @Test
  func `Malformed YAML in the first complete block remains a YAML diagnostic`() throws {
    let file = try temporaryFile(
      named: "invalid.swift",
      content: """
        /*
        ---
        title: [invalid
        ---
        */
        """
    )
    defer { try? file.parent().delete() }
    let reader = try makeReader()

    #expect(throws: YAMLConversionError.self) {
      try reader.document(at: file)
    }
  }

  @Test
  func `A file without a complete block has empty frontmatter without error`() throws {
    let file = try temporaryFile(
      named: "plain.swift",
      content: "let value = 1\n"
    )
    defer { try? file.parent().delete() }

    let document = try makeReader().document(at: file)

    #expect(document.frontMatter.isEmpty)
  }

  @Test
  func `Non-Markdown wrapped frontmatter is ignored without explicit opt-in`() throws {
    let file = try temporaryFile(
      named: "not-opted-in.swift",
      content: """
        /*
        ---
        title: Ignored
        ---
        */
        """
    )
    defer { try? file.parent().delete() }
    let reader = FrontMatterFileReader(
      includeNonMarkdown: false,
      rawSyntax: nil,
      namedSyntax: nil,
      projectConfiguration: try WrappedFrontMatterProjectConfiguration(),
      useBuiltInPresets: true
    )

    let document = try reader.document(at: file)

    #expect(document.frontMatter.isEmpty)
  }

  @Test
  func `One-off delimiters take precedence over extension inference`() throws {
    let file = try temporaryFile(
      named: "raw.swift",
      content: """
        <!--
        ---
        title: One-off
        ---
        -->
        """
    )
    defer { try? file.parent().delete() }
    let reader = FrontMatterFileReader(
      includeNonMarkdown: true,
      rawSyntax: .htmlComment,
      namedSyntax: nil,
      projectConfiguration: try WrappedFrontMatterProjectConfiguration(),
      useBuiltInPresets: true
    )

    let document = try reader.document(at: file)

    #expect(document.getValue(forKey: "title")?.string == "One-off")
  }

  @Test
  func `Explicit syntax takes precedence over project and built-in extension inference`() throws {
    let file = try temporaryFile(
      named: "precedence.swift",
      content: #"""
        """
        ---
        title: Explicit
        ---
        """
        """#
    )
    defer { try? file.parent().delete() }
    let projectConfiguration = try WrappedFrontMatterProjectConfiguration(
      extensionMappings: ["swift": "html-comment"]
    )
    let reader = FrontMatterFileReader(
      includeNonMarkdown: true,
      rawSyntax: nil,
      namedSyntax: .pythonDocstring,
      projectConfiguration: projectConfiguration,
      useBuiltInPresets: true
    )

    let document = try reader.document(at: file)

    #expect(document.getValue(forKey: "title")?.string == "Explicit")
  }

  @Test
  func `Project extension mapping takes precedence and survives disabled presets`() throws {
    let file = try temporaryFile(
      named: "mapping.swift",
      content: """
        <!--
        ---
        title: Project mapping
        ---
        -->
        """
    )
    defer { try? file.parent().delete() }
    let projectConfiguration = try WrappedFrontMatterProjectConfiguration(
      extensionMappings: ["swift": "html-comment"]
    )
    let reader = FrontMatterFileReader(
      includeNonMarkdown: true,
      rawSyntax: nil,
      namedSyntax: nil,
      projectConfiguration: projectConfiguration,
      useBuiltInPresets: false
    )

    let document = try reader.document(at: file)

    #expect(document.getValue(forKey: "title")?.string == "Project mapping")
  }

  @Test
  func `Project-defined syntax is resolved through its extension mapping`() throws {
    let file = try temporaryFile(
      named: "template.erb",
      content: """
        <%#
        ---
        title: Custom syntax
        ---
        %>
        """
    )
    defer { try? file.parent().delete() }
    let syntax = try WrappedFrontMatterSyntax(
      openingCommentDelimiter: "<%#",
      closingCommentDelimiter: "%>"
    )
    let projectConfiguration = try WrappedFrontMatterProjectConfiguration(
      syntaxes: ["erb-comment": syntax],
      extensionMappings: ["erb": "erb-comment"]
    )
    let reader = FrontMatterFileReader(
      includeNonMarkdown: true,
      rawSyntax: nil,
      namedSyntax: nil,
      projectConfiguration: projectConfiguration,
      useBuiltInPresets: true
    )

    let document = try reader.document(at: file)

    #expect(document.getValue(forKey: "title")?.string == "Custom syntax")
  }

  @Test
  func `CLI exposes approved wrapped frontmatter options`() throws {
    let parsed = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "title",
      "--include-non-md",
      "--frontmatter-comment-open", "/*",
      "--frontmatter-comment-close", "*/",
      "--no-frontmatter-presets",
      "example.swift",
    ])
    let command = try #require(parsed as? CLIEntry.FrontMatterCommands.Has)

    #expect(command.frontmatterSource.includeNonMarkdown)
    #expect(command.frontmatterSource.commentOpen == "/*")
    #expect(command.frontmatterSource.commentClose == "*/")
    #expect(command.frontmatterSource.noPresets)
  }

  @Test
  func `Explicit extensions still constrain an opted-in directory scan`() throws {
    let directory = Path.current + "tmp/wrapped-frontmatter-paths-\(UUID().uuidString)/"
    try directory.mkpath()
    defer { try? directory.delete() }
    try (directory + "included.swift").write("")
    try (directory + "excluded.py").write("")
    let parsed = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "title",
      "--include-non-md",
      "--extensions", "swift",
      directory.string,
    ])
    let command = try #require(parsed as? CLIEntry.FrontMatterCommands.Has)

    let paths = try command.options.resolvedPaths(
      includeAllExtensions: command.frontmatterSource.includeNonMarkdown
    )

    #expect(paths.map(\.lastComponent) == ["included.swift"])
  }

  @Test
  func `Raw comment delimiters and named syntax are mutually exclusive`() throws {
    let parsed = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "title",
      "--include-non-md",
      "--frontmatter-syntax", "c-block",
      "--frontmatter-comment-open", "/*",
      "--frontmatter-comment-close", "*/",
      "example.swift",
    ])
    let command = try #require(parsed as? CLIEntry.FrontMatterCommands.Has)

    #expect(throws: ValidationError.self) {
      try command.frontmatterSource.makeReader()
    }
  }

  @Test
  func `All approved read-only commands expose non-Markdown opt-in`() throws {
    let dump = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      "--include-non-md", "example.swift",
    ])
    let get = try CLIEntry.FrontMatterCommands.Get.parseAsRoot([
      "--key", "title", "--include-non-md", "example.swift",
    ])
    let has = try CLIEntry.FrontMatterCommands.Has.parseAsRoot([
      "--key", "title", "--include-non-md", "example.swift",
    ])
    let list = try CLIEntry.FrontMatterCommands.List.parseAsRoot([
      "--include-non-md", "example.swift",
    ])
    let search = try CLIEntry.FrontMatterCommands.Search.parseAsRoot([
      "title", "--include-non-md", "example.swift",
    ])
    let unique = try CLIEntry.FrontMatterCommands.Unique.parseAsRoot([
      "title", "--include-non-md", "example.swift",
    ])

    #expect((dump as? CLIEntry.FrontMatterCommands.Dump)?.frontmatterSource.includeNonMarkdown == true)
    #expect((get as? CLIEntry.FrontMatterCommands.Get)?.frontmatterSource.includeNonMarkdown == true)
    #expect((has as? CLIEntry.FrontMatterCommands.Has)?.frontmatterSource.includeNonMarkdown == true)
    #expect((list as? CLIEntry.FrontMatterCommands.List)?.frontmatterSource.includeNonMarkdown == true)
    #expect((search as? CLIEntry.FrontMatterCommands.Search)?.frontmatterSource.includeNonMarkdown == true)
    #expect((unique as? CLIEntry.FrontMatterCommands.Unique)?.frontmatterSource.includeNonMarkdown == true)
  }

  private func makeReader() throws -> FrontMatterFileReader {
    FrontMatterFileReader(
      includeNonMarkdown: true,
      rawSyntax: nil,
      namedSyntax: nil,
      projectConfiguration: try WrappedFrontMatterProjectConfiguration(),
      useBuiltInPresets: true
    )
  }

  private func temporaryFile(named name: String, content: String) throws -> Path {
    let directory = Path.current + "tmp/wrapped-frontmatter-tests-\(UUID().uuidString)/"
    try directory.mkpath()
    let file = directory + name
    try file.write(content)
    return file
  }
}
