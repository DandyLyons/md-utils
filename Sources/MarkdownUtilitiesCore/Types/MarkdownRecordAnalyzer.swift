import Foundation
import MarkdownSyntax

struct AnalyzedMarkdownRecord {
  var record: MarkdownRecord
  var body: String
  var hasFrontmatter: Bool
  var userFrontmatter: [String: JSONValue]?
  var systemTypeHints: [MarkdownTypeHint]
  var headings: [AnalyzedMarkdownHeading]
  var parseDiagnostics: [MarkdownDiagnostic]

  var allTypeHints: [MarkdownTypeHint] {
    var result: [MarkdownTypeHint] = []
    var seen: Set<MarkdownTypeHint> = []
    for hint in systemTypeHints + record.context.typeHints where seen.insert(hint).inserted {
      result.append(hint)
    }
    return result
  }
}

struct AnalyzedMarkdownHeading {
  var text: String
  var level: Int
  var line: Int
  var parentIndex: Int?
  var directContentIsEmpty: Bool
}

enum MarkdownRecordAnalyzer {
  static func analyze(_ record: MarkdownRecord) async -> AnalyzedMarkdownRecord {
    let parser = FrontMatterParser()
    var input = Substring(record.content)
    let parts: (rawFrontMatter: String, body: String)
    do {
      parts = try parser.parse(&input)
    } catch {
      return AnalyzedMarkdownRecord(
        record: record,
        body: record.content,
        hasFrontmatter: containsFrontmatterBlock(record.content),
        userFrontmatter: nil,
        systemTypeHints: [],
        headings: await analyzeHeadings(in: record.content),
        parseDiagnostics: [parseDiagnostic(error.localizedDescription)]
      )
    }

    let hasPhysicalFrontmatter = containsFrontmatterBlock(record.content)
    var userFrontmatter: [String: JSONValue]?
    var hints: [MarkdownTypeHint] = []
    var diagnostics: [MarkdownDiagnostic] = []

    if hasPhysicalFrontmatter {
      do {
        let mapping = try YAMLConversion.parse(parts.rawFrontMatter)
        let dynamicValue = try YAMLConversion.safeNodeToSwiftValue(.mapping(mapping))
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
        diagnostics.append(parseDiagnostic(error.localizedDescription))
      }
    }

    return AnalyzedMarkdownRecord(
      record: record,
      body: parts.body,
      hasFrontmatter: hasPhysicalFrontmatter,
      userFrontmatter: userFrontmatter,
      systemTypeHints: hints,
      headings: await analyzeHeadings(in: parts.body),
      parseDiagnostics: diagnostics
    )
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
    guard content.starts(with: "---\n") else { return false }
    let remaining = content.dropFirst(4)
    return remaining == "---" || remaining.hasPrefix("---\n") || remaining.contains("\n---\n")
      || remaining.hasSuffix("\n---")
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

  private static func parseDiagnostic(_ message: String) -> MarkdownDiagnostic {
    MarkdownDiagnostic(
      code: "record.frontmatter.invalid-yaml",
      severity: .error,
      domain: .frontmatter,
      location: "frontmatter",
      message: "Invalid YAML: \(message)"
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
