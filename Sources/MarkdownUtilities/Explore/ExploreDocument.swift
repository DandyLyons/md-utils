//
//  ExploreDocument.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// A source-preserving model for progressively exploring a Markdown document.
public struct ExploreDocument: Sendable {
  /// Original Markdown source lines split on newline boundaries.
  public let sourceLines: [String]

  /// Optional YAML frontmatter block from the original source.
  public let frontmatter: ExploreFrontmatter?

  /// Optional document preamble before the first heading.
  public let preamble: ExplorePreamble?

  /// Top-level section tree nodes.
  public let sections: [ExploreSection]

  /// Creates an explore document model.
  public init(
    sourceLines: [String],
    frontmatter: ExploreFrontmatter?,
    preamble: ExplorePreamble?,
    sections: [ExploreSection]
  ) {
    self.sourceLines = sourceLines
    self.frontmatter = frontmatter
    self.preamble = preamble
    self.sections = sections
  }

  /// The shallowest heading level present in the document body.
  public var topHeadingLevel: Int? {
    allSections.map(\.level).min()
  }

  /// All section nodes in source order.
  public var allSections: [ExploreSection] {
    sections.flatMap { [$0] + $0.descendants }
  }

  /// Returns source text for a 1-based inclusive line range.
  public func sourceText(in range: ClosedRange<Int>) -> String {
    guard range.lowerBound >= 1, range.upperBound <= sourceLines.count else {
      return ""
    }

    let startIndex = range.lowerBound - 1
    let endIndex = range.upperBound - 1
    return sourceLines[startIndex...endIndex].joined(separator: "\n")
  }

  /// Builds an explore document from original Markdown source.
  public static func build(from source: String) async throws -> ExploreDocument {
    let sourceLines = source.components(separatedBy: "\n")
    let frontmatter = try detectFrontmatter(in: sourceLines)
    let bodyStartIndex = frontmatter?.lineRange.upperBound ?? 0
    let bodyStartLine = bodyStartIndex + 1
    let bodyLines = bodyStartIndex < sourceLines.count ? Array(sourceLines[bodyStartIndex...]) : []
    let body = bodyLines.joined(separator: "\n")

    let markdown = try await Markdown(text: body)
    let root = await markdown.parse()
    let headings = root.children.compactMap { $0 as? Heading }
    let sections = buildSections(from: headings, sourceLines: sourceLines, bodyStartLine: bodyStartLine)
    let preamble = detectPreamble(
      sourceLines: sourceLines,
      bodyStartLine: bodyStartLine,
      firstHeadingLine: sections.first?.headingLine
    )

    return ExploreDocument(
      sourceLines: sourceLines,
      frontmatter: frontmatter,
      preamble: preamble,
      sections: sections
    )
  }

  private static func detectFrontmatter(in sourceLines: [String]) throws -> ExploreFrontmatter? {
    guard sourceLines.first == "---" else {
      return nil
    }

    for index in 1..<sourceLines.count where sourceLines[index] == "---" {
      let rawYAML = sourceLines[1..<index].joined(separator: "\n")
      let mapping = try YAMLConversion.parse(rawYAML)
      return ExploreFrontmatter(
        lineRange: 1...(index + 1),
        fieldCount: mapping.count
      )
    }

    return nil
  }

  private static func detectPreamble(
    sourceLines: [String],
    bodyStartLine: Int,
    firstHeadingLine: Int?
  ) -> ExplorePreamble? {
    let endLine = (firstHeadingLine ?? (sourceLines.count + 1)) - 1
    guard bodyStartLine <= endLine else {
      return nil
    }

    let range = bodyStartLine...endLine
    let text = sourceLines[(range.lowerBound - 1)...(range.upperBound - 1)].joined(separator: "\n")
    guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
      return nil
    }

    return ExplorePreamble(
      lineRange: range,
      wordCount: countWords(in: text),
      lineCount: range.count
    )
  }

  private static func buildSections(
    from headings: [Heading],
    sourceLines: [String],
    bodyStartLine: Int
  ) -> [ExploreSection] {
    guard headings.isEmpty == false else {
      return []
    }

    var workingSections: [WorkingSection] = headings.enumerated().map { index, heading in
      let headingLine = bodyStartLine + heading.position.start.line - 1
      let title = HeadingTextExtractor.extractText(from: heading)
      let headingMarkdown = line(at: headingLine, in: sourceLines)

      return WorkingSection(
        id: index,
        level: heading.depth.rawValue,
        title: title,
        headingLine: headingLine,
        headingMarkdown: headingMarkdown,
        fullLineRange: headingLine...headingLine,
        bodyLineRange: nil,
        path: [title],
        childIndices: []
      )
    }

    for index in workingSections.indices {
      let level = workingSections[index].level
      let endLine: Int
      if let nextBoundary = workingSections[(index + 1)...].first(where: { $0.level <= level }) {
        endLine = nextBoundary.headingLine - 1
      } else {
        endLine = sourceLines.count
      }

      let firstDescendantLine = workingSections[(index + 1)...]
        .first(where: { $0.headingLine <= endLine && $0.level > level })?
        .headingLine
      let bodyStart = workingSections[index].headingLine + 1
      let bodyEnd = (firstDescendantLine ?? (endLine + 1)) - 1

      workingSections[index].fullLineRange = workingSections[index].headingLine...endLine
      if bodyStart <= bodyEnd {
        workingSections[index].bodyLineRange = bodyStart...bodyEnd
      }
    }

    var rootIndices: [Int] = []
    var stack: [Int] = []

    for index in workingSections.indices {
      while let lastIndex = stack.last, workingSections[lastIndex].level >= workingSections[index].level {
        stack.removeLast()
      }

      if let parentIndex = stack.last {
        workingSections[parentIndex].childIndices.append(index)
        workingSections[index].path = workingSections[parentIndex].path + [workingSections[index].title]
      } else {
        rootIndices.append(index)
      }

      stack.append(index)
    }

    func makeSection(index: Int) -> ExploreSection {
      let working = workingSections[index]
      let children = working.childIndices.map { makeSection(index: $0) }
      let fullText = sourceLines[(working.fullLineRange.lowerBound - 1)...(working.fullLineRange.upperBound - 1)]
        .joined(separator: "\n")

      return ExploreSection(
        id: working.id,
        level: working.level,
        title: working.title,
        headingLine: working.headingLine,
        headingMarkdown: working.headingMarkdown,
        fullLineRange: working.fullLineRange,
        bodyLineRange: working.bodyLineRange,
        path: working.path,
        wordCount: countWords(in: fullText),
        lineCount: working.fullLineRange.count,
        children: children
      )
    }

    return rootIndices.map { makeSection(index: $0) }
  }

  private static func line(at lineNumber: Int, in sourceLines: [String]) -> String {
    guard lineNumber >= 1, lineNumber <= sourceLines.count else {
      return ""
    }

    return sourceLines[lineNumber - 1]
  }

  private static func countWords(in text: String) -> Int {
    text.split { character in
      character.isWhitespace || character.isPunctuation
    }.count
  }
}

/// Source details for a frontmatter block.
public struct ExploreFrontmatter: Equatable, Sendable {
  /// 1-based inclusive line range of the original frontmatter block.
  public let lineRange: ClosedRange<Int>

  /// Number of top-level YAML fields.
  public let fieldCount: Int

  public init(lineRange: ClosedRange<Int>, fieldCount: Int) {
    self.lineRange = lineRange
    self.fieldCount = fieldCount
  }
}

/// Source details for content before the first heading.
public struct ExplorePreamble: Equatable, Sendable {
  /// 1-based inclusive line range of the preamble.
  public let lineRange: ClosedRange<Int>

  /// Word count in the preamble.
  public let wordCount: Int

  /// Line count in the preamble.
  public let lineCount: Int

  public init(lineRange: ClosedRange<Int>, wordCount: Int, lineCount: Int) {
    self.lineRange = lineRange
    self.wordCount = wordCount
    self.lineCount = lineCount
  }
}

/// A source-preserving Markdown heading section.
public struct ExploreSection: Equatable, Sendable, Identifiable {
  public let id: Int
  public let level: Int
  public let title: String
  public let headingLine: Int
  public let headingMarkdown: String
  public let fullLineRange: ClosedRange<Int>
  public let bodyLineRange: ClosedRange<Int>?
  public let path: [String]
  public let wordCount: Int
  public let lineCount: Int
  public let children: [ExploreSection]

  public init(
    id: Int,
    level: Int,
    title: String,
    headingLine: Int,
    headingMarkdown: String,
    fullLineRange: ClosedRange<Int>,
    bodyLineRange: ClosedRange<Int>?,
    path: [String],
    wordCount: Int,
    lineCount: Int,
    children: [ExploreSection]
  ) {
    self.id = id
    self.level = level
    self.title = title
    self.headingLine = headingLine
    self.headingMarkdown = headingMarkdown
    self.fullLineRange = fullLineRange
    self.bodyLineRange = bodyLineRange
    self.path = path
    self.wordCount = wordCount
    self.lineCount = lineCount
    self.children = children
  }

  /// Immediate child subsection count.
  public var childSectionCount: Int {
    children.count
  }

  /// Descendant sections in source order.
  public var descendants: [ExploreSection] {
    children.flatMap { [$0] + $0.descendants }
  }
}

private struct WorkingSection {
  let id: Int
  let level: Int
  let title: String
  let headingLine: Int
  let headingMarkdown: String
  var fullLineRange: ClosedRange<Int>
  var bodyLineRange: ClosedRange<Int>?
  var path: [String]
  var childIndices: [Int]
}
