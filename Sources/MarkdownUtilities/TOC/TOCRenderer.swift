//
//  TOCRenderer.swift
//  MarkdownUtilities
//

import Foundation

/// Renders table of contents to various output formats.
public enum TOCRenderer {

  /// Output format for rendering.
  public enum Format: Equatable, Sendable {
    /// Markdown format with specified style.
    case markdown(style: MarkdownStyle)

    /// Plain text format with specified style.
    case plainText(style: PlainTextStyle)

    /// JSON format.
    case json(pretty: Bool)

    /// HTML format.
    case html
  }

  /// Style options for Markdown rendering.
  public enum MarkdownStyle: Equatable, Sendable {
    /// Unordered list with links (default).
    case unorderedLinks

    /// Unordered list without links.
    case unorderedPlain

    /// Ordered list with links.
    case orderedLinks

    /// Ordered list without links.
    case orderedPlain
  }

  /// Style options for plain text rendering.
  public enum PlainTextStyle: Equatable, Sendable {
    /// Indented with spaces (2 spaces per level).
    case indented

    /// Flat list with level numbers.
    case flatWithLevels
  }

  /// Render a table of contents to the specified format.
  ///
  /// - Parameters:
  ///   - toc: The table of contents to render
  ///   - format: The output format
  /// - Returns: Rendered string
  public static func render(_ toc: TableOfContents, as format: Format) -> String {
    switch format {
    case .markdown(let style):
      return renderMarkdown(toc, style: style)
    case .plainText(let style):
      return renderPlainText(toc, style: style)
    case .json(let pretty):
      return renderJSON(toc, pretty: pretty)
    case .html:
      return renderHTML(toc)
    }
  }

  // MARK: - Markdown Rendering

  static func renderMarkdown(_ toc: TableOfContents, style: MarkdownStyle) -> String {
    let useLinks = style == .unorderedLinks || style == .orderedLinks
    let useOrdered = style == .orderedLinks || style == .orderedPlain

    var lines: [String] = []

    func renderEntry(_ entry: TOCEntry, depth: Int) {
      let indent = String(repeating: "  ", count: depth)
      let marker = useOrdered ? "1." : "-"

      let text: String
      if useLinks, let slug = entry.slug {
        text = "[\(entry.text)](#\(slug))"
      } else {
        text = entry.text
      }

      lines.append("\(indent)\(marker) \(text)")

      for child in entry.children {
        renderEntry(child, depth: depth + 1)
      }
    }

    for entry in toc.entries {
      renderEntry(entry, depth: 0)
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Plain Text Rendering

  static func renderPlainText(_ toc: TableOfContents, style: PlainTextStyle) -> String {
    switch style {
    case .indented:
      return renderPlainTextIndented(toc)
    case .flatWithLevels:
      return renderPlainTextFlat(toc)
    }
  }

  static func renderPlainTextIndented(_ toc: TableOfContents) -> String {
    var lines: [String] = []

    func renderEntry(_ entry: TOCEntry, depth: Int) {
      let indent = String(repeating: "  ", count: depth)
      lines.append("\(indent)\(entry.text)")

      for child in entry.children {
        renderEntry(child, depth: depth + 1)
      }
    }

    for entry in toc.entries {
      renderEntry(entry, depth: 0)
    }

    return lines.joined(separator: "\n")
  }

  static func renderPlainTextFlat(_ toc: TableOfContents) -> String {
    let flatEntries = toc.flatEntries
    let lines = flatEntries.map { entry in
      "[\(entry.level)] \(entry.text)"
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - JSON Rendering

  static func renderJSON(_ toc: TableOfContents, pretty: Bool) -> String {
    let encoder = JSONEncoder()
    if pretty {
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    let jsonData = TOCJSONRepresentation(from: toc)

    guard let data = try? encoder.encode(jsonData),
      let string = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }

    return string
  }

  // MARK: - HTML Rendering

  static func renderHTML(_ toc: TableOfContents) -> String {
    var html = "<ul>\n"

    func renderEntry(_ entry: TOCEntry, depth: Int) -> String {
      let indent = String(repeating: "  ", count: depth + 1)
      var result = ""

      result += "\(indent)<li>"

      if let slug = entry.slug {
        result += "<a href=\"#\(slug)\">\(escapeHTML(entry.text))</a>"
      } else {
        result += escapeHTML(entry.text)
      }

      if !entry.children.isEmpty {
        result += "\n\(indent)  <ul>\n"
        for child in entry.children {
          result += renderEntry(child, depth: depth + 2)
        }
        result += "\(indent)  </ul>\n\(indent)"
      }

      result += "</li>\n"
      return result
    }

    for entry in toc.entries {
      html += renderEntry(entry, depth: 0)
    }

    html += "</ul>"
    return html
  }

  static func escapeHTML(_ text: String) -> String {
    text
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}

// MARK: - JSON Representation

struct TOCJSONRepresentation: Codable {
  let entries: [EntryRepresentation]
  let minLevel: Int
  let maxLevel: Int

  init(from toc: TableOfContents) {
    self.entries = toc.entries.map { EntryRepresentation(from: $0) }
    self.minLevel = toc.minLevel
    self.maxLevel = toc.maxLevel
  }

  struct EntryRepresentation: Codable {
    let level: Int
    let text: String
    let slug: String?
    let children: [EntryRepresentation]

    init(from entry: TOCEntry) {
      self.level = entry.level
      self.text = entry.text
      self.slug = entry.slug
      self.children = entry.children.map { EntryRepresentation(from: $0) }
    }
  }
}
