//
//  FrontMatterParser.swift
//  MarkdownUtilities
//

import Foundation
import Parsing

/// Parser for separating frontmatter from markdown body content.
///
/// This parser detects YAML (`---`) or TOML (`+++`) frontmatter and separates it
/// from the body content without parsing the structured data itself.
struct FrontMatterParser: Parsing.Parser {
  typealias Input = Substring
  typealias Output = (rawFrontMatter: String, body: String, format: FrontMatterFormat?)
  /// Parses input into structured Markdown data.
  ///
  /// See <doc:FrontmatterWorkflows> for workflow details.
  func parse(_ input: inout Substring) throws -> Output {
    let originalSource = String(input)
    guard let format = FrontMatterFormat.allCases.first(where: {
      originalSource.hasPrefix("\($0.delimiter)\n")
    }) else {
      input = ""
      return ("", originalSource, nil)
    }
    let bytes = Array(originalSource.utf8)
    let delimiter = Array(format.delimiter.utf8)
    let contentStart = delimiter.count + 1
    let closingStart = stride(from: contentStart, to: bytes.count, by: 1).first { index in
      let startsLine = index == contentStart || bytes[index - 1] == 0x0A
      return startsLine
        && index + delimiter.count <= bytes.count
        && bytes[index..<(index + delimiter.count)].elementsEqual(delimiter)
    }
    guard let closingStart else {
      input = ""
      return ("", originalSource, nil)
    }

    let rawEnd = closingStart > contentStart && bytes[closingStart - 1] == 0x0A
      ? closingStart - 1
      : closingStart
    let rawFrontMatter = String(decoding: bytes[contentStart..<rawEnd], as: UTF8.self)
    var bodyStart = closingStart + delimiter.count
    if bodyStart + 1 < bytes.count, bytes[bodyStart] == 0x0D, bytes[bodyStart + 1] == 0x0A {
      bodyStart += 2
    } else if bodyStart < bytes.count, bytes[bodyStart] == 0x0A {
      bodyStart += 1
    }
    let body = String(decoding: bytes[bodyStart...], as: UTF8.self)
    input = ""
    return (rawFrontMatter, body, format)
  }
}
