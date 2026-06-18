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

  /// Styles human-readable group headings.
  static func heading(_ text: String) -> String {
    text.bold
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
