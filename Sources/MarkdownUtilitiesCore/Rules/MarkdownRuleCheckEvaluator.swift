import Foundation
import JSONSchema

/// Portable checks used by reusable rules and legacy rule adapters.
public enum MarkdownRuleCheck: Equatable, Sendable {
  case frontmatterSchema(id: String, schema: JSONValue)
  case requiredHeading(id: String, heading: String)
  case maxBodyLines(id: String, maximum: Int)
  case maxBodyWords(id: String, maximum: Int)
}

/// Explicit content supplied to the synchronous portable rule-check evaluator.
public struct MarkdownRuleCheckInput: Equatable, Sendable {
  public var frontmatter: JSONValue?
  public var body: String

  public init(frontmatter: JSONValue?, body: String) {
    self.frontmatter = frontmatter
    self.body = body
  }
}

/// Evaluates already-selected rule checks without filesystem or CLI dependencies.
public enum MarkdownRuleCheckEvaluator {
  public static func evaluate(
    _ checks: [MarkdownRuleCheck],
    input: MarkdownRuleCheckInput
  ) throws -> [MarkdownDiagnostic] {
    var diagnostics: [MarkdownDiagnostic] = []
    for check in checks {
      switch check {
      case .frontmatterSchema(let id, let schemaValue):
        guard let frontmatter = input.frontmatter,
              let schema = schemaValue.foundationValue as? [String: Any] else { continue }
        let result = try JSONSchema.validate(frontmatter.foundationValue, schema: schema)
        if result.valid == false {
          diagnostics.append(contentsOf: result.errors?.map { error in
            MarkdownDiagnostic(
              code: "rule.frontmatter.schema",
              severity: .error,
              domain: .frontmatter,
              constraintID: id,
              location: pointerDisplayPath(error.instanceLocation.path),
              message: error.description
            )
          } ?? [MarkdownDiagnostic(
            code: "rule.frontmatter.schema",
            severity: .error,
            domain: .frontmatter,
            constraintID: id,
            location: "frontmatter",
            message: "schema validation failed"
          )])
        }
      case .requiredHeading(let id, let heading):
        guard headingTexts(in: input.body).contains(heading) == false else { continue }
        diagnostics.append(MarkdownDiagnostic(
          code: "rule.body.required-heading",
          severity: .error,
          domain: .body,
          constraintID: id,
          location: "heading",
          message: "required heading \"\(heading)\" not found"
        ))
      case .maxBodyLines(let id, let maximum):
        let count = input.body.isEmpty ? 0 : input.body.components(separatedBy: "\n").count
        guard count > maximum else { continue }
        diagnostics.append(MarkdownDiagnostic(
          code: "rule.body.max-lines",
          severity: .error,
          domain: .body,
          constraintID: id,
          location: "body.lines",
          message: "line count \(count) exceeds maximum \(maximum)"
        ))
      case .maxBodyWords(let id, let maximum):
        let count = input.body.split(whereSeparator: \.isWhitespace).count
        guard count > maximum else { continue }
        diagnostics.append(MarkdownDiagnostic(
          code: "rule.body.max-words",
          severity: .error,
          domain: .body,
          constraintID: id,
          location: "body.words",
          message: "word count \(count) exceeds maximum \(maximum)"
        ))
      }
    }
    return diagnostics
  }

  private static func headingTexts(in body: String) -> [String] {
    body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("#") else { return nil }
      let hashes = trimmed.prefix { $0 == "#" }
      guard (1...6).contains(hashes.count) else { return nil }
      let afterHashes = trimmed.dropFirst(hashes.count)
      guard afterHashes.first == " " else { return nil }
      return String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
  }

  private static func pointerDisplayPath(_ pointer: String) -> String {
    if pointer.isEmpty || pointer == "/" { return "frontmatter" }
    let trimmed = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
    return trimmed.replacingOccurrences(of: "/", with: ".")
  }
}
