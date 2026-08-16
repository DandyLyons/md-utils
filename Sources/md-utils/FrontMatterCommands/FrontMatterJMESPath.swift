//
//  FrontMatterJMESPath.swift
//  md-utils
//

import Foundation
import JMESPath
import MarkdownUtilitiesCore

/// Shared JMESPath support for frontmatter commands.
enum FrontMatterJMESPath {
  /// Compiles a JMESPath expression.
  static func compile(_ expression: String) throws -> JMESExpression {
    try JMESExpression.compile(expression)
  }

  /// Converts parsed frontmatter into the Foundation representation expected by JMESPath.
  static func object(from document: MarkdownDocument) throws -> Any {
    guard document.frontMatterFormat != .toml else {
      throw FrontMatterCommandError(message: "TOML frontmatter is not supported by fm search")
    }
    return FrontMatterConversion.foundationValue(document.frontMatter)
  }

  /// Extracts the useful description from the JMESPath package's wrapped errors.
  static func message(for error: Error) -> String {
    let description = String(describing: error)
    let patterns = [
      #"compileTime\("([^"]+)"\)"#,
      #"runtime\("([^"]+)"\)"#,
    ]

    for pattern in patterns {
      guard let match = description.range(of: pattern, options: .regularExpression),
        let capture = description.range(
          of: #""([^"]+)""#,
          options: .regularExpression,
          range: match
        )
      else {
        continue
      }
      return String(description[capture].dropFirst().dropLast())
    }

    return error.localizedDescription
  }
}
