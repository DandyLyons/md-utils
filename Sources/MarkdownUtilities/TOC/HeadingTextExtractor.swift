//
//  HeadingTextExtractor.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Extracts plain text from heading AST nodes and generates URL-safe slugs.
public enum HeadingTextExtractor {

  /// Extracts plain text content from a heading.
  ///
  /// Recursively traverses the heading's phrasing content children to extract
  /// all text, ignoring formatting and structural elements.
  ///
  /// - Parameter heading: The heading node to extract text from
  /// - Returns: The extracted plain text
  public static func extractText(from heading: Heading) -> String {
    extractText(from: heading.children)
  }

  /// Extracts plain text from an array of phrasing content.
  ///
  /// - Parameter content: Array of phrasing content nodes
  /// - Returns: The concatenated plain text
  static func extractText(from content: [PhrasingContent]) -> String {
    content.map { extractText(from: $0) }.joined()
  }

  /// Extracts plain text from a single phrasing content node.
  ///
  /// - Parameter content: A phrasing content node
  /// - Returns: The extracted plain text
  static func extractText(from content: PhrasingContent) -> String {
    switch content {
    // Literal types - return the value directly
    case let text as Text:
      return text.value
    case let code as InlineCode:
      return code.value
    case let html as HTML:
      return html.value

    // Parent types - recurse into children
    case let strong as Strong:
      return extractText(from: strong.children)
    case let emphasis as Emphasis:
      return extractText(from: emphasis.children)
    case let delete as Delete:
      return extractText(from: delete.children)

    // Link - extract text from children (not URL)
    case let link as Link:
      return extractText(from: link.children.map { $0 as PhrasingContent })

    // Break types - ignore
    case is Break, is SoftBreak:
      return ""

    // Image - ignore (can't extract meaningful text)
    case is Image:
      return ""

    // Unknown types - ignore
    default:
      return ""
    }
  }

  /// Generates a URL-safe slug from text using GitHub-style rules.
  ///
  /// Rules:
  /// 1. Convert to lowercase
  /// 2. Replace spaces with hyphens
  /// 3. Remove all characters except alphanumerics, hyphens, and underscores
  /// 4. Handle duplicates with numeric suffixes
  ///
  /// - Parameters:
  ///   - text: The text to convert to a slug
  ///   - existingSlugs: Set of already-used slugs to avoid duplicates
  /// - Returns: A unique URL-safe slug
  public static func generateSlug(
    from text: String,
    existingSlugs: Set<String> = []
  ) -> String {
    // Step 1: Convert to lowercase
    var slug = text.lowercased()

    // Step 2: Replace spaces with hyphens
    slug = slug.replacingOccurrences(of: " ", with: "-")

    // Step 3: Remove all characters except alphanumerics, hyphens, and underscores
    slug = slug.filter { char in
      char.isLetter || char.isNumber || char == "-" || char == "_"
    }

    // Remove leading/trailing hyphens
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    // If slug is empty after processing, use a default
    if slug.isEmpty {
      slug = "section"
    }

    // Step 4: Handle duplicates with numeric suffixes
    var uniqueSlug = slug
    var counter = 1
    while existingSlugs.contains(uniqueSlug) {
      uniqueSlug = "\(slug)-\(counter)"
      counter += 1
    }

    return uniqueSlug
  }
}
