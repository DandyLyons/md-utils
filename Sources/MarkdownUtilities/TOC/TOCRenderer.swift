//
//  TOCRenderer.swift
//  MarkdownUtilities
//

import Foundation

/// Renders table of contents to various output formats.
public enum TOCRenderer {

  /// Output format for rendering.
  public enum Format: Equatable, Sendable {
    /// Markdown unordered list with links (- [text](#slug)).
    case mdBulletLinks

    /// Markdown headings only (## heading).
    case mdOnlyHeadings

    /// Tree structure with box-drawing characters.
    case tree

    /// Compact JSON.
    case json

    /// Pretty-printed JSON.
    case jsonPretty

    /// Plain indented text.
    case plain

    /// HTML unordered list.
    case html
  }

  /// Render a table of contents to the specified format.
  ///
  /// - Parameters:
  ///   - toc: The table of contents to render
  ///   - format: The output format
  /// - Returns: Rendered string
  public static func render(_ toc: TableOfContents, as format: Format) -> String {
    switch format {
    case .mdBulletLinks:
      return renderMdBulletLinks(toc)
    case .mdOnlyHeadings:
      return renderMdOnlyHeadings(toc)
    case .tree:
      return renderTree(toc)
    case .json:
      return renderJSON(toc, pretty: false)
    case .jsonPretty:
      return renderJSON(toc, pretty: true)
    case .plain:
      return renderPlainTextIndented(toc)
    case .html:
      return renderHTML(toc)
    }
  }

  // MARK: - Markdown Bullet Links Rendering

  static func renderMdBulletLinks(_ toc: TableOfContents) -> String {
    var lines: [String] = []

    func renderEntry(_ entry: TOCEntry, depth: Int) {
      let indent = String(repeating: "  ", count: depth)
      let text: String
      if let slug = entry.slug {
        text = "[\(entry.text)](#\(slug))"
      } else {
        text = entry.text
      }

      lines.append("\(indent)- \(text)")

      for child in entry.children {
        renderEntry(child, depth: depth + 1)
      }
    }

    for entry in toc.entries {
      renderEntry(entry, depth: 0)
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Markdown Only Headings Rendering

  static func renderMdOnlyHeadings(_ toc: TableOfContents) -> String {
    var lines: [String] = []

    func renderEntry(_ entry: TOCEntry) {
      let marker = String(repeating: "#", count: entry.level)
      lines.append("\(marker) \(entry.text)")

      for child in entry.children {
        renderEntry(child)
      }
    }

    for entry in toc.entries {
      renderEntry(entry)
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Tree Rendering

  static func renderTree(_ toc: TableOfContents) -> String {
    var lines: [String] = []

    func renderEntry(_ entry: TOCEntry, prefix: String, isLast: Bool) {
      let connector = isLast ? "└── " : "├── "
      lines.append("\(prefix)\(connector)\(entry.text)")

      let childPrefix = prefix + (isLast ? "    " : "│   ")
      for (index, child) in entry.children.enumerated() {
        let isLastChild = index == entry.children.count - 1
        renderEntry(child, prefix: childPrefix, isLast: isLastChild)
      }
    }

    for (index, entry) in toc.entries.enumerated() {
      let isLast = index == toc.entries.count - 1
      renderEntry(entry, prefix: "", isLast: isLast)
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Plain Text Rendering

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
