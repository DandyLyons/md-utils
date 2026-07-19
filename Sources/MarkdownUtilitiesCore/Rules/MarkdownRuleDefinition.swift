import Foundation

/// Selects records by portable predicates and confirmed Markdown types.
public struct MarkdownRuleApplicability: Equatable, Sendable {
  public var predicates: [MarkdownConstraint]
  public var anyTypes: [MarkdownTypeName]
  public var allTypes: [MarkdownTypeName]

  public init(
    predicates: [MarkdownConstraint] = [],
    anyTypes: [MarkdownTypeName] = [],
    allTypes: [MarkdownTypeName] = []
  ) {
    self.predicates = predicates
    self.anyTypes = anyTypes
    self.allTypes = allTypes
  }
}

/// A reusable rule that keeps applicability separate from policy checks.
public struct MarkdownRuleDefinition: Equatable, Sendable {
  public var name: String
  public var applicability: MarkdownRuleApplicability
  public var frontmatter: MarkdownFrontmatterDefinition
  public var requirements: MarkdownConstraintGroup

  public init(
    name: String,
    applicability: MarkdownRuleApplicability = MarkdownRuleApplicability(),
    frontmatter: MarkdownFrontmatterDefinition = MarkdownFrontmatterDefinition(),
    requirements: MarkdownConstraintGroup = MarkdownConstraintGroup()
  ) {
    self.name = name
    self.applicability = applicability
    self.frontmatter = frontmatter
    self.requirements = requirements
  }
}

/// Structured result of matching and checking one rule against one record.
public struct MarkdownRuleAssessment: Equatable, Sendable {
  public var ruleName: String
  public var applicable: Bool
  public var applicabilityDiagnostics: [MarkdownDiagnostic]
  public var diagnostics: [MarkdownDiagnostic]

  public init(
    ruleName: String,
    applicable: Bool,
    applicabilityDiagnostics: [MarkdownDiagnostic] = [],
    diagnostics: [MarkdownDiagnostic] = []
  ) {
    self.ruleName = ruleName
    self.applicable = applicable
    self.applicabilityDiagnostics = applicabilityDiagnostics
    self.diagnostics = diagnostics
  }

  public var passes: Bool {
    applicable && diagnostics.contains(where: { $0.severity == .error }) == false
  }
}

/// Matches rules and evaluates their checks without filesystem or CLI dependencies.
public struct MarkdownRuleChecker: Sendable {
  public var typeRegistry: MarkdownTypeRegistry?

  public init(typeRegistry: MarkdownTypeRegistry? = nil) {
    self.typeRegistry = typeRegistry
  }

  public func assess(
    _ record: MarkdownRecord,
    against rule: MarkdownRuleDefinition
  ) async throws -> MarkdownRuleAssessment {
    let applicability = try await assessApplicability(record, rule: rule)
    guard applicability.matches else {
      return MarkdownRuleAssessment(
        ruleName: rule.name,
        applicable: false,
        applicabilityDiagnostics: applicability.diagnostics
      )
    }

    let checkDefinition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: syntheticName(rule.name, suffix: "checks")),
      version: "rule",
      frontmatter: rule.frontmatter,
      body: rule.requirements,
      context: MarkdownConstraintGroup()
    )
    let registry = try MarkdownTypeRegistry(definitions: [checkDefinition])
    let assessment = try await MarkdownTypeChecker(registry: registry).assess(record, as: checkDefinition.name)
    return MarkdownRuleAssessment(
      ruleName: rule.name,
      applicable: true,
      diagnostics: assessment.diagnostics
    )
  }

  public func isApplicable(
    _ record: MarkdownRecord,
    to rule: MarkdownRuleDefinition
  ) async throws -> Bool {
    try await assessApplicability(record, rule: rule).matches
  }

  private func assessApplicability(
    _ record: MarkdownRecord,
    rule: MarkdownRuleDefinition
  ) async throws -> (matches: Bool, diagnostics: [MarkdownDiagnostic]) {
    var diagnostics: [MarkdownDiagnostic] = []

    if rule.applicability.predicates.isEmpty == false {
      let bodyPredicates = rule.applicability.predicates.filter { constraint in
        if case .path = constraint.predicate { return false }
        return true
      }
      let contextPredicates = rule.applicability.predicates.filter { constraint in
        if case .path = constraint.predicate { return true }
        return false
      }
      let definition = MarkdownTypeDefinition(
        name: MarkdownTypeName(rawValue: syntheticName(rule.name, suffix: "applicability")),
        version: "rule",
        body: MarkdownConstraintGroup(requirements: bodyPredicates),
        context: MarkdownConstraintGroup(requirements: contextPredicates)
      )
      let registry = try MarkdownTypeRegistry(definitions: [definition])
      let assessment = try await MarkdownTypeChecker(registry: registry).assess(record, as: definition.name)
      diagnostics.append(contentsOf: assessment.errors.filter { diagnostic in
        diagnostic.code != "record.frontmatter.invalid-yaml"
      })
    }

    if rule.applicability.anyTypes.isEmpty == false || rule.applicability.allTypes.isEmpty == false {
      guard let typeRegistry else {
        throw MarkdownRuleCheckerError.typeRegistryRequired(rule.name)
      }
      let checker = MarkdownTypeChecker(registry: typeRegistry)
      let assessments = await checker.assessAll(record)
      let conforming = Set(assessments.filter(\.conforms).map(\.type))
      if rule.applicability.anyTypes.isEmpty == false,
         rule.applicability.anyTypes.contains(where: conforming.contains) == false {
        diagnostics.append(MarkdownDiagnostic(
          code: "rule.applicability.type-any",
          severity: .error,
          domain: .record,
          location: "record.types",
          message: "Record does not conform to any type selected by rule \(rule.name)"
        ))
      }
      let missingAll = rule.applicability.allTypes.filter { conforming.contains($0) == false }
      if missingAll.isEmpty == false {
        diagnostics.append(MarkdownDiagnostic(
          code: "rule.applicability.type-all",
          severity: .error,
          domain: .record,
          location: "record.types",
          message: "Record does not conform to required type(s): \(missingAll.map(\.rawValue).joined(separator: ", "))"
        ))
      }
    }

    return (diagnostics.isEmpty, diagnostics)
  }

  private func syntheticName(_ ruleName: String, suffix: String) -> String {
    let safeName = ruleName.map { character in
      character.isLetter || character.isNumber ? character : "-"
    }
    return "__rule-\(String(safeName))-\(suffix)"
  }
}

/// Errors raised before a portable rule can be assessed.
public enum MarkdownRuleCheckerError: Error, Equatable, LocalizedError {
  case typeRegistryRequired(String)

  public var errorDescription: String? {
    switch self {
    case .typeRegistryRequired(let ruleName):
      return "Rule \(ruleName) references Markdown types but no type registry was supplied"
    }
  }
}
