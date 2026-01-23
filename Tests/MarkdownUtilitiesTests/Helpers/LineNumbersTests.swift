//
//  LineNumbersTests.swift
//  MarkdownUtilitiesTests
//
//  Tests for line number utilities

import Testing
import Foundation
@testable import MarkdownUtilities

@Suite("LineNumbers Utilities")
struct LineNumbersTests {

  // MARK: - String.substring(lines:) Tests

  @Test
  func `substring extracts single line`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let result = try #require(text.substring(lines: 2...2))
    #expect(String(result) == "Line 2")
  }

  @Test
  func `substring extracts line range`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    Line 4
    """

    let result = try #require(text.substring(lines: 2...3))
    #expect(String(result) == "Line 2\nLine 3")
  }

  @Test
  func `substring extracts from first line`() async throws {
    let text = """
    First line
    Second line
    Third line
    """

    let result = try #require(text.substring(lines: 1...2))
    #expect(String(result) == "First line\nSecond line")
  }

  @Test
  func `substring extracts to last line`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let result = try #require(text.substring(lines: 2...3))
    #expect(String(result) == "Line 2\nLine 3")
  }

  @Test
  func `substring extracts entire document`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let result = try #require(text.substring(lines: 1...3))
    #expect(String(result) == text)
  }

  @Test
  func `substring handles range beyond file length`() async throws {
    let text = """
    Line 1
    Line 2
    """

    let result = try #require(text.substring(lines: 1...10))
    #expect(String(result) == text)
  }

  @Test
  func `substring returns nil for invalid range start`() async throws {
    let text = """
    Line 1
    Line 2
    """

    let result = text.substring(lines: 0...2)
    #expect(result == nil)
  }

  // Note: Cannot test invalid range order (3...1) because ClosedRange construction
  // itself will fatalError before substring(lines:) can be called.
  // Swift's ClosedRange requires lowerBound <= upperBound at construction time.

  @Test
  func `substring returns nil when start exceeds file length`() async throws {
    let text = """
    Line 1
    Line 2
    """

    let result = text.substring(lines: 10...15)
    #expect(result == nil)
  }

  @Test
  func `substring handles empty lines`() async throws {
    let text = """
    Line 1

    Line 3

    Line 5
    """

    let result = try #require(text.substring(lines: 2...4))
    #expect(String(result) == "\nLine 3\n")
  }

  @Test
  func `substring handles text with no newlines`() async throws {
    let text = "Single line"

    let result = try #require(text.substring(lines: 1...1))
    #expect(String(result) == text)
  }

  @Test
  func `substring handles text with trailing newline`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3

    """

    let result = try #require(text.substring(lines: 1...3))
    #expect(String(result) == "Line 1\nLine 2\nLine 3")
  }

  @Test
  func `substring extracts last line without trailing newline`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let result = try #require(text.substring(lines: 3...3))
    #expect(String(result) == "Line 3")
  }

  // MARK: - StringProtocol.lineNumber(for:) Tests

  @Test
  func `lineNumber returns 1 for start of string`() async throws {
    let text = """
    Line 1
    Line 2
    """

    let lineNum = text.lineNumber(for: text.startIndex)
    #expect(lineNum == 1)
  }

  @Test
  func `lineNumber calculates correct line for index`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    // Find index of "Line 2"
    let line2Range = try #require(text.range(of: "Line 2"))
    let lineNum = text.lineNumber(for: line2Range.lowerBound)
    #expect(lineNum == 2)
  }

  @Test
  func `lineNumber handles multiple newlines`() async throws {
    let text = """
    Line 1

    Line 3
    """

    // Find index of "Line 3"
    let line3Range = try #require(text.range(of: "Line 3"))
    let lineNum = text.lineNumber(for: line3Range.lowerBound)
    #expect(lineNum == 3)
  }

  @Test
  func `lineNumber works on substrings`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let substring = try #require(text.substring(lines: 2...3))
    let lineNum = substring.lineNumber(for: substring.startIndex)
    #expect(lineNum == 1) // Line number relative to substring
  }

  // MARK: - Substring.lineRange Tests

  @Test
  func `lineRange returns correct range for single line substring`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let substring = try #require(text.substring(lines: 2...2))
    #expect(substring.lineRange == 2...2)
  }

  @Test
  func `lineRange returns correct range for multi-line substring`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    Line 4
    """

    let substring = try #require(text.substring(lines: 2...4))
    #expect(substring.lineRange == 2...4)
  }

  @Test
  func `lineRange returns correct starting line number`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let substring = try #require(text.substring(lines: 2...3))
    #expect(substring.startingLineNumber == 2)
  }

  @Test
  func `lineRange returns correct ending line number`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let substring = try #require(text.substring(lines: 2...3))
    #expect(substring.endingLineNumber == 3)
  }

  @Test
  func `lineRange handles first line`() async throws {
    let text = """
    Line 1
    Line 2
    """

    let substring = try #require(text.substring(lines: 1...1))
    #expect(substring.lineRange == 1...1)
    #expect(substring.startingLineNumber == 1)
    #expect(substring.endingLineNumber == 1)
  }

  @Test
  func `lineRange handles last line`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let substring = try #require(text.substring(lines: 3...3))
    #expect(substring.lineRange == 3...3)
    #expect(substring.startingLineNumber == 3)
    #expect(substring.endingLineNumber == 3)
  }

  @Test
  func `lineRange handles substring spanning entire document`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    """

    let substring = try #require(text.substring(lines: 1...3))
    #expect(substring.lineRange == 1...3)
    #expect(substring.startingLineNumber == 1)
    #expect(substring.endingLineNumber == 3)
  }

  // MARK: - Integration Tests

  @Test
  func `extract and analyze line numbers from markdown document`() async throws {
    let markdown = """
    ---
    title: Test Document
    ---

    # Heading 1

    Some content here.

    ## Heading 2

    More content.
    """

    // Extract frontmatter
    let frontmatter = try #require(markdown.substring(lines: 1...3))
    #expect(frontmatter.startingLineNumber == 1)
    #expect(frontmatter.endingLineNumber == 3)
    #expect(String(frontmatter).contains("title: Test Document"))

    // Extract heading section
    let heading = try #require(markdown.substring(lines: 5...7))
    #expect(heading.startingLineNumber == 5)
    #expect(heading.endingLineNumber == 7)
    #expect(String(heading).contains("# Heading 1"))
  }

  @Test
  func `consecutive line extractions maintain correct line numbers`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    Line 4
    Line 5
    """

    let part1 = try #require(text.substring(lines: 1...2))
    #expect(part1.startingLineNumber == 1)
    #expect(part1.endingLineNumber == 2)

    let part2 = try #require(text.substring(lines: 3...5))
    #expect(part2.startingLineNumber == 3)
    #expect(part2.endingLineNumber == 5)
  }

  @Test
  func `nested substring extraction`() async throws {
    let text = """
    Line 1
    Line 2
    Line 3
    Line 4
    Line 5
    """

    // Extract lines 2-4
    let outer = try #require(text.substring(lines: 2...4))
    #expect(outer.startingLineNumber == 2)
    #expect(outer.endingLineNumber == 4)

    // The outer substring still references the original base string
    // So we can verify it knows its position in the original
    #expect(String(outer) == "Line 2\nLine 3\nLine 4")
  }
}
