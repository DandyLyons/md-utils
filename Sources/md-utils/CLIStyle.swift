//
//  CLIStyle.swift
//  md-utils
//

import Foundation
import Rainbow

/// Shared ANSI styling for human-facing CLI output.
enum CLIStyle {
  /// Styles metadata that should be visually distinct from user content.
  static func metadata(_ text: String) -> String {
    text.bit8(244)
  }

  /// Styles secondary text such as empty-state messages and counts.
  static func muted(_ text: String) -> String {
    text.bit8(244)
  }

  /// Styles unobtrusive guidance that should remain discoverable.
  static func hint(_ text: String) -> String {
    text.bit8(110)
  }

  /// Styles human-readable group headings.
  static func heading(_ text: String) -> String {
    text.bold
  }

  /// Styles schema describe section headings.
  static func schemaDescribeHeading(_ text: String) -> String {
    text.lightBlue.bold
  }

  /// Styles schema describe rule names.
  static func schemaDescribeRuleName(_ text: String) -> String {
    text.magenta.bold
  }

  /// Styles field names in schema descriptions.
  static func schemaDescribeFieldName(_ text: String) -> String {
    text.lightGreen.bold
  }

  /// Styles Markdown heading hash markers by heading depth.
  static func headingMarker(_ text: String, level: Int) -> String {
    switch level {
    case 1:
      return text.red
    case 2:
      return text.lightRed
    case 3:
      return text.yellow
    case 4:
      return text.green
    case 5:
      return text.blue
    default:
      return text.magenta
    }
  }

  /// Styles synthetic explore nodes such as frontmatter and preamble.
  static func exploreLabel(_ text: String) -> String {
    text.lightBlue
  }

  /// Styles frontmatter nodes in explore tree output.
  static func frontmatterLabel(_ text: String) -> String {
    text.magenta
  }

  /// Styles preamble nodes in explore tree output.
  static func preambleLabel(_ text: String) -> String {
    text.lightBlue
  }

  /// Styles only the leading hash marker of a Markdown heading line.
  static func markdownHeading(_ text: String, level: Int) -> String {
    let marker = String(repeating: "#", count: level)
    guard text.hasPrefix(marker) else {
      return text
    }

    let rest = text.dropFirst(marker.count)
    return headingMarker(marker, level: level) + rest
  }

  /// Styles filesystem paths in human-facing output.
  static func path(_ text: String) -> String {
    text.cyan
  }

  /// Styles success/status labels.
  static func success(_ text: String) -> String {
    text.green
  }

  /// Styles warning labels.
  static func warning(_ text: String) -> String {
    text.yellow
  }

  /// Styles error labels.
  static func error(_ text: String) -> String {
    text.red
  }

  /// Writes a human-facing line to stderr.
  static func writeStderr(_ text: String) {
    fputs("\(text)\n", stderr)
  }

  /// Writes a styled error line to stderr.
  static func writeError(_ message: String) {
    writeStderr("\(error("error")): \(message)")
  }

  /// Writes a styled warning line to stderr.
  static func writeWarning(_ message: String) {
    writeStderr("\(warning("warning")): \(message)")
  }
}
