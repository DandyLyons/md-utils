//
//  MarkdownDocument.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// A representation of a Markdown document.
public struct MarkdownDocument {
  /// The raw markdown content.
  public var content: String

  /// The root initializer for a markdown document.
  ///
  /// This is a minimal implementation. Future versions will include
  /// parsed AST, metadata extraction, and manipulation methods.
  public init(content: String) {
    self.content = content
  }
}
