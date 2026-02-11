//
//  ResolvedWikilink.swift
//  MarkdownUtilities
//

import PathKit

/// A wikilink combined with its resolution result, suitable for JSON serialization.
public struct ResolvedWikilink: Sendable, Codable, Equatable {
  /// The wikilink target string.
  public let target: String

  /// The display text, if any.
  public let displayText: String?

  /// The anchor formatted as a string (e.g. "#heading", "#^blockID"), if any.
  public let anchor: String?

  /// Whether this is an embed (`![[...]]`).
  public let isEmbed: Bool

  /// The resolved file path, if exactly one match was found.
  public let resolvedPath: String?

  /// The resolution status: "resolved", "unresolved", or "ambiguous".
  public let status: String

  /// Candidate paths when the resolution is ambiguous.
  public let candidates: [String]?

  /// Creates a ``ResolvedWikilink`` from a ``Wikilink`` and its ``WikilinkResolution``.
  public init(wikilink: Wikilink, resolution: WikilinkResolution) {
    self.target = wikilink.target
    self.displayText = wikilink.displayText
    self.anchor = wikilink.anchor.map { Self.formatAnchor($0) }
    self.isEmbed = wikilink.isEmbed

    switch resolution {
    case .resolved(let path):
      self.resolvedPath = path.string
      self.status = "resolved"
      self.candidates = nil
    case .unresolved:
      self.resolvedPath = nil
      self.status = "unresolved"
      self.candidates = nil
    case .ambiguous(let paths):
      self.resolvedPath = nil
      self.status = "ambiguous"
      self.candidates = paths.map(\.string)
    }
  }

  /// Formats a ``WikilinkAnchor`` as a string.
  private static func formatAnchor(_ anchor: WikilinkAnchor) -> String {
    switch anchor {
    case .heading(let text):
      "#\(text)"
    case .blockID(let id):
      "#^\(id)"
    }
  }
}
