import Foundation
import MarkdownSyntax

/// Normalizes italic/emphasis markers in Markdown content.
public enum ItalicNormalizer {

    /// The target italic marker character.
    public enum Marker: String, Sendable, Equatable {
        case asterisk = "*"
        case underscore = "_"
    }

    /// Normalizes emphasis markers in `content` using the AST for precise targeting.
    ///
    /// Only modifies `Emphasis` nodes (`*text*` or `_text_`). Does not touch `Strong`
    /// nodes (`**bold**` or `__bold__`), inline code, or fenced code blocks.
    ///
    /// Emphasis nodes nested directly inside another `Emphasis` are skipped to avoid
    /// converting `*_text_*` into `**text**` (which would parse as strong/bold).
    ///
    /// - Note: `Position.end.offset` in MarkdownSyntax points to the closing delimiter
    ///   character itself (inclusive), so it is used directly as the closing marker index.
    ///
    /// - Parameters:
    ///   - content: The Markdown body text to normalize
    ///   - root: The parsed AST for `content`
    ///   - marker: The target italic marker character
    /// - Returns: The normalized content string
    public static func normalize(_ content: String, root: Root, to marker: Marker) -> String {
        let nodes = collectEmphasisNodes(from: root.children)

        let targetChar = Character(marker.rawValue)

        // Collect (openOffset, closeOffset) pairs for nodes that need changing
        var replacements: [(open: String.Index, close: String.Index)] = []

        for node in nodes {
            guard let startOffset = node.position.start.offset,
                  let endOffset = node.position.end.offset,
                  startOffset < endOffset else {
                continue
            }

            let openChar = content[startOffset]
            // Only process emphasis markers (skip if already correct or not a marker)
            guard (openChar == "*" || openChar == "_"), openChar != targetChar else {
                continue
            }

            // end.offset points to the closing delimiter character itself (inclusive).
            let closeOffset = endOffset

            replacements.append((open: startOffset, close: closeOffset))
        }

        // Sort in reverse order of open index so we process from end to start,
        // preserving the validity of earlier indices after each replacement.
        replacements.sort { $0.open > $1.open }

        var result = content
        let markerStr = String(targetChar)
        for (openOffset, closeOffset) in replacements {
            result.replaceSubrange(closeOffset...closeOffset, with: markerStr)
            result.replaceSubrange(openOffset...openOffset, with: markerStr)
        }

        return result
    }

    /// Collects `Emphasis` nodes from block-level content nodes, recursing into
    /// paragraphs, headings, blockquotes, and list items to find all emphasis nodes.
    ///
    /// Does NOT recurse into `Emphasis` children (to avoid nested-marker collisions).
    private static func collectEmphasisNodes(from nodes: [Content]) -> [Emphasis] {
        var result: [Emphasis] = []
        for node in nodes {
            if let paragraph = node as? Paragraph {
                result.append(contentsOf: collectFromPhrasing(paragraph.children))
            } else if let heading = node as? Heading {
                result.append(contentsOf: collectFromPhrasing(heading.children))
            } else if let blockquote = node as? Blockquote {
                result.append(contentsOf: collectEmphasisNodes(from: blockquote.children))
            } else if let list = node as? List {
                for listChild in list.children {
                    guard let item = listChild as? ListItem else { continue }
                    result.append(contentsOf: collectEmphasisNodes(from: item.children))
                }
            }
        }
        return result
    }

    /// Collects `Emphasis` nodes from phrasing (inline) content.
    ///
    /// Recurses into `Strong`, `Link`, and `Delete` (strikethrough) children but
    /// not into nested `Emphasis` children.
    private static func collectFromPhrasing(_ nodes: [PhrasingContent]) -> [Emphasis] {
        var result: [Emphasis] = []
        for node in nodes {
            if let emphasis = node as? Emphasis {
                result.append(emphasis)
                // Do not recurse into emphasis children to avoid nested marker collision
            } else if let strong = node as? Strong {
                result.append(contentsOf: collectFromPhrasing(strong.children))
            } else if let delete = node as? Delete {
                result.append(contentsOf: collectFromPhrasing(delete.children))
            } else if let link = node as? Link {
                result.append(contentsOf: collectFromPhrasing(link.children.map { $0 as PhrasingContent }))
            }
        }
        return result
    }
}
