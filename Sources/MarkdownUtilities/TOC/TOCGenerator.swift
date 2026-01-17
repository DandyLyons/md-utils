//
//  TOCGenerator.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownSyntax

/// Generates table of contents from Markdown AST.
public enum TOCGenerator {

  /// Options for TOC generation.
  public struct Options: Equatable, Sendable {
    /// Minimum heading level to include (1-6).
    public var minLevel: Int

    /// Maximum heading level to include (1-6).
    public var maxLevel: Int

    /// Whether to generate URL-safe slugs for entries.
    public var generateSlugs: Bool

    /// Whether to include source positions in entries.
    public var includePositions: Bool

    /// Whether to build hierarchical structure or flat list.
    public var hierarchical: Bool

    /// Create TOC generation options.
    ///
    /// - Parameters:
    ///   - minLevel: Minimum heading level (default: 1)
    ///   - maxLevel: Maximum heading level (default: 6)
    ///   - generateSlugs: Generate slugs (default: true)
    ///   - includePositions: Include positions (default: false)
    ///   - hierarchical: Build hierarchy (default: true)
    public init(
      minLevel: Int = 1,
      maxLevel: Int = 6,
      generateSlugs: Bool = true,
      includePositions: Bool = false,
      hierarchical: Bool = true
    ) {
      self.minLevel = minLevel
      self.maxLevel = maxLevel
      self.generateSlugs = generateSlugs
      self.includePositions = includePositions
      self.hierarchical = hierarchical
    }
  }

  /// Generate a table of contents from a Markdown AST root.
  ///
  /// Extracts all headings from the document and builds either a hierarchical
  /// or flat TOC structure based on options.
  ///
  /// - Parameters:
  ///   - root: The root of the Markdown AST
  ///   - options: Generation options (default: all defaults)
  /// - Returns: A TableOfContents structure
  /// - Throws: If the options are invalid (e.g., minLevel > maxLevel)
  public static func generate(
    from root: Root,
    options: Options = Options()
  ) throws -> TableOfContents {
    // Validate options
    guard options.minLevel >= 1 && options.minLevel <= 6 else {
      throw TOCGeneratorError.invalidLevelRange(
        "minLevel must be between 1 and 6, got \(options.minLevel)"
      )
    }
    guard options.maxLevel >= 1 && options.maxLevel <= 6 else {
      throw TOCGeneratorError.invalidLevelRange(
        "maxLevel must be between 1 and 6, got \(options.maxLevel)"
      )
    }
    guard options.minLevel <= options.maxLevel else {
      throw TOCGeneratorError.invalidLevelRange(
        "minLevel (\(options.minLevel)) must be <= maxLevel (\(options.maxLevel))"
      )
    }

    // Extract all headings from the AST
    let headings = extractHeadings(from: root.children)

    // Filter by level range
    let filteredHeadings = headings.filter { heading in
      let level = heading.depth.rawValue
      return level >= options.minLevel && level <= options.maxLevel
    }

    // If no headings, return empty TOC
    if filteredHeadings.isEmpty {
      return TableOfContents(
        entries: [],
        minLevel: options.minLevel,
        maxLevel: options.maxLevel
      )
    }

    // Generate slugs if requested
    var slugs: Set<String> = []
    let entries = filteredHeadings.map { heading -> TOCEntry in
      let level = heading.depth.rawValue
      let text = HeadingTextExtractor.extractText(from: heading)

      let slug: String?
      if options.generateSlugs {
        let generatedSlug = HeadingTextExtractor.generateSlug(
          from: text,
          existingSlugs: slugs
        )
        slugs.insert(generatedSlug)
        slug = generatedSlug
      } else {
        slug = nil
      }

      let position = options.includePositions ? heading.position : nil

      return TOCEntry(
        level: level,
        text: text,
        slug: slug,
        position: position,
        children: []
      )
    }

    // Build hierarchical or flat structure
    let finalEntries: [TOCEntry]
    if options.hierarchical {
      finalEntries = buildHierarchy(entries)
    } else {
      finalEntries = entries
    }

    // Calculate actual min/max levels
    let actualMinLevel = entries.map { $0.level }.min() ?? options.minLevel
    let actualMaxLevel = entries.map { $0.level }.max() ?? options.maxLevel

    return TableOfContents(
      entries: finalEntries,
      minLevel: actualMinLevel,
      maxLevel: actualMaxLevel
    )
  }

  /// Extract all heading nodes from content.
  ///
  /// - Parameter content: Array of content nodes
  /// - Returns: Array of heading nodes
  static func extractHeadings(from content: [Content]) -> [Heading] {
    var headings: [Heading] = []

    for node in content {
      if let heading = node as? Heading {
        headings.append(heading)
      }
      // Handle nested structures (lists, blockquotes, etc.)
      // For now, we only extract top-level headings
    }

    return headings
  }

  /// Build hierarchical structure from flat list of entries.
  ///
  /// Uses a stack-based algorithm to nest entries based on their levels.
  ///
  /// - Parameter flatEntries: Flat array of entries in document order
  /// - Returns: Hierarchical array of entries
  static func buildHierarchy(_ flatEntries: [TOCEntry]) -> [TOCEntry] {
    if flatEntries.isEmpty {
      return []
    }

    var result: [TOCEntry] = []
    var stack: [(entry: TOCEntry, level: Int)] = []

    for entry in flatEntries {
      // Pop stack until we find the parent level
      while !stack.isEmpty && stack.last!.level >= entry.level {
        let popped = stack.removeLast()
        if stack.isEmpty {
          result.append(popped.entry)
        } else {
          // Add to parent's children
          var parent = stack.removeLast()
          parent.entry = TOCEntry(
            level: parent.entry.level,
            text: parent.entry.text,
            slug: parent.entry.slug,
            position: parent.entry.position,
            children: parent.entry.children + [popped.entry]
          )
          stack.append(parent)
        }
      }

      // Push current entry onto stack
      stack.append((entry: entry, level: entry.level))
    }

    // Pop remaining stack
    while !stack.isEmpty {
      let popped = stack.removeLast()
      if stack.isEmpty {
        result.append(popped.entry)
      } else {
        var parent = stack.removeLast()
        parent.entry = TOCEntry(
          level: parent.entry.level,
          text: parent.entry.text,
          slug: parent.entry.slug,
          position: parent.entry.position,
          children: parent.entry.children + [popped.entry]
        )
        stack.append(parent)
      }
    }

    return result
  }
}

/// Errors that can occur during TOC generation.
public enum TOCGeneratorError: Error, Equatable {
  case invalidLevelRange(String)
}
