import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Requested wikilink target spelling; neither case changes link syntax.
public enum WikilinkTargetStyle: String, Codable, Sendable {
  case path = "wiki-path"
  case name = "wiki-link"
}

public enum WikilinkConversionScope: String, Codable, Sendable {
  case all, body, frontmatter
}

/// Controls Markdown suffixes only; all other file extensions are retained.
public enum WikilinkMarkdownExtension: String, Codable, Sendable {
  /// Include extensions for path style, omit them for name style.
  case auto
  case include
  case omit
}

/// One replacement or skipped occurrence, suitable for a preview report.
public struct WikilinkConversionChange: Codable, Sendable, Equatable {
  public let location: String
  public let original: String
  public let replacement: String?
  public let diagnostic: String?
}

/// Immutable source snapshot and proposed result for revision-checked application.
public struct WikilinkConversionPlan {
  public let source: String
  public let proposed: String
  public let changes: [WikilinkConversionChange]
  public var hasChanges: Bool { !source.utf8.elementsEqual(proposed.utf8) }
}

/// Plans conversion independently of CLI presentation and persistence.
public enum WikilinkConversion {
  public static func plan(
    source: String,
    file: Path,
    resolver: WikilinkResolver,
    style: WikilinkTargetStyle,
    markdownExtension: WikilinkMarkdownExtension = .auto,
    scope: WikilinkConversionScope = .all,
    keys: [String] = [],
  ) throws -> WikilinkConversionPlan {
    var document = try MarkdownDocument(content: source)
    let original = document
    var changes: [WikilinkConversionChange] = []

    func rewrite(_ text: String, location: String) -> String {
      WikilinkRewriter.rewrite(text) { link in
        // Self-heading references already have the most precise destination.
        guard !link.target.isEmpty else { return nil }
        func skip(_ reason: String) -> String? {
          changes.append(.init(location: location, original: link.rawValue, replacement: nil, diagnostic: reason))
          return nil
        }
        let destination: Path
        switch resolver.resolve(link, from: file) {
        case .resolved(let path): destination = path
        case .unresolved: return skip("unresolved target")
        case .ambiguous: return skip("ambiguous target")
        }
        var target: String
        switch style {
        case .path:
          let prefix = resolver.root.string.hasSuffix("/") ? resolver.root.string : resolver.root.string + "/"
          guard destination.string.hasPrefix(prefix) else { return skip("target outside collection") }
          target = String(destination.string.dropFirst(prefix.count))
        case .name:
          target = destination.lastComponent
        }
        let omitExtension = markdownExtension == .omit || (markdownExtension == .auto && style == .name)
        if omitExtension, let suffix = destination.extension, ["md", "markdown"].contains(suffix) {
          target = String(target.dropLast(suffix.count + 1))
        }
        guard resolver.resolve(target: target, from: file) == .resolved(destination) else {
          return skip("proposed target '\(target)' does not uniquely resolve to the same file")
        }
        guard target != link.target else { return nil }
        let replacement = WikilinkRewriter.rewrite(link.rawValue) { _ in target }
        // Reject filenames that the supported wikilink grammar cannot represent.
        guard let parsed = WikilinkScanner.scan(replacement).first,
          parsed.target == target, parsed.anchor == link.anchor,
          parsed.displayText == link.displayText, parsed.isEmbed == link.isEmbed
        else { return skip("target cannot be represented safely as a wikilink") }
        changes.append(.init(location: location, original: link.rawValue, replacement: replacement, diagnostic: nil))
        return target
      }
    }

    func convertValue(_ value: FrontMatterValue, location: String) -> FrontMatterValue {
      switch value {
      case .string(let text): return .string(rewrite(text, location: location))
      case .array(let values):
        return .array(values.enumerated().map { convertValue($0.element, location: "\(location)[\($0.offset)]") })
      default: return value
      }
    }
    if scope != .body {
      for (key, value) in original.frontMatter where keys.isEmpty || keys.contains(key) {
        document.frontMatter[key] = convertValue(value, location: "frontmatter[\(key)]")
      }
    }
    if scope != .frontmatter { document.body = rewrite(original.body, location: "body") }
    let proposed: String
    if document.frontMatter != original.frontMatter {
      proposed = try document.render()
    } else {
      // The parser retains the exact body suffix, so body-only edits preserve the envelope.
      proposed = String(decoding: source.utf8.dropLast(original.body.utf8.count), as: UTF8.self) + document.body
    }
    return .init(source: source, proposed: proposed, changes: changes)
  }
}
