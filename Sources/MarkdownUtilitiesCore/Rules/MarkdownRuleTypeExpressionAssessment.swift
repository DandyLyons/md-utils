import Foundation

/// An evaluated type-expression branch with original diagnostics and resource provenance.
public struct MarkdownRuleTypeExpressionAssessment: Equatable, Sendable {
  public let location: String
  public let reference: String?
  public let status: MarkdownRuleEvidenceStatus
  public let assessment: MarkdownTypeAssessment?
  public let children: [Self]

  /// Deterministic branch-by-branch explanation without discarding negative evidence.
  public var explanation: [String] {
    ["\(location)\(reference.map { " (\($0))" } ?? ""): \(status.rawValue)"]
      + (assessment?.diagnostics.map { "\(location): \($0.code): \($0.message)" } ?? [])
      + children.flatMap(\.explanation)
  }

  /// Only diagnostics contributing to this outcome; detailed children retain all evidence.
  public var diagnostics: [MarkdownDiagnostic] {
    if let assessment { return assessment.diagnostics }
    if status == .matched {
      // Negative branches do not propose repairs to make their excluded types conform.
      return children.filter { $0.status == .matched }.flatMap(\.diagnostics)
        .filter { $0.severity != .error }
    }
    return [MarkdownDiagnostic(
      code: status == .unavailable ? "rule.types.evaluation-error" : "rule.types.nonconformance",
      severity: .error, domain: .record, constraintID: location, location: location,
      message: status == .unavailable
        ? "Type expression could not be evaluated; inspect branch evidence"
        : "Type expression did not conform; inspect branch evidence"
    )]
  }
}

extension MarkdownRuleChecker {
  package func assessTypes(
    _ expression: MarkdownRuleTypeExpression,
    bindings: [String: MarkdownTypeName],
    record: AnalyzedMarkdownRecord,
    location: String = "types"
  ) throws -> MarkdownRuleTypeExpressionAssessment {
    try Task.checkCancellation()
    if case .reference(let reference) = expression {
      guard let name = bindings[reference], let types = registry.typeRegistry else {
        throw MarkdownTypeCheckerError.unknownType(reference)
      }
      let assessment = try MarkdownTypeChecker(registry: types).assess(record, as: name)
      let evaluationError = assessment.diagnostics.contains {
        $0.severity == .error && (
          record.parseDiagnostics.contains($0)
          || $0.code.hasSuffix(".engine-error")
          || $0.code.hasSuffix(".unavailable")
          || $0.code == "record.frontmatter.syntax-unavailable"
          || $0.code == "record.markdown-structure.unsupported"
        )
      }
      return .init(location: location, reference: reference,
        status: evaluationError ? .unavailable : (assessment.conforms ? .matched : .notMatched),
        assessment: assessment, children: [])
    }
    let operands: [MarkdownRuleTypeExpression]
    let key: String
    switch expression {
    case .allOf(let values): operands = values; key = "allOf"
    case .anyOf(let values): operands = values; key = "anyOf"
    case .oneOf(let values): operands = values; key = "oneOf"
    case .not(let value): operands = [value]; key = "not"
    case .reference(let reference): throw MarkdownTypeCheckerError.unknownType(reference)
    }
    let children = try operands.enumerated().map { index, operand in
      try assessTypes(operand, bindings: bindings, record: record,
        location: key == "not" ? location + ".not" : "\(location).\(key)[\(index)]")
    }
    let values = children.map(\.status)
    let status: MarkdownRuleEvidenceStatus
    switch expression {
    case .allOf: status = MarkdownRuleMatchComposition.all(values)
    case .anyOf: status = MarkdownRuleMatchComposition.any(values)
    case .oneOf: status = MarkdownRuleMatchComposition.one(values)
    case .not: status = MarkdownRuleMatchComposition.not(values.first ?? .unavailable)
    case .reference(let reference): throw MarkdownTypeCheckerError.unknownType(reference)
    }
    return .init(location: location, reference: nil, status: status, assessment: nil, children: children)
  }
}
