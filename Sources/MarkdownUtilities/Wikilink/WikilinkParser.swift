//
//  WikilinkParser.swift
//  MarkdownUtilities
//

import Parsing

/// Errors thrown when wikilink parsing fails.
enum WikilinkParserError: Error {
  case expectedOpenBrackets
  case expectedCloseBrackets
  case emptyContent
  case invalidContent
}

/// Parser for Obsidian-flavored wikilinks.
///
/// Parses wikilinks of the form `[[target]]`, `[[target|display]]`, `![[embed]]`,
/// `[[page#heading]]`, `[[page#^blockID]]`, and combinations thereof.
///
/// Conforms to `Parsing.Parser` with `Input = Substring` and `Output = Wikilink`.
struct WikilinkParser: Parsing.Parser {
  typealias Input = Substring
  typealias Output = Wikilink

  func parse(_ input: inout Substring) throws -> Wikilink {
    let original = input

    // 1. Detect optional `!` embed prefix
    let isEmbed: Bool
    if input.first == "!" {
      // Peek ahead to check for `[[`
      let afterBang = input.dropFirst()
      if afterBang.starts(with: "[[") {
        isEmbed = true
        input.removeFirst() // consume `!`
      } else {
        isEmbed = false
      }
    } else {
      isEmbed = false
    }

    // 2. Consume `[[`
    guard input.starts(with: "[[") else {
      input = original
      throw WikilinkParserError.expectedOpenBrackets
    }
    input.removeFirst(2)

    // 3. Capture everything up to `]]`
    let interior: Substring
    do {
      interior = try PrefixUpTo("]]").parse(&input)
    } catch {
      input = original
      throw WikilinkParserError.expectedCloseBrackets
    }

    // 4. Consume `]]`
    guard input.starts(with: "]]") else {
      input = original
      throw WikilinkParserError.expectedCloseBrackets
    }
    input.removeFirst(2)

    // Guard against empty interior
    guard !interior.isEmpty else {
      input = original
      throw WikilinkParserError.emptyContent
    }

    // Reject interior containing `[[` (nested/malformed brackets)
    guard !interior.contains("[[") else {
      input = original
      throw WikilinkParserError.invalidContent
    }

    // 5. Compute rawValue from what we consumed
    let consumed = original[..<input.startIndex]
    let rawValue = String(consumed)

    // 6. Process interior: split on unescaped pipe
    let (targetPart, displayText) = splitOnUnescapedPipe(String(interior))

    // 7. Extract anchor from target part
    let (target, anchor) = extractAnchor(from: targetPart)

    return Wikilink(
      rawValue: rawValue,
      target: target,
      displayText: displayText,
      anchor: anchor,
      isEmbed: isEmbed
    )
  }

  /// Splits a string on the first unescaped `|` character.
  ///
  /// A `|` preceded by `\` is treated as an escaped literal pipe and is not
  /// used as a separator. Escape sequences (`\|`) in the target portion are
  /// resolved to literal `|`.
  ///
  /// - Returns: A tuple of (target, displayText?) where displayText is nil
  ///   if no unescaped pipe was found.
  private func splitOnUnescapedPipe(_ interior: String) -> (String, String?) {
    var index = interior.startIndex

    while index < interior.endIndex {
      let char = interior[index]
      if char == "\\" {
        // Skip the next character (it's escaped)
        let next = interior.index(after: index)
        if next < interior.endIndex {
          index = interior.index(after: next)
        } else {
          index = interior.endIndex
        }
      } else if char == "|" {
        // Found unescaped pipe — split here
        let targetRaw = String(interior[interior.startIndex..<index])
        let displayStart = interior.index(after: index)
        let displayText = String(interior[displayStart...])
        let target = resolveEscapedPipes(targetRaw)
        return (target, displayText)
      } else {
        index = interior.index(after: index)
      }
    }

    // No unescaped pipe found
    let target = resolveEscapedPipes(interior)
    return (target, nil)
  }

  /// Replaces `\|` escape sequences with literal `|`.
  private func resolveEscapedPipes(_ text: String) -> String {
    text.replacingOccurrences(of: "\\|", with: "|")
  }

  /// Extracts an anchor from a target string.
  ///
  /// Splits on the first `#` to determine anchor type:
  /// - `#^id` produces `.blockID("id")`
  /// - `#heading` produces `.heading("heading")`
  /// - No `#` produces `nil`
  ///
  /// - Returns: A tuple of (target without anchor, optional anchor).
  private func extractAnchor(from target: String) -> (String, WikilinkAnchor?) {
    guard let hashIndex = target.firstIndex(of: "#") else {
      return (target, nil)
    }

    let pagePart = String(target[target.startIndex..<hashIndex])
    let afterHash = target[target.index(after: hashIndex)...]

    if afterHash.starts(with: "^") {
      let blockID = String(afterHash.dropFirst())
      return (pagePart, .blockID(blockID))
    } else {
      let heading = String(afterHash)
      return (pagePart, .heading(heading))
    }
  }
}
