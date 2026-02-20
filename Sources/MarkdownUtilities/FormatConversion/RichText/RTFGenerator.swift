import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Generates Markdown from RTF data.
///
/// This generator loads RTF `Data` into an `NSAttributedString`, then walks
/// the attributes to produce Markdown text. Heading detection is based on
/// font size heuristics, and list/code detection uses font and indentation cues.
public struct RTFGenerator: MarkdownGenerator {
    public typealias Input = Data
    public typealias Options = RTFGeneratorOptions

    public init() {}

    public func generate(from input: Data, options: RTFGeneratorOptions) async throws -> String {
        let attributedString = try loadRTF(from: input)
        let fullString = attributedString.string

        guard !fullString.isEmpty else {
            return ""
        }

        let baseFontSize = detectBaseFontSize(in: attributedString)
        var markdownLines: [String] = []
        let paragraphs = splitIntoParagraphs(attributedString)

        var inCodeBlock = false

        for paragraph in paragraphs {
            let text = paragraph.string.trimmingCharacters(in: .newlines)
            if text.isEmpty {
                if inCodeBlock {
                    markdownLines.append("```")
                    markdownLines.append("")
                    inCodeBlock = false
                }
                markdownLines.append("")
                continue
            }

            // Detect code block (all monospace font)
            if options.detectCodeBlocks && isMonospace(paragraph) {
                if !inCodeBlock {
                    markdownLines.append("```")
                    inCodeBlock = true
                }
                markdownLines.append(text)
                continue
            }

            if inCodeBlock {
                markdownLines.append("```")
                markdownLines.append("")
                inCodeBlock = false
            }

            // Detect heading
            if options.detectHeadings {
                if let headingLevel = detectHeadingLevel(paragraph, baseFontSize: baseFontSize, threshold: options.headingSizeThreshold) {
                    let prefix = String(repeating: "#", count: headingLevel)
                    let inlineMarkdown = convertInlineAttributes(paragraph, skipBold: true)
                    markdownLines.append("\(prefix) \(inlineMarkdown)")
                    markdownLines.append("")
                    continue
                }
            }

            // Detect list items
            if options.detectLists {
                if let listItem = detectListItem(text) {
                    let content = listItem.content
                    let contentAttrString = extractContentAfterPrefix(paragraph, prefixLength: listItem.prefixLength)
                    let inlineMarkdown = convertInlineAttributes(contentAttrString)
                    markdownLines.append("\(listItem.prefix)\(inlineMarkdown)")
                    _ = content // suppress unused warning
                    continue
                }
            }

            // Detect blockquote (large left indent relative to default)
            if detectBlockquote(paragraph) {
                let inlineMarkdown = convertInlineAttributes(paragraph)
                markdownLines.append("> \(inlineMarkdown)")
                continue
            }

            // Regular paragraph
            let inlineMarkdown = convertInlineAttributes(paragraph)
            markdownLines.append(inlineMarkdown)
            markdownLines.append("")
        }

        if inCodeBlock {
            markdownLines.append("```")
        }

        // Clean up multiple consecutive blank lines
        var cleaned: [String] = []
        var lastWasBlank = false
        for line in markdownLines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && lastWasBlank {
                continue
            }
            cleaned.append(line)
            lastWasBlank = isBlank
        }

        // Remove trailing blank lines
        while let last = cleaned.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            cleaned.removeLast()
        }

        return cleaned.joined(separator: "\n")
    }

    // MARK: - RTF Loading

    private func loadRTF(from data: Data) throws -> NSAttributedString {
        #if canImport(AppKit)
        guard let attrString = NSAttributedString(
            rtf: data,
            documentAttributes: nil
        ) else {
            throw RTFConversionError.failedToParseRTF
        }
        return attrString
        #elseif canImport(UIKit)
        do {
            let attrString = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attrString
        } catch {
            throw RTFConversionError.failedToParseRTF
        }
        #endif
    }

    // MARK: - Paragraph Splitting

    private func splitIntoParagraphs(_ attributedString: NSAttributedString) -> [NSAttributedString] {
        let fullString = attributedString.string
        var paragraphs: [NSAttributedString] = []
        var searchStart = fullString.startIndex

        while searchStart < fullString.endIndex {
            let remaining = fullString[searchStart...]
            if let newlineRange = remaining.range(of: "\n") {
                let paragraphEnd = newlineRange.upperBound
                let nsRange = NSRange(searchStart..<paragraphEnd, in: fullString)
                let sub = attributedString.attributedSubstring(from: nsRange)
                paragraphs.append(sub)
                searchStart = paragraphEnd
            } else {
                // Last paragraph without trailing newline
                let nsRange = NSRange(searchStart..<fullString.endIndex, in: fullString)
                let sub = attributedString.attributedSubstring(from: nsRange)
                paragraphs.append(sub)
                break
            }
        }

        return paragraphs
    }

    // MARK: - Base Font Size Detection

    private func detectBaseFontSize(in attributedString: NSAttributedString) -> CGFloat {
        var sizeCounts: [CGFloat: Int] = [:]
        let range = NSRange(location: 0, length: attributedString.length)

        attributedString.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            if let font = value as? PlatformFont {
                let size = font.pointSize
                sizeCounts[size, default: 0] += (attrRange.length)
            }
        }

        // Return the most common font size
        return sizeCounts.max(by: { $0.value < $1.value })?.key ?? 14
    }

    // MARK: - Heading Detection

    private func detectHeadingLevel(
        _ paragraph: NSAttributedString,
        baseFontSize: CGFloat,
        threshold: CGFloat
    ) -> Int? {
        let text = paragraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Check if the visible content of the paragraph is bold and larger than base
        // Only examine the trimmed range (skip trailing newlines/whitespace)
        let fullText = paragraph.string
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimStart = fullText.distance(
            from: fullText.startIndex,
            to: fullText.range(of: trimmedText)?.lowerBound ?? fullText.startIndex
        )
        let trimmedRange = NSRange(location: trimStart, length: trimmedText.count)

        var isBold = true
        var fontSize: CGFloat = 0
        var hasFont = false

        paragraph.enumerateAttribute(.font, in: trimmedRange) { value, _, _ in
            guard let font = value as? PlatformFont else { return }
            hasFont = true
            fontSize = max(fontSize, font.pointSize)

            #if canImport(AppKit)
            let traits = NSFontManager.shared.traits(of: font)
            if !traits.contains(.boldFontMask) {
                isBold = false
            }
            #elseif canImport(UIKit)
            let traits = font.fontDescriptor.symbolicTraits
            if !traits.contains(.traitBold) {
                isBold = false
            }
            #endif
        }

        guard hasFont && isBold && fontSize >= baseFontSize * threshold else {
            return nil
        }

        // Determine heading level based on size ratio
        let ratio = fontSize / baseFontSize
        if ratio >= 1.8 { return 1 }
        if ratio >= 1.4 { return 2 }
        if ratio >= 1.2 { return 3 }
        if ratio >= 1.05 { return 4 }
        if ratio >= 0.95 { return 5 }
        return 6
    }

    // MARK: - Monospace Detection

    private func isMonospace(_ paragraph: NSAttributedString) -> Bool {
        let text = paragraph.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let range = NSRange(location: 0, length: paragraph.length)
        var allMono = true

        paragraph.enumerateAttribute(.font, in: range) { value, attrRange, stop in
            guard let font = value as? PlatformFont else { return }
            // Check the text in this range — skip whitespace-only runs
            let subRange = Range(attrRange, in: paragraph.string)
            if let subRange = subRange {
                let subText = String(paragraph.string[subRange])
                if subText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            }

            #if canImport(AppKit)
            let traits = NSFontManager.shared.traits(of: font)
            if !traits.contains(.fixedPitchFontMask) {
                // Check font name as fallback
                let name = font.fontName.lowercased()
                if !name.contains("menlo") && !name.contains("courier") && !name.contains("mono") && !name.contains("consolas") {
                    allMono = false
                    stop.pointee = true
                }
            }
            #elseif canImport(UIKit)
            let traits = font.fontDescriptor.symbolicTraits
            if !traits.contains(.traitMonoSpace) {
                let name = font.fontName.lowercased()
                if !name.contains("menlo") && !name.contains("courier") && !name.contains("mono") && !name.contains("consolas") {
                    allMono = false
                    stop.pointee = true
                }
            }
            #endif
        }

        return allMono
    }

    // MARK: - List Detection

    private struct ListItemInfo {
        let prefix: String
        let content: String
        let prefixLength: Int
    }

    private func detectListItem(_ text: String) -> ListItemInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Bullet list: starts with bullet character or dash
        if trimmed.hasPrefix("\u{2022}") {
            let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            let prefixLength = text.distance(from: text.startIndex, to: text.firstIndex(of: "\u{2022}")!) + 1
            return ListItemInfo(prefix: "- ", content: content, prefixLength: prefixLength + 1)
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2))
            return ListItemInfo(prefix: "- ", content: content, prefixLength: 2)
        }

        // Ordered list: starts with number followed by . or )
        let pattern = #"^(\d+)[.\)]\s*"#
        if let match = trimmed.range(of: pattern, options: .regularExpression) {
            let matchedPrefix = String(trimmed[match])
            let content = String(trimmed[match.upperBound...])
            return ListItemInfo(prefix: matchedPrefix, content: content, prefixLength: matchedPrefix.count)
        }

        return nil
    }

    private func extractContentAfterPrefix(_ paragraph: NSAttributedString, prefixLength: Int) -> NSAttributedString {
        let text = paragraph.string
        // Find the actual content start by skipping bullet/number and whitespace/tabs
        var contentStart = text.startIndex
        var skipped = 0
        for char in text {
            if skipped >= prefixLength {
                // Also skip any tabs after prefix
                if char == "\t" || char == " " {
                    contentStart = text.index(after: contentStart)
                    continue
                }
                break
            }
            skipped += 1
            contentStart = text.index(after: contentStart)
        }

        let nsRange = NSRange(contentStart..<text.endIndex, in: text)
        guard nsRange.length > 0 else {
            return NSAttributedString(string: "")
        }
        return paragraph.attributedSubstring(from: nsRange)
    }

    // MARK: - Blockquote Detection

    private func detectBlockquote(_ paragraph: NSAttributedString) -> Bool {
        guard paragraph.length > 0 else { return false }

        let attrs = paragraph.attributes(at: 0, effectiveRange: nil)
        if let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
            return paragraphStyle.headIndent >= 24 || paragraphStyle.firstLineHeadIndent >= 24
        }
        return false
    }

    // MARK: - Inline Attribute Conversion

    private func convertInlineAttributes(_ attributedString: NSAttributedString, skipBold: Bool = false) -> String {
        let text = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        var result = ""
        let trimmedStart = attributedString.string.distance(
            from: attributedString.string.startIndex,
            to: attributedString.string.firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) ?? attributedString.string.startIndex
        )

        let trimmedString = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = NSRange(location: trimmedStart, length: trimmedString.count)

        guard trimmedRange.location + trimmedRange.length <= attributedString.length else {
            return text
        }

        let trimmedAttrString = attributedString.attributedSubstring(from: trimmedRange)

        let range = NSRange(location: 0, length: trimmedAttrString.length)

        trimmedAttrString.enumerateAttributes(in: range) { attrs, attrRange, _ in
            guard let subRange = Range(attrRange, in: trimmedAttrString.string) else { return }
            var segment = String(trimmedAttrString.string[subRange])

            // Skip empty segments
            guard !segment.isEmpty else { return }

            // Detect formatting traits
            var isBold = false
            var isItalic = false
            var isMono = false
            var isStrikethrough = false
            var linkURL: URL?

            if let font = attrs[.font] as? PlatformFont {
                #if canImport(AppKit)
                let traits = NSFontManager.shared.traits(of: font)
                isBold = traits.contains(.boldFontMask)
                isItalic = traits.contains(.italicFontMask)
                isMono = traits.contains(.fixedPitchFontMask) ||
                    font.fontName.lowercased().contains("menlo") ||
                    font.fontName.lowercased().contains("courier") ||
                    font.fontName.lowercased().contains("mono")
                #elseif canImport(UIKit)
                let traits = font.fontDescriptor.symbolicTraits
                isBold = traits.contains(.traitBold)
                isItalic = traits.contains(.traitItalic)
                isMono = traits.contains(.traitMonoSpace) ||
                    font.fontName.lowercased().contains("menlo") ||
                    font.fontName.lowercased().contains("courier") ||
                    font.fontName.lowercased().contains("mono")
                #endif
            }

            if let strikethrough = attrs[.strikethroughStyle] as? Int, strikethrough != 0 {
                isStrikethrough = true
            }

            if let link = attrs[.link] {
                if let url = link as? URL {
                    linkURL = url
                } else if let urlString = link as? String {
                    linkURL = URL(string: urlString)
                }
            }

            // Build markdown wrapping
            if skipBold {
                isBold = false
            }

            if let url = linkURL {
                segment = "[\(segment)](\(url.absoluteString))"
            }

            if isMono {
                segment = "`\(segment)`"
            } else {
                if isBold && isItalic {
                    segment = "***\(segment)***"
                } else if isBold {
                    segment = "**\(segment)**"
                } else if isItalic {
                    segment = "*\(segment)*"
                }
            }

            if isStrikethrough {
                segment = "~~\(segment)~~"
            }

            result += segment
        }

        return result
    }
}
