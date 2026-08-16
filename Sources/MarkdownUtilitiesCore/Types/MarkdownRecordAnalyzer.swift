import Foundation
import MarkdownSyntax

/// Expensive derived record state needed by a specific assessment plan.
package struct MarkdownRecordAnalysisRequirements: OptionSet, Sendable {
  package let rawValue: UInt8

  package init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  /// Parse the Markdown syntax tree and retain heading relationships.
  package static let headings = Self(rawValue: 1 << 0)
  /// Preserve the historical eager-analysis behavior.
  package static let all: Self = [.headings]

  package static func required(by predicate: MarkdownPredicate) -> Self {
    switch predicate {
    case .heading, .headingRelationship, .section:
      return .headings
    case .path, .maxBodyLines, .maxBodyWords:
      return []
    }
  }

  package static func required(by predicate: MarkdownRulePredicate) -> Self {
    switch predicate {
    case .markdown(let predicate):
      return required(by: predicate)
    case .heading, .headingRegularExpression, .section:
      return .headings
    case .pathRegularExpression, .filenameEquals, .extensionIn,
         .modifiedAfter, .modifiedBefore, .frontmatterField,
         .frontmatterJMESPath, .bodyContains, .bodyRegularExpression,
         .wikilink, .bodyLineCount, .bodyWordCount:
      return []
    }
  }
}

/// Describes how one rules-runtime record exposes frontmatter and body content.
package enum MarkdownRecordContentKind: Sendable {
  /// Ordinary Markdown with leading `---` frontmatter and Markdown structure.
  case markdown
  /// Non-Markdown text using ordinary leading `---` frontmatter.
  case plainText
  /// Non-Markdown host source using a shipped wrapped-frontmatter syntax.
  case wrapped(FrontMatterSyntax)
  /// Non-Markdown host source without a shipped frontmatter mapping.
  case unmapped(fileExtension: String)

  /// Resolves rules-runtime behavior from a filename extension.
  package static func rulesKind(forExtension fileExtension: String) -> Self {
    let normalized = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    if normalized == "md" || normalized == "markdown" { return .markdown }
    if normalized == "txt" { return .plainText }
    if let syntax = FrontMatterSyntax.shippedSyntax(forExtension: normalized) {
      return .wrapped(syntax)
    }
    return .unmapped(fileExtension: normalized)
  }
}

/// Parsed record state shared by rule, type, identity, and server assessment.
///
/// Package visibility keeps parser implementation details out of the public API while
/// allowing sibling targets to guarantee that one snapshot build parses each record once.
package struct AnalyzedMarkdownRecord: Sendable {
  package var record: MarkdownRecord
  package var body: String
  package var hasFrontmatter: Bool
  package var userFrontmatter: [String: JSONValue]?
  package var systemTypeHints: [MarkdownTypeHint]
  package var headings: [AnalyzedMarkdownHeading]
  package var parseDiagnostics: [MarkdownDiagnostic]
  package var supportsMarkdownStructure: Bool
  package var unavailableFrontmatterExtension: String?

  package var allTypeHints: [MarkdownTypeHint] {
    var result: [MarkdownTypeHint] = []
    var seen: Set<MarkdownTypeHint> = []
    for hint in systemTypeHints + record.context.typeHints where seen.insert(hint).inserted {
      result.append(hint)
    }
    return result
  }
}

/// Heading facts retained after one Markdown syntax-tree traversal.
package struct AnalyzedMarkdownHeading: Sendable {
  package var text: String
  package var level: Int
  package var line: Int
  package var parentIndex: Int?
  package var directContentIsEmpty: Bool
}

/// Produces reusable structured state from canonical Markdown content.
package enum MarkdownRecordAnalyzer {
  /// Separates frontmatter, parses safe YAML, and derives requested document state.
  package static func analyze(
    _ record: MarkdownRecord,
    requirements: MarkdownRecordAnalysisRequirements = .all,
    contentKind: MarkdownRecordContentKind = .markdown
  ) async -> AnalyzedMarkdownRecord {
    let parts: RecordParts
    switch contentKind {
    case .markdown, .plainText:
      let parser = FrontMatterParser()
      var input = Substring(record.content)
      do {
        let parsed = try parser.parse(&input)
        parts = RecordParts(
          rawFrontmatter: parsed.rawFrontMatter,
          body: parsed.body,
          hasFrontmatter: parsed.format != nil,
          format: parsed.format,
          diagnostics: []
        )
      } catch {
        let supportsMarkdownStructure = contentKind.supportsMarkdownStructure
        return AnalyzedMarkdownRecord(
          record: record,
          body: record.content,
          hasFrontmatter: containsFrontmatterBlock(record.content),
          userFrontmatter: nil,
          systemTypeHints: [],
          headings: supportsMarkdownStructure
            ? await analyzeHeadings(in: record.content, when: requirements)
            : [],
          parseDiagnostics: [parseDiagnostic(error.localizedDescription, format: nil)],
          supportsMarkdownStructure: supportsMarkdownStructure,
          unavailableFrontmatterExtension: nil
        )
      }
    case .wrapped(let syntax):
      let scan = WrappedFrontMatterParser(syntax: syntax).parse(record.content)
      var body = record.content
      if let block = scan.firstBlock {
        body.removeSubrange(block.range)
      }
      let diagnostics = scan.additionalOpeningLines.first.map { line in
        [multipleBlocksDiagnostic(line: line)]
      } ?? []
      parts = RecordParts(
        rawFrontmatter: scan.firstBlock?.rawFrontMatter ?? "",
        body: body,
        hasFrontmatter: scan.firstBlock != nil,
        format: scan.firstBlock?.format,
        diagnostics: diagnostics
      )
    case .unmapped(let fileExtension):
      return AnalyzedMarkdownRecord(
        record: record,
        body: record.content,
        hasFrontmatter: false,
        userFrontmatter: nil,
        systemTypeHints: [],
        headings: [],
        parseDiagnostics: [],
        supportsMarkdownStructure: false,
        unavailableFrontmatterExtension: fileExtension
      )
    }

    var userFrontmatter: [String: JSONValue]?
    var hints: [MarkdownTypeHint] = []
    var diagnostics = parts.diagnostics

    if parts.hasFrontmatter {
      do {
        let frontMatter = try FrontMatterConversion.parse(
          parts.rawFrontmatter,
          format: parts.format ?? .yaml
        )
        let dynamicValue = FrontMatterConversion.foundationValue(frontMatter)
        guard case .object(var object) = try JSONValue(any: dynamicValue) else {
          throw YAMLConversionError.notAMapping
        }
        if let systemMetadata = object.removeValue(forKey: "$md-utils") {
          let parsed = parseTypeHints(systemMetadata)
          hints = parsed.hints
          diagnostics.append(contentsOf: parsed.diagnostics)
        }
        userFrontmatter = object.isEmpty ? nil : object
      } catch {
        diagnostics.append(parseDiagnostic(error.localizedDescription, format: parts.format))
      }
    }

    return AnalyzedMarkdownRecord(
      record: record,
      body: parts.body,
      hasFrontmatter: parts.hasFrontmatter,
      userFrontmatter: userFrontmatter,
      systemTypeHints: hints,
      headings: contentKind.supportsMarkdownStructure
        ? await analyzeHeadings(in: parts.body, when: requirements)
        : [],
      parseDiagnostics: diagnostics,
      supportsMarkdownStructure: contentKind.supportsMarkdownStructure,
      unavailableFrontmatterExtension: nil
    )
  }

  private struct RecordParts {
    var rawFrontmatter: String
    var body: String
    var hasFrontmatter: Bool
    var format: FrontMatterFormat?
    var diagnostics: [MarkdownDiagnostic]
  }

  private static func analyzeHeadings(
    in body: String,
    when requirements: MarkdownRecordAnalysisRequirements
  ) async -> [AnalyzedMarkdownHeading] {
    guard requirements.contains(.headings) else { return [] }
    return await analyzeHeadings(in: body)
  }

  private static func analyzeHeadings(in body: String) async -> [AnalyzedMarkdownHeading] {
    do {
      let markdown = try await Markdown(text: body)
      let root = await markdown.parse()
      let syntaxHeadings = root.children.compactMap { $0 as? Heading }
      let lines = body.components(separatedBy: "\n")
      var headings: [AnalyzedMarkdownHeading] = []
      var stack: [Int] = []

      for (index, heading) in syntaxHeadings.enumerated() {
        let level = heading.depth.rawValue
        while let candidate = stack.last, headings[candidate].level >= level {
          stack.removeLast()
        }
        let nextHeadingLine = index + 1 < syntaxHeadings.count
          ? syntaxHeadings[index + 1].position.start.line
          : lines.count + 1
        let contentStart = heading.position.start.line
        let contentEnd = max(contentStart, nextHeadingLine - 1)
        let directContent: String
        if contentStart < contentEnd, contentStart < lines.count {
          let upperBound = min(contentEnd, lines.count)
          directContent = lines[contentStart..<upperBound].joined(separator: "\n")
        } else {
          directContent = ""
        }
        headings.append(AnalyzedMarkdownHeading(
          text: HeadingTextExtractor.extractText(from: heading),
          level: level,
          line: heading.position.start.line,
          parentIndex: stack.last,
          directContentIsEmpty: directContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ))
        stack.append(headings.count - 1)
      }
      return headings
    } catch {
      return []
    }
  }

  private static func containsFrontmatterBlock(_ content: String) -> Bool {
    let parser = FrontMatterParser()
    var input = Substring(content)
    return (try? parser.parse(&input).format) != nil
  }

  private static func parseTypeHints(
    _ metadata: JSONValue
  ) -> (hints: [MarkdownTypeHint], diagnostics: [MarkdownDiagnostic]) {
    guard case .object(let object) = metadata, let rawHints = object["typeHints"] else {
      return ([], [])
    }
    guard case .array(let values) = rawHints else {
      return ([], [hintDiagnostic("$md-utils.typeHints must be an array")])
    }

    var hints: [MarkdownTypeHint] = []
    var diagnostics: [MarkdownDiagnostic] = []
    for (index, value) in values.enumerated() {
      switch value {
      case .string(let name) where name.isEmpty == false:
        hints.append(MarkdownTypeHint(name: name))
      case .object(let object):
        guard let name = object["name"]?.stringValue, name.isEmpty == false else {
          diagnostics.append(hintDiagnostic("$md-utils.typeHints[\(index)] requires a nonempty name"))
          continue
        }
        let version = object["version"]?.stringValue
        hints.append(MarkdownTypeHint(name: name, version: version))
      default:
        diagnostics.append(hintDiagnostic("$md-utils.typeHints[\(index)] must be a type name or object"))
      }
    }
    return (hints, diagnostics)
  }

  private static func parseDiagnostic(
    _ message: String,
    format: FrontMatterFormat?
  ) -> MarkdownDiagnostic {
    let formatName = format?.rawValue.uppercased() ?? "frontmatter"
    return MarkdownDiagnostic(
      code: format == .toml ? "record.frontmatter.invalid-toml" : "record.frontmatter.invalid-yaml",
      severity: .error,
      domain: .frontmatter,
      location: "frontmatter",
      message: "Invalid \(formatName): \(message)"
    )
  }

  private static func multipleBlocksDiagnostic(line: Int) -> MarkdownDiagnostic {
    MarkdownDiagnostic(
      code: "record.frontmatter.multiple-blocks",
      severity: .error,
      domain: .frontmatter,
      location: "frontmatter",
      message: "multiple frontmatter blocks; additional block opens at line \(line)"
    )
  }

  private static func hintDiagnostic(_ message: String) -> MarkdownDiagnostic {
    MarkdownDiagnostic(
      code: "type.hint.malformed",
      severity: .error,
      domain: .typeHint,
      location: "$md-utils.typeHints",
      message: message
    )
  }
}

private extension MarkdownRecordContentKind {
  var supportsMarkdownStructure: Bool {
    if case .markdown = self { return true }
    return false
  }
}
