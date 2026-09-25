import MarkdownUtilitiesCore
import SwiftKnap

/// Reuses the public Swift engine; runtime management belongs entirely to SwiftKnap.
actor KnapRendering {
  static let shared = KnapRendering()
  private var engine: KnapEngine?

  func render(_ template: String, input: MarkdownTemplateInput, limits: RenderLimits) async throws -> RenderResult {
    var variables = ["data": try Self.value(input.data)]
    if let frontmatter = input.frontmatter {
      variables["frontmatter"] = try Self.value(.object(frontmatter))
    }
    let renderer: KnapEngine
    if let engine { renderer = engine }
    else {
      renderer = try KnapEngine()
      engine = renderer
    }
    return try await renderer.render(template, variables: variables,
      options: .init(trimOutput: false, limits: limits))
  }

  private static func value(_ input: JSONValue) throws -> TemplateValue {
    switch input {
    case .null: return .null
    case .boolean(let value): return .bool(value)
    case .string(let value): return .string(value)
    case .number(let value): return .number(value)
    case .integer(let value):
      guard (-9_007_199_254_740_991...9_007_199_254_740_991).contains(value) else {
        throw MarkdownTemplateError(stage: .input,
          message: "Integer \(value) exceeds Knap's exact integer range; supply it as a string.")
      }
      return .number(Double(value))
    case .array(let values): return .array(try values.map(Self.value))
    case .object(let values): return .object(try values.mapValues(Self.value))
    }
  }

  static func diagnostic(_ value: Diagnostic, severity: MarkdownDiagnosticSeverity) -> MarkdownDiagnostic {
    MarkdownDiagnostic(code: "template.knap.\(value.code)", severity: severity, domain: .body,
      constraintID: value.filter, location: "template:\(value.line):\(value.column)", message: value.message)
  }
}
