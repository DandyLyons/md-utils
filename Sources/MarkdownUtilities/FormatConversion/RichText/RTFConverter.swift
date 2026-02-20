import Foundation
import MarkdownSyntax

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Converts Markdown AST to RTF data.
///
/// This converter walks the Markdown AST and builds an `NSMutableAttributedString`
/// with appropriate font, paragraph style, and other attributes, then exports
/// RTF `Data`.
public struct RTFConverter: MarkdownConverter {
    public typealias Output = Data
    public typealias Options = RTFOptions

    public init() {}

    public func convert(from root: Root, options: RTFOptions) async throws -> Data {
        let result = NSMutableAttributedString()

        processBlockContent(root.children, into: result, options: options, listDepth: 0)

        // Remove trailing newline if present
        let length = result.length
        if length > 0 {
            let lastChar = result.attributedSubstring(from: NSRange(location: length - 1, length: 1)).string
            if lastChar == "\n" {
                result.deleteCharacters(in: NSRange(location: length - 1, length: 1))
            }
        }

        let range = NSRange(location: 0, length: result.length)
        guard let rtfData = result.rtf(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf,
        ]) else {
            throw RTFConversionError.failedToGenerateRTF
        }

        return rtfData
    }

    // MARK: - Block Content Processing

    private func processBlockContent(
        _ content: [Content],
        into result: NSMutableAttributedString,
        options: RTFOptions,
        listDepth: Int
    ) {
        for (index, node) in content.enumerated() {
            processBlockNode(node, into: result, options: options, listDepth: listDepth)
            // Add paragraph separator between blocks (not after the last one)
            if index < content.count - 1 {
                let separator = NSAttributedString(string: "\n", attributes: [
                    .font: baseFont(options: options),
                ])
                result.append(separator)
            }
        }
    }

    private func processBlockNode(
        _ node: Content,
        into result: NSMutableAttributedString,
        options: RTFOptions,
        listDepth: Int
    ) {
        switch node {
        case let heading as Heading:
            processHeading(heading, into: result, options: options)

        case let paragraph as Paragraph:
            processParagraph(paragraph, into: result, options: options, indent: CGFloat(listDepth) * options.listIndent)

        case let codeBlock as Code:
            processCodeBlock(codeBlock, into: result, options: options)

        case let blockquote as Blockquote:
            processBlockquote(blockquote, into: result, options: options)

        case let list as List:
            processList(list, into: result, options: options, depth: listDepth)

        case is ThematicBreak:
            processThematicBreak(into: result, options: options)

        default:
            break
        }
    }

    // MARK: - Heading

    private func processHeading(
        _ heading: Heading,
        into result: NSMutableAttributedString,
        options: RTFOptions
    ) {
        let depth = heading.depth.rawValue
        let scaleIndex = min(depth - 1, options.headingScales.count - 1)
        let scale = options.headingScales[max(0, scaleIndex)]
        let fontSize = options.baseFontSize * scale

        let font = boldFont(name: options.baseFontName, size: fontSize, options: options)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = options.paragraphSpacing
        paragraphStyle.paragraphSpacing = options.paragraphSpacing

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]
        #if canImport(AppKit) || canImport(UIKit)
        attributes[.foregroundColor] = PlatformColor.black
        #endif

        let headingText = NSMutableAttributedString()
        processPhrasingContent(heading.children, into: headingText, baseAttributes: attributes, options: options)
        headingText.append(NSAttributedString(string: "\n", attributes: attributes))
        result.append(headingText)
    }

    // MARK: - Paragraph

    private func processParagraph(
        _ paragraph: Paragraph,
        into result: NSMutableAttributedString,
        options: RTFOptions,
        indent: CGFloat = 0
    ) {
        let font = baseFont(options: options)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = options.paragraphSpacing
        if indent > 0 {
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.headIndent = indent
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let paraText = NSMutableAttributedString()
        processPhrasingContent(paragraph.children, into: paraText, baseAttributes: attributes, options: options)
        paraText.append(NSAttributedString(string: "\n", attributes: attributes))
        result.append(paraText)
    }

    // MARK: - Code Block

    private func processCodeBlock(
        _ codeBlock: Code,
        into result: NSMutableAttributedString,
        options: RTFOptions
    ) {
        let font = monoFont(options: options)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = options.paragraphSpacing
        paragraphStyle.firstLineHeadIndent = options.listIndent
        paragraphStyle.headIndent = options.listIndent

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]

        let codeText = NSAttributedString(string: codeBlock.value + "\n", attributes: attributes)
        result.append(codeText)
    }

    // MARK: - Blockquote

    private func processBlockquote(
        _ blockquote: Blockquote,
        into result: NSMutableAttributedString,
        options: RTFOptions
    ) {
        // Process children with increased indent by wrapping paragraphs
        for child in blockquote.children {
            if let paragraph = child as? Paragraph {
                processParagraph(paragraph, into: result, options: options, indent: options.listIndent)
            } else {
                processBlockNode(child, into: result, options: options, listDepth: 1)
            }
        }
    }

    // MARK: - List

    private func processList(
        _ list: List,
        into result: NSMutableAttributedString,
        options: RTFOptions,
        depth: Int
    ) {
        let ordered = list.ordered
        for (itemIndex, listContent) in list.children.enumerated() {
            guard let item = listContent as? ListItem else { continue }

            let indent = CGFloat(depth + 1) * options.listIndent
            let prefix: String
            if ordered {
                prefix = "\(itemIndex + 1).\t"
            } else {
                prefix = "\u{2022}\t"
            }

            let font = baseFont(options: options)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = options.paragraphSpacing / 2
            paragraphStyle.firstLineHeadIndent = CGFloat(depth) * options.listIndent
            paragraphStyle.headIndent = indent
            paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: indent)]

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]

            let itemText = NSMutableAttributedString(string: prefix, attributes: attributes)

            // Process item children
            for child in item.children {
                if let paragraph = child as? Paragraph {
                    processPhrasingContent(paragraph.children, into: itemText, baseAttributes: attributes, options: options)
                } else if let nestedList = child as? List {
                    itemText.append(NSAttributedString(string: "\n", attributes: attributes))
                    processList(nestedList, into: itemText, options: options, depth: depth + 1)
                }
            }

            itemText.append(NSAttributedString(string: "\n", attributes: attributes))
            result.append(itemText)
        }
    }

    // MARK: - Thematic Break

    private func processThematicBreak(
        into result: NSMutableAttributedString,
        options: RTFOptions
    ) {
        let font = baseFont(options: options)
        let rule = NSAttributedString(
            string: String(repeating: "\u{2500}", count: 40) + "\n",
            attributes: [.font: font]
        )
        result.append(rule)
    }

    // MARK: - Phrasing (Inline) Content

    private func processPhrasingContent(
        _ content: [PhrasingContent],
        into result: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any],
        options: RTFOptions
    ) {
        for node in content {
            processPhrasingNode(node, into: result, baseAttributes: baseAttributes, options: options)
        }
    }

    private func processPhrasingNode(
        _ node: PhrasingContent,
        into result: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any],
        options: RTFOptions
    ) {
        switch node {
        case let text as Text:
            result.append(NSAttributedString(string: text.value, attributes: baseAttributes))

        case let inlineCode as InlineCode:
            var codeAttributes = baseAttributes
            codeAttributes[.font] = monoFont(options: options)
            result.append(NSAttributedString(string: inlineCode.value, attributes: codeAttributes))

        case let strong as Strong:
            var strongAttributes = baseAttributes
            if let currentFont = baseAttributes[.font] as? PlatformFont {
                strongAttributes[.font] = addBoldTrait(to: currentFont, options: options)
            }
            processPhrasingContent(strong.children, into: result, baseAttributes: strongAttributes, options: options)

        case let emphasis as Emphasis:
            var emAttributes = baseAttributes
            if let currentFont = baseAttributes[.font] as? PlatformFont {
                emAttributes[.font] = addItalicTrait(to: currentFont, options: options)
            }
            processPhrasingContent(emphasis.children, into: result, baseAttributes: emAttributes, options: options)

        case let delete as Delete:
            var deleteAttributes = baseAttributes
            deleteAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            processPhrasingContent(delete.children, into: result, baseAttributes: deleteAttributes, options: options)

        case let link as Link:
            var linkAttributes = baseAttributes
            if options.preserveLinks {
                linkAttributes[.link] = link.url
            }
            let children = link.children.map { $0 as PhrasingContent }
            processPhrasingContent(children, into: result, baseAttributes: linkAttributes, options: options)

        case let image as Image:
            // Images are lossy in RTF — render alt text in italics
            var imageAttributes = baseAttributes
            if let currentFont = baseAttributes[.font] as? PlatformFont {
                imageAttributes[.font] = addItalicTrait(to: currentFont, options: options)
            }
            let children = image.children.map { $0 as PhrasingContent }
            processPhrasingContent(children, into: result, baseAttributes: imageAttributes, options: options)

        case is Break:
            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))

        case is SoftBreak:
            result.append(NSAttributedString(string: " ", attributes: baseAttributes))

        case let html as HTML:
            result.append(NSAttributedString(string: html.value, attributes: baseAttributes))

        default:
            break
        }
    }

    // MARK: - Font Helpers

    private func baseFont(options: RTFOptions) -> PlatformFont {
        PlatformFont(name: options.baseFontName, size: options.baseFontSize)
            ?? PlatformFont.systemFont(ofSize: options.baseFontSize)
    }

    private func monoFont(options: RTFOptions) -> PlatformFont {
        PlatformFont(name: options.monospaceFontName, size: options.baseFontSize)
            ?? PlatformFont.systemFont(ofSize: options.baseFontSize)
    }

    private func boldFont(name: String, size: CGFloat, options: RTFOptions) -> PlatformFont {
        #if canImport(AppKit)
        let font = PlatformFont(name: name, size: size) ?? PlatformFont.systemFont(ofSize: size)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #elseif canImport(UIKit)
        if let font = PlatformFont(name: name, size: size) {
            if let boldDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                return PlatformFont(descriptor: boldDescriptor, size: size)
            }
            return font
        }
        return PlatformFont.boldSystemFont(ofSize: size)
        #endif
    }

    private func addBoldTrait(to font: PlatformFont, options: RTFOptions) -> PlatformFont {
        #if canImport(AppKit)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #elseif canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitBold)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return PlatformFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
        #endif
    }

    private func addItalicTrait(to font: PlatformFont, options: RTFOptions) -> PlatformFont {
        #if canImport(AppKit)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #elseif canImport(UIKit)
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return PlatformFont(descriptor: descriptor, size: font.pointSize)
        }
        return font
        #endif
    }
}
