import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities

@Suite("explore command")
struct ExploreTests {
  @Test
  func `parse supports explore flags`() throws {
    let parsed = try CLIEntry.Explore.parseAsRoot([
      "README.md",
      "--expand", "About",
      "-P", "About/History",
      "-l", "12,18",
      "-C", "chap",
      "-F",
      "-p",
      "-r",
      "-f", "markdown"
    ])
    let command = try #require(parsed as? CLIEntry.Explore)

    #expect(command.expandedTitles == ["About"])
    #expect(command.expandedPaths == ["About/History"])
    #expect(command.expandedLines == [12, 18])
    #expect(command.expandedTitleContains == ["chap"])
    #expect(command.expandFrontmatter)
    #expect(command.expandPreamble)
    #expect(command.recursive)
    #expect(command.format == .markdown)
  }

  @Test
  func `parse supports markdown no stubs format`() throws {
    let parsed = try CLIEntry.Explore.parseAsRoot([
      "README.md",
      "--format", "markdown-no-stubs"
    ])
    let command = try #require(parsed as? CLIEntry.Explore)

    #expect(command.format == .markdownNoStubs)
  }

  @Test
  func `parse supports repeated and comma separated expand lines`() throws {
    let parsed = try CLIEntry.Explore.parseAsRoot([
      "README.md",
      "--expand-line", "42,57",
      "--expand-line", "81"
    ])
    let command = try #require(parsed as? CLIEntry.Explore)

    #expect(command.expandedLines == [42, 57, 81])
  }

  @Test
  func `parse rejects invalid comma separated expand lines`() {
    #expect(throws: Error.self) {
      _ = try CLIEntry.Explore.parseAsRoot([
        "README.md",
        "--expand-line", "42,abc"
      ])
    }

    #expect(throws: Error.self) {
      _ = try CLIEntry.Explore.parseAsRoot([
        "README.md",
        "--expand-line", "42, 57"
      ])
    }
  }

  @Test
  func `help includes progressive disclosure examples and matching descriptions`() throws {
    let help = CLIEntry.Explore.helpMessage().split(whereSeparator: \.isWhitespace).joined(separator: " ")

    #expect(help.contains("md-utils explore README.md --expand \"Usage\""))
    #expect(help.contains("md-utils explore README.md --expand-line 42,57,81"))
    #expect(help.contains("md-utils explore README.md --expand-title-contains \"Chapter 7\""))
    #expect(help.contains("heading title exactly matches"))
    #expect(help.contains("slash-separated heading path"))
    #expect(help.contains("heading title contains"))
  }

  @Test
  func `terminal default shows top heading level collapsed`() async throws {
    let document = try await ExploreDocument.build(from: """
      ### Alpha
      Alpha body.
      #### Alpha Child
      Child body.
      ### Beta
      Beta body.
      """)
    let output = render(document)

    #expect(output.contains("► ### Alpha (line 1,"))
    #expect(output.contains("► ### Beta (line 5,"))
    #expect(output.contains("Alpha body.") == false)
    #expect(output.contains("Alpha Child") == false)
  }

  @Test
  func `terminal default shows root sections even when levels differ`() async throws {
    let document = try await ExploreDocument.build(from: """
      Intro text.
      ## The Text
      Main body.
      ###### v1
      Verse body.
      # Footnotes
      [^1]: Note.
      """)
    let output = render(document)

    #expect(output.contains("► Preamble"))
    #expect(output.contains("► ## The Text"))
    #expect(output.contains("► # Footnotes"))
    #expect(output.contains("###### v1") == false)
  }

  @Test
  func `preamble can be expanded in terminal and markdown output`() async throws {
    let document = try await ExploreDocument.build(from: """
      [[John]] | [[John 2]]
      ***
      ## The Text
      Main body.
      """)

    let terminalOutput = render(document, expandPreamble: true)
    let markdownOutput = render(document, expandPreamble: true, format: .markdown)
    let collapsedMarkdownOutput = render(document, format: .markdown)

    #expect(terminalOutput.contains("▼ Preamble"))
    #expect(terminalOutput.contains("[[John]] | [[John 2]]"))
    #expect(markdownOutput.contains("[[John]] | [[John 2]]"))
    #expect(collapsedMarkdownOutput.contains("[[John]] | [[John 2]]") == false)
  }

  @Test
  func `terminal output shows expansion hint`() async throws {
    let document = try await ExploreDocument.build(from: """
      # Alpha
      Alpha body.
      """)

    let terminalOutput = render(document)
    let markdownOutput = render(document, format: .markdown)

    #expect(terminalOutput.contains("Hint: expand by title (-e), title contains (-C), path (-P), line (-l), frontmatter (-F), or preamble (-p)."))
    #expect(terminalOutput.hasPrefix("Hint:"))
    #expect(markdownOutput.contains("Hint:") == false)
  }

  @Test
  func `terminal expands matching title and shows immediate children collapsed`() async throws {
    let document = try await ExploreDocument.build(from: """
      # About
      About body.
      ## History
      History body.
      """)
    let output = render(document, expandedTitles: ["About"])

    #expect(output.contains("▼ # About (line 1)"))
    #expect(output.contains("About body."))
    #expect(output.contains("► ## History (line 3,"))
    #expect(output.contains("History body.") == false)
  }

  @Test
  func `terminal expands child target without revealing ancestor body`() async throws {
    let document = try await ExploreDocument.build(from: """
      # Root
      Root body.
      ## Commands
      Commands body.
      ## Other
      Other body.
      """)

    let childOnly = render(document, expandedTitles: ["Commands"])
    let parentAndChild = render(document, expandedTitles: ["Root", "Commands"])

    #expect(childOnly.contains("▼ # Root"))
    #expect(childOnly.contains("Root body.") == false)
    #expect(childOnly.contains("▼ ## Commands"))
    #expect(childOnly.contains("Commands body."))
    #expect(childOnly.contains("► ## Other"))
    #expect(parentAndChild.contains("Root body."))
    #expect(parentAndChild.contains("Commands body."))
  }

  @Test
  func `terminal expands duplicate title matches`() async throws {
    let document = try await ExploreDocument.build(from: """
      # Setup
      First body.
      # Setup
      Second body.
      """)
    let output = render(document, expandedTitles: ["Setup"])

    #expect(output.contains("First body."))
    #expect(output.contains("Second body."))
  }

  @Test
  func `terminal expands headings by case insensitive title substring`() async throws {
    let document = try await ExploreDocument.build(from: """
      # Chapter 7: Motivation
      Motivation body.
      # Chapter 8: Focus
      Focus body.
      """)
    let output = render(document, expandedTitleContains: ["chapter 7"])

    #expect(output.contains("Motivation body."))
    #expect(output.contains("Focus body.") == false)
  }

  @Test
  func `terminal expands by path and line`() async throws {
    let document = try await ExploreDocument.build(from: """
      # About
      ## History
      History body.
      # Usage
      Usage body.
      """)
    let output = render(document, expandedPaths: ["About/History"], expandedLines: [4])

    #expect(output.contains("▼ # About"))
    #expect(output.contains("▼ ## History"))
    #expect(output.contains("History body."))
    #expect(output.contains("▼ # Usage"))
    #expect(output.contains("Usage body."))
  }

  @Test
  func `terminal warns for unmatched expansion targets and suggests one close title or path`() async throws {
    let document = try await ExploreDocument.build(from: """
      # My Notes
      ## Chapter 7: How to Motivate Your Brain [03:30:00]
      Body.
      # Usage
      Usage body.
      """)
    let output = render(
      document,
      expandedTitles: ["Chapter 7: How to Motivate Your Brain"],
      expandedPaths: ["My Notes/Chapter 7: How to Motivate Your Brain"],
      expandedLines: [99],
      expandedTitleContains: ["missing"]
    )

    #expect(output.contains("Warning: no heading matched --expand \"Chapter 7: How to Motivate Your Brain\""))
    #expect(output.contains("Did you mean: Chapter 7: How to Motivate Your Brain [03:30:00]"))
    #expect(output.contains("Warning: no heading matched --expand-path \"My Notes/Chapter 7: How to Motivate Your Brain\""))
    #expect(output.contains("Did you mean: My Notes/Chapter 7: How to Motivate Your Brain [03:30:00]"))
    #expect(output.contains("Warning: no heading matched --expand-line 99"))
    #expect(output.contains("Warning: no heading matched --expand-title-contains \"missing\""))
  }

  @Test
  func `markdown output omits unmatched target warnings`() async throws {
    let document = try await ExploreDocument.build(from: """
      # Usage
      Usage body.
      """)
    let output = render(document, expandedTitles: ["Missing"], format: .markdown)

    #expect(output.contains("Warning:") == false)
    #expect(output.contains("Did you mean:") == false)
    #expect(output.contains("# Usage"))
  }

  @Test
  func `terminal recursive expansion expands descendants`() async throws {
    let document = try await ExploreDocument.build(from: """
      # About
      Intro.
      ## History
      History body.
      ### Deep
      Deep body.
      """)
    let output = render(document, expandedTitles: ["About"], recursive: true)

    #expect(output.contains("▼ ## History"))
    #expect(output.contains("History body."))
    #expect(output.contains("▼ ### Deep"))
    #expect(output.contains("Deep body."))
  }

  @Test
  func `terminal renders frontmatter collapsed and expanded`() async throws {
    let document = try await ExploreDocument.build(from: """
      ---
      title: Test
      tags:
        - swift
      ---
      # Intro
      """)

    let collapsed = render(document)
    let expanded = render(document, expandFrontmatter: true)

    #expect(collapsed.contains("► Frontmatter"))
    #expect(collapsed.contains("2 fields"))
    #expect(collapsed.contains("title: Test") == false)
    #expect(expanded.contains("▼ Frontmatter"))
    #expect(expanded.contains("---\ntitle: Test"))
  }

  @Test
  func `markdown output uses source only and omits collapsed frontmatter`() async throws {
    let document = try await ExploreDocument.build(from: """
      ---
      title: Test
      ---
      # About
      About body.
      ## History
      History body.
      """)

    let collapsed = render(document, format: .markdown)
    let expanded = render(document, expandedTitles: ["About"], expandFrontmatter: true, format: .markdown)

    #expect(collapsed.contains("---") == false)
    #expect(collapsed.contains("►") == false)
    #expect(collapsed.contains("# About"))
    #expect(collapsed.contains("About body.") == false)
    #expect(expanded.contains("---\ntitle: Test\n---"))
    #expect(expanded.contains("About body."))
    #expect(expanded.contains("## History"))
    #expect(expanded.contains("History body.") == false)
  }

  @Test
  func `markdown no stubs omits collapsed heading stubs`() async throws {
    let document = try await ExploreDocument.build(from: """
      # Root
      Root body.
      ## Commands
      Commands body.
      ## Other
      Other body.
      """)

    let defaultOutput = render(document, format: .markdownNoStubs)
    let childOutput = render(document, expandedTitles: ["Commands"], format: .markdownNoStubs)
    let parentAndChildOutput = render(
      document,
      expandedTitles: ["Root", "Commands"],
      format: .markdownNoStubs
    )

    #expect(defaultOutput == "")
    #expect(childOutput.contains("# Root"))
    #expect(childOutput.contains("Root body.") == false)
    #expect(childOutput.contains("## Commands"))
    #expect(childOutput.contains("Commands body."))
    #expect(childOutput.contains("## Other") == false)
    #expect(parentAndChildOutput.contains("Root body."))
    #expect(parentAndChildOutput.contains("Commands body."))
    #expect(parentAndChildOutput.contains("## Other") == false)
  }

  @Test
  func `run rejects directories`() async throws {
    let directory = Path.temporary + "explore-tests-\(UUID().uuidString)"
    try directory.mkdir()
    defer { try? directory.delete() }

    let parsed = try CLIEntry.Explore.parseAsRoot([directory.string])
    var command = try #require(parsed as? CLIEntry.Explore)

    await #expect(throws: Error.self) {
      try await command.run()
    }
  }

  private func render(
    _ document: ExploreDocument,
    expandedTitles: [String] = [],
    expandedPaths: [String] = [],
    expandedLines: [Int] = [],
    expandedTitleContains: [String] = [],
    expandFrontmatter: Bool = false,
    expandPreamble: Bool = false,
    recursive: Bool = false,
    format: CLIEntry.ExploreFormat = .terminal
  ) -> String {
    ExploreRenderer(
      document: document,
      expandedTitles: expandedTitles,
      expandedPaths: expandedPaths,
      expandedLines: expandedLines,
      expandedTitleContains: expandedTitleContains,
      expandFrontmatter: expandFrontmatter,
      expandPreamble: expandPreamble,
      recursive: recursive,
      format: format
    ).render()
  }
}
