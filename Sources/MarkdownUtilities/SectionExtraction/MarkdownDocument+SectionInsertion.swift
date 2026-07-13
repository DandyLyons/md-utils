//
//  MarkdownDocument+SectionInsertion.swift
//  MarkdownUtilities
//

import Foundation
import Yams

/// Adds section insertion and removal behavior to ``MarkdownDocument``.
extension MarkdownDocument {
  /// Placement for inserting a new section relative to an existing section.
  public enum SectionInsertionPlacement: Sendable {
    /// Insert before the matched section.
    case before(SectionExtractor.Options.MatchCriteria)

    /// Insert after the matched section.
    case after(SectionExtractor.Options.MatchCriteria)
  }

  /// Inserts a new, contained section relative to an existing section.
  ///
  /// The inserted content may be body-only or a complete section whose leading heading
  /// matches `name`. Heading levels are normalized so the inserted content remains one
  /// contained section at the inferred or explicitly requested destination level.
  public func insertSection(
    name: String,
    content rawContent: String,
    placement: SectionInsertionPlacement,
    level explicitLevel: Int? = nil,
    caseSensitive: Bool = false
  ) async throws -> MarkdownDocument {
    let root = try await parseAST()
    let options = SectionExtractor.Options(
      matchCriteria: placement.matchCriteria,
      removeFromOriginal: false
    )
    let result = try await SectionExtractor.extract(
      root: root,
      originalContent: body,
      options: options
    )

    let destinationLevel = explicitLevel ?? result.section.heading.depth.rawValue
    guard (1...6).contains(destinationLevel) else {
      throw SectionInsertionError.invalidHeadingLevel(destinationLevel)
    }

    let insertedSection = try normalizedInsertedSection(
      name: name,
      rawContent: rawContent,
      destinationLevel: destinationLevel,
      caseSensitive: caseSensitive
    )

    let insertedBody = insertSectionText(
      insertedSection,
      in: body,
      anchorRange: result.section.lineRange,
      placement: placement
    )

    return try rebuildDocumentAfterInsertion(withBody: insertedBody)
  }

  /// Removes a section and all of its descendant content.
  public func removeSection(at index: Int) async throws -> MarkdownDocument {
    let (_, updated) = try await extractSection(at: index, removeFromOriginal: true)
    guard let updatedDoc = updated else {
      return self
    }
    return updatedDoc
  }

  /// Removes a section and all of its descendant content by heading name.
  public func removeSection(
    byName name: String,
    caseSensitive: Bool = false
  ) async throws -> MarkdownDocument {
    let (_, updated) = try await extractSection(
      byName: name,
      caseSensitive: caseSensitive,
      removeFromOriginal: true
    )
    guard let updatedDoc = updated else {
      return self
    }
    return updatedDoc
  }

  private func normalizedInsertedSection(
    name: String,
    rawContent: String,
    destinationLevel: Int,
    caseSensitive: Bool
  ) throws -> String {
    let content = rawContent.trimmingCharacters(in: .newlines)
    var lines = content.components(separatedBy: .newlines)

    while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
      lines.removeFirst()
    }

    if let first = lines.first, let heading = parseMarkdownHeading(first) {
      guard headingsMatch(heading.title, name, caseSensitive: caseSensitive) else {
        throw SectionInsertionError.mismatchedInputHeading(actual: heading.title, expected: name)
      }

      let delta = destinationLevel - heading.level
      return try shiftHeadings(in: lines, by: delta).joined(separator: "\n")
    }

    let headingLine = String(repeating: "#", count: destinationLevel) + " " + name
    let bodyLines = try normalizeBodyHeadingLevels(lines, below: destinationLevel)
    guard !bodyLines.isEmpty else {
      return headingLine
    }
    return ([headingLine, ""] + bodyLines).joined(separator: "\n")
  }

  private func normalizeBodyHeadingLevels(_ lines: [String], below destinationLevel: Int) throws -> [String] {
    let headingLevels = lines.compactMap { parseMarkdownHeading($0)?.level }
    guard let minimumHeadingLevel = headingLevels.min(), minimumHeadingLevel <= destinationLevel else {
      return lines
    }

    let delta = destinationLevel + 1 - minimumHeadingLevel
    return try shiftHeadings(in: lines, by: delta)
  }

  private func shiftHeadings(in lines: [String], by delta: Int) throws -> [String] {
    guard delta != 0 else {
      return lines
    }

    return try lines.map { line in
      guard let heading = parseMarkdownHeading(line) else {
        return line
      }

      let shiftedLevel = heading.level + delta
      guard (1...6).contains(shiftedLevel) else {
        throw SectionInsertionError.headingShiftOutOfRange(
          title: heading.title,
          requestedLevel: shiftedLevel
        )
      }

      return String(repeating: "#", count: shiftedLevel) + " " + heading.title
    }
  }

  private func insertSectionText(
    _ insertedSection: String,
    in content: String,
    anchorRange: ClosedRange<Int>,
    placement: SectionInsertionPlacement
  ) -> String {
    var lines = content.components(separatedBy: .newlines)
    let insertionIndex: Int
    switch placement {
    case .before:
      insertionIndex = anchorRange.lowerBound - 1
    case .after:
      insertionIndex = anchorRange.upperBound
    }

    let block = insertionBlockLines(insertedSection)
    lines.insert(contentsOf: block, at: insertionIndex)
    return lines.joined(separator: "\n")
  }

  private func insertionBlockLines(_ insertedSection: String) -> [String] {
    var block = insertedSection.components(separatedBy: .newlines)
    while let first = block.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
      block.removeFirst()
    }
    while let last = block.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
      block.removeLast()
    }
    return [""] + block + [""]
  }

  private func parseMarkdownHeading(_ line: String) -> (level: Int, title: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    var level = 0
    for character in trimmed {
      if character == "#" {
        level += 1
      } else {
        break
      }
    }

    guard (1...6).contains(level) else {
      return nil
    }

    let remainderStart = trimmed.index(trimmed.startIndex, offsetBy: level)
    let remainder = trimmed[remainderStart...]
    guard remainder.first?.isWhitespace == true else {
      return nil
    }

    var title = remainder.trimmingCharacters(in: .whitespaces)
    while title.hasSuffix("#") {
      title = String(title.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    guard !title.isEmpty else {
      return nil
    }
    return (level: level, title: title)
  }

  private func headingsMatch(_ lhs: String, _ rhs: String, caseSensitive: Bool) -> Bool {
    if caseSensitive {
      return lhs == rhs
    }
    return lhs.lowercased() == rhs.lowercased()
  }

  private func rebuildDocumentAfterInsertion(withBody newBody: String) throws -> MarkdownDocument {
    guard !frontMatter.isEmpty else {
      return try MarkdownDocument(content: newBody)
    }

    let yamlContent = try YAMLConversion.serialize(frontMatter)
    let fullContent = """
      ---
      \(yamlContent)---
      \(newBody)
      """
    return try MarkdownDocument(content: fullContent)
  }
}

private extension MarkdownDocument.SectionInsertionPlacement {
  var matchCriteria: SectionExtractor.Options.MatchCriteria {
    switch self {
    case .before(let criteria), .after(let criteria):
      return criteria
    }
  }
}
