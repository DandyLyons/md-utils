import Foundation

/// Supplies compilation and evaluation for rule query languages outside portable Core.
public protocol MarkdownRuleQueryCapabilityProvider: Sendable {
  var capabilities: Set<MarkdownRuleRuntimeCapability> { get }
  func validateJMESPath(_ expression: String) throws
  func evaluateJMESPath(_ expression: String, frontmatter: JSONValue) throws -> JSONValue?
}

/// Stable categories produced while compiling normalized rules.
public enum MarkdownRuleCompilationDiagnosticCode: String, Codable, Equatable, Sendable {
  case invalidName = "rule.name.invalid"
  case duplicateName = "rule.name.duplicate"
  case duplicateIdentifier = "rule.identifier.duplicate"
  case invalidOperand = "rule.operand.invalid"
  case missingCapability = "rule.capability.missing"
  case missingType = "rule.type.missing"
  case unresolvedSchema = "rule.schema.unresolved"
  case unsupportedFeature = "rule.feature.unsupported"
}

/// One deterministic rule-compilation problem.
public struct MarkdownRuleCompilationDiagnostic: Codable, Equatable, Sendable {
  public var code: MarkdownRuleCompilationDiagnosticCode
  public var location: String
  public var message: String

  public init(
    code: MarkdownRuleCompilationDiagnosticCode,
    location: String,
    message: String
  ) {
    self.code = code
    self.location = location
    self.message = message
  }
}

/// All diagnostics from one failed rule-compilation pass.
public struct MarkdownRuleCompilationError: Error, Codable, Equatable, Sendable, LocalizedError {
  public var diagnostics: [MarkdownRuleCompilationDiagnostic]

  public init(diagnostics: [MarkdownRuleCompilationDiagnostic]) {
    self.diagnostics = diagnostics.sorted {
      ($0.location, $0.code.rawValue, $0.message) < ($1.location, $1.code.rawValue, $1.message)
    }
  }

  public var errorDescription: String? {
    diagnostics.map { "\($0.location): \($0.message)" }.joined(separator: "; ")
  }
}

/// A validated rule whose schema resources and runtime needs are resolved.
public struct CompiledMarkdownRule: Sendable {
  public let definition: MarkdownRuleDefinition
  public let requiredCapabilities: Set<MarkdownRuleRuntimeCapability>
  package let analysisRequirements: MarkdownRecordAnalysisRequirements
  package let resolvedSchemas: [String: JSONValue]

  package init(
    definition: MarkdownRuleDefinition,
    requiredCapabilities: Set<MarkdownRuleRuntimeCapability>,
    analysisRequirements: MarkdownRecordAnalysisRequirements,
    resolvedSchemas: [String: JSONValue]
  ) {
    self.definition = definition
    self.requiredCapabilities = requiredCapabilities
    self.analysisRequirements = analysisRequirements
    self.resolvedSchemas = resolvedSchemas
  }
}

/// An immutable collection of compiled rules and their evaluation dependencies.
///
/// See <doc:CompilingMarkdownRules> for the compile-once lifecycle.
public struct MarkdownRuleRegistry: Sendable {
  private let rulesByName: [String: CompiledMarkdownRule]
  package let typeRegistry: MarkdownTypeRegistry?
  package let queryProvider: (any MarkdownRuleQueryCapabilityProvider)?

  package init(
    rules: [CompiledMarkdownRule],
    typeRegistry: MarkdownTypeRegistry?,
    queryProvider: (any MarkdownRuleQueryCapabilityProvider)?
  ) {
    self.rulesByName = Dictionary(uniqueKeysWithValues: rules.map { ($0.definition.name, $0) })
    self.typeRegistry = typeRegistry
    self.queryProvider = queryProvider
  }

  /// Compiled definitions ordered by case-sensitive rule name.
  public var definitions: [MarkdownRuleDefinition] {
    rulesByName.values.map(\.definition).sorted { $0.name < $1.name }
  }

  /// Returns a compiled rule by its case-sensitive name.
  public func rule(named name: String) -> CompiledMarkdownRule? {
    rulesByName[name]
  }
}

/// Validates normalized rules against the facilities supplied by one runtime.
///
/// See <doc:CompilingMarkdownRules> and <doc:RuleRuntimeCapabilities>.
public struct MarkdownRuleCompiler: Sendable {
  public var capabilities: Set<MarkdownRuleRuntimeCapability>
  public var typeRegistry: MarkdownTypeRegistry?
  public var schemaProvider: (any MarkdownSchemaResourceProvider)?
  public var queryProvider: (any MarkdownRuleQueryCapabilityProvider)?

  public init(
    capabilities: Set<MarkdownRuleRuntimeCapability> = [],
    typeRegistry: MarkdownTypeRegistry? = nil,
    schemaProvider: (any MarkdownSchemaResourceProvider)? = nil,
    queryProvider: (any MarkdownRuleQueryCapabilityProvider)? = nil
  ) {
    self.capabilities = capabilities.union(queryProvider?.capabilities ?? [])
    self.typeRegistry = typeRegistry
    self.schemaProvider = schemaProvider
    self.queryProvider = queryProvider
  }

  /// Compiles all definitions or reports every independently discoverable problem.
  public func compile(_ definitions: [MarkdownRuleDefinition]) throws -> MarkdownRuleRegistry {
    var diagnostics: [MarkdownRuleCompilationDiagnostic] = []
    var compiled: [CompiledMarkdownRule] = []
    let duplicateNames = duplicates(definitions.map(\.name))

    for (index, definition) in definitions.enumerated() {
      let location = "rules[\(index)]"
      var ruleDiagnostics: [MarkdownRuleCompilationDiagnostic] = []
      if definition.name.isEmpty
        || definition.name.trimmingCharacters(in: .whitespacesAndNewlines) != definition.name {
        ruleDiagnostics.append(diagnostic(
          .invalidName,
          "\(location).name",
          "Rule names must be nonempty and cannot have surrounding whitespace"
        ))
      }
      if duplicateNames.contains(definition.name) {
        ruleDiagnostics.append(diagnostic(
          .duplicateName,
          "\(location).name",
          "Rule name \"\(definition.name)\" is configured more than once"
        ))
      }

      let identifiers = definition.applicability.requirements.map(\.id) + definition.checks.map(\.id)
      for identifier in duplicates(identifiers).sorted() {
        ruleDiagnostics.append(diagnostic(
          .duplicateIdentifier,
          location,
          "Rule \"\(definition.name)\" contains duplicate identifier \"\(identifier)\""
        ))
      }

      for type in definition.applicability.anyTypes + definition.applicability.allTypes {
        if typeRegistry?.definition(named: type) == nil {
          ruleDiagnostics.append(diagnostic(
            .missingType,
            "\(location).applicability.types",
            "Rule \"\(definition.name)\" references unavailable Markdown type \"\(type.rawValue)\""
          ))
        }
      }

      var requiredCapabilities: Set<MarkdownRuleRuntimeCapability> = []
      for (requirementIndex, requirement) in definition.applicability.requirements.enumerated() {
        let requirementLocation = "\(location).applicability.requirements[\(requirementIndex)]"
        validate(
          requirement.predicate,
          location: requirementLocation,
          requiredCapabilities: &requiredCapabilities,
          diagnostics: &ruleDiagnostics
        )
      }

      for capability in requiredCapabilities where capabilities.contains(capability) == false {
        ruleDiagnostics.append(diagnostic(
          .missingCapability,
          "\(location).capabilities",
          "Rule \"\(definition.name)\" requires runtime capability \"\(capability.rawValue)\""
        ))
      }

      var resolvedSchemas: [String: JSONValue] = [:]
      let schemaChecks = definition.checks.filter { check in
        if case .frontmatterSchema = check.predicate { return true }
        return false
      }
      if schemaChecks.isEmpty == false {
        let sources = schemaChecks.compactMap { check -> MarkdownJSONSchemaSource? in
          guard case .frontmatterSchema(let source, _) = check.predicate else { return nil }
          return source
        }
        do {
          let syntheticName = MarkdownTypeName(rawValue: syntheticTypeName(definition.name))
          let synthetic = MarkdownTypeDefinition(
            name: syntheticName,
            version: "rule",
            frontmatter: MarkdownFrontmatterDefinition(presence: .optional, schemas: sources),
            source: definition.source
          )
          let registry = try MarkdownTypeRegistry(
            definitions: [synthetic],
            schemaProvider: schemaProvider
          )
          let schemas = registry.resolvedSchemas(for: syntheticName)
          for (check, schema) in zip(schemaChecks, schemas) {
            resolvedSchemas[check.id] = schema
          }
        } catch {
          ruleDiagnostics.append(diagnostic(
            .unresolvedSchema,
            "\(location).checks",
            error.localizedDescription
          ))
        }
      }

      diagnostics.append(contentsOf: ruleDiagnostics)
      if ruleDiagnostics.isEmpty {
        compiled.append(CompiledMarkdownRule(
          definition: definition,
          requiredCapabilities: requiredCapabilities,
          analysisRequirements: analysisRequirements(for: definition),
          resolvedSchemas: resolvedSchemas
        ))
      }
    }

    guard diagnostics.isEmpty else {
      throw MarkdownRuleCompilationError(diagnostics: diagnostics)
    }
    return MarkdownRuleRegistry(
      rules: compiled,
      typeRegistry: typeRegistry,
      queryProvider: queryProvider
    )
  }

  private func analysisRequirements(
    for definition: MarkdownRuleDefinition
  ) -> MarkdownRecordAnalysisRequirements {
    var result: MarkdownRecordAnalysisRequirements = []
    for requirement in definition.applicability.requirements {
      result.formUnion(.required(by: requirement.predicate))
    }
    for check in definition.checks {
      if case .markdown(let predicate) = check.predicate {
        result.formUnion(.required(by: predicate))
      }
    }

    let typeNames = Set(definition.applicability.anyTypes + definition.applicability.allTypes)
    for typeName in typeNames {
      guard let type = typeRegistry?.definition(named: typeName) else { continue }
      let constraints = type.body.requirements + type.body.recommendations
        + type.context.requirements + type.context.recommendations
      for constraint in constraints {
        result.formUnion(.required(by: constraint.predicate))
      }
    }
    return result
  }

  private func validate(
    _ predicate: MarkdownRulePredicate,
    location: String,
    requiredCapabilities: inout Set<MarkdownRuleRuntimeCapability>,
    diagnostics: inout [MarkdownRuleCompilationDiagnostic]
  ) {
    switch predicate {
    case .modifiedAfter, .modifiedBefore:
      requiredCapabilities.insert(.modificationDate)
    case .frontmatterJMESPath(let expression):
      requiredCapabilities.insert(.frontmatterJMESPath)
      guard let queryProvider else { return }
      do {
        try queryProvider.validateJMESPath(expression)
      } catch {
        diagnostics.append(diagnostic(.invalidOperand, location, error.localizedDescription))
      }
    case .pathRegularExpression(let pattern),
         .headingRegularExpression(let pattern),
         .bodyRegularExpression(let pattern):
      validateRegularExpression(pattern, location: location, diagnostics: &diagnostics)
    case .frontmatterField(_, let operation):
      if case .regularExpression(let pattern) = operation {
        validateRegularExpression(pattern, location: location, diagnostics: &diagnostics)
      }
    case .extensionIn(let extensions):
      if extensions.isEmpty || extensions.contains(where: { $0.isEmpty }) {
        diagnostics.append(diagnostic(
          .invalidOperand,
          location,
          "Extension predicates require at least one nonempty extension"
        ))
      }
    case .bodyLineCount(let range), .bodyWordCount(let range):
      validate(range, location: location, diagnostics: &diagnostics)
    case .markdown, .filenameEquals, .heading, .section,
         .bodyContains, .wikilink:
      break
    }
  }

  private func validate(
    _ range: MarkdownRuleIntegerRange,
    location: String,
    diagnostics: inout [MarkdownRuleCompilationDiagnostic]
  ) {
    if range.minimum == nil && range.maximum == nil {
      diagnostics.append(diagnostic(.invalidOperand, location, "Count ranges require a minimum or maximum"))
    }
    if let minimum = range.minimum, minimum < 0 {
      diagnostics.append(diagnostic(.invalidOperand, location, "Count range minimum must be nonnegative"))
    }
    if let maximum = range.maximum, maximum < 0 {
      diagnostics.append(diagnostic(.invalidOperand, location, "Count range maximum must be nonnegative"))
    }
    if let minimum = range.minimum, let maximum = range.maximum, minimum > maximum {
      diagnostics.append(diagnostic(.invalidOperand, location, "Count range minimum cannot exceed maximum"))
    }
  }

  private func validateRegularExpression(
    _ pattern: String,
    location: String,
    diagnostics: inout [MarkdownRuleCompilationDiagnostic]
  ) {
    do {
      _ = try NSRegularExpression(pattern: pattern)
    } catch {
      diagnostics.append(diagnostic(.invalidOperand, location, "Invalid regular expression: \(error.localizedDescription)"))
    }
  }

  private func diagnostic(
    _ code: MarkdownRuleCompilationDiagnosticCode,
    _ location: String,
    _ message: String
  ) -> MarkdownRuleCompilationDiagnostic {
    MarkdownRuleCompilationDiagnostic(code: code, location: location, message: message)
  }

  private func duplicates<T: Hashable>(_ values: [T]) -> Set<T> {
    var seen: Set<T> = []
    var duplicates: Set<T> = []
    for value in values where seen.insert(value).inserted == false {
      duplicates.insert(value)
    }
    return duplicates
  }

  private func syntheticTypeName(_ ruleName: String) -> String {
    let safeName = ruleName.map { $0.isLetter || $0.isNumber ? $0 : "-" }
    return "__compiled-rule-\(String(safeName))"
  }
}
