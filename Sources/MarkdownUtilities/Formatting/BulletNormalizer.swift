import Foundation
import MarkdownSyntax

/// Normalizes unordered list bullet markers in Markdown content.
public enum BulletNormalizer {

    /// The target bullet marker character.
    public enum Marker: String, Sendable, Equatable {
        case dash = "-"
        case asterisk = "*"
    }

    /// Normalizes bullet markers in `content` using the AST for precise targeting.
    ///
    /// Only modifies unordered list items; skips ordered lists, code blocks, and
    /// horizontal rules (thematic breaks).
    ///
    /// - Parameters:
    ///   - content: The Markdown body text to normalize
    ///   - root: The parsed AST for `content`
    ///   - marker: The target bullet marker character
    /// - Returns: The normalized content string
    public static func normalize(_ content: String, root: Root, to marker: Marker) -> String {
        let items = collectUnorderedListItems(from: root.children)

        var lineNumbers = Set<Int>()
        for item in items {
            lineNumbers.insert(item.position.start.line)
        }

        guard !lineNumbers.isEmpty else { return content }

        var lines = content.components(separatedBy: "\n")
        for i in lines.indices {
            if lineNumbers.contains(i + 1) {
                lines[i] = replaceBullet(in: lines[i], to: marker)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Recursively collects `ListItem` nodes from unordered `List` nodes only.
    ///
    /// Recurses into `Blockquote` children and into `ListItem` children (for nested lists).
    /// Ordered list items are skipped but their children are still searched for nested
    /// unordered lists.
    private static func collectUnorderedListItems(from nodes: [Content]) -> [ListItem] {
        var items: [ListItem] = []
        for node in nodes {
            if let list = node as? List {
                if !list.ordered {
                    for listChild in list.children {
                        guard let item = listChild as? ListItem else { continue }
                        items.append(item)
                        // Recurse into nested block content (nested lists)
                        items.append(contentsOf: collectUnorderedListItems(from: item.children))
                    }
                } else {
                    // Ordered list — skip its items but still recurse into children
                    // to find nested unordered lists
                    for listChild in list.children {
                        guard let item = listChild as? ListItem else { continue }
                        items.append(contentsOf: collectUnorderedListItems(from: item.children))
                    }
                }
            } else if let blockquote = node as? Blockquote {
                items.append(contentsOf: collectUnorderedListItems(from: blockquote.children))
            }
        }
        return items
    }

    /// Replaces the bullet character on a line (the first `*`, `-`, or `+` after leading whitespace).
    ///
    /// Returns the line unchanged if no bullet marker is found.
    private static func replaceBullet(in line: String, to marker: Marker) -> String {
        var index = line.startIndex

        // Skip leading whitespace
        while index < line.endIndex && line[index].isWhitespace {
            index = line.index(after: index)
        }

        // Check if next character is an unordered list marker
        guard index < line.endIndex else { return line }
        let ch = line[index]
        guard ch == "*" || ch == "-" || ch == "+" else { return line }

        // Verify the marker is followed by whitespace (so it's a bullet, not a word boundary)
        let afterBullet = line.index(after: index)
        guard afterBullet < line.endIndex, line[afterBullet].isWhitespace else { return line }

        var result = line
        result.replaceSubrange(index...index, with: marker.rawValue)
        return result
    }
}
