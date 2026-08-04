import Foundation
import JSONSchema

/// Matches and checks records using one compiled rule registry.
public struct MarkdownRuleChecker: Sendable {
  public let registry: MarkdownRuleRegistry

  public init(registry: MarkdownRuleRegistry) {
    self.registry = registry
  }

  /// Assesses a record against the compiled rule with the supplied name.
  public func assess(
    _ record: MarkdownRecord,
    ruleNamed name: String
  ) async throws -> MarkdownRuleAssessment {
    guard let rule = registry.rule(named: name) else {
      throw MarkdownRuleCheckerError.unknownRule(name)
    }
    return try assess(
      await MarkdownRecordAnalyzer.analyze(
        record,
        requirements: analysisRequirements(for: rule)
      ),
      against: rule
    )
  }

  /// Returns whether a record is selected by a compiled rule.
  public func isApplicable(
    _ record: MarkdownRecord,
    toRuleNamed name: String
  ) async throws -> Bool {
    try await assess(record, ruleNamed: name).status != .notApplicable
  }

  /// Assesses parsed state shared by package subsystems.
  package func assess(
    _ record: AnalyzedMarkdownRecord,
    against rule: CompiledMarkdownRule
  ) throws -> MarkdownRuleAssessment {
    let applicability = try assessApplicability(record, rule: rule.definition)
    if applicability.unavailable {
      return MarkdownRuleAssessment(
        ruleName: rule.definition.name,
        status: .failed,
        evidence: applicability.evidence,
        applicabilityDiagnostics: applicability.diagnostics
      )
    }
    guard applicability.matches else {
      return MarkdownRuleAssessment(
        ruleName: rule.definition.name,
        status: .notApplicable,
        evidence: applicability.evidence,
        applicabilityDiagnostics: applicability.diagnostics
      )
    }

    var diagnostics: [MarkdownDiagnostic] = []
    var skippedChecks = 0
    for check in rule.definition.checks {
      switch check.predicate {
      case .frontmatterSchema(_, let presence):
        guard record.hasFrontmatter else {
          if presence == .optional {
            skippedChecks += 1
          } else {
            diagnostics.append(MarkdownDiagnostic(
              code: "frontmatter.presence.required",
              severity: check.severity,
              domain: .frontmatter,
              constraintID: check.id,
              location: "frontmatter",
              message: "required by rule \"\(rule.definition.name)\""
            ))
          }
          continue
        }
        if let parseError = record.parseDiagnostics.first(where: { $0.domain == .frontmatter }) {
          diagnostics.append(parseError)
          continue
        }
        guard let schemaValue = rule.resolvedSchemas[check.id],
              let schema = schemaValue.foundationValue as? [String: Any] else {
          diagnostics.append(MarkdownDiagnostic(
            code: "rule.frontmatter.schema-unavailable",
            severity: .error,
            domain: .frontmatter,
            constraintID: check.id,
            location: "frontmatter",
            message: "Compiled schema is unavailable"
          ))
          continue
        }
        let frontmatter = JSONValue.object(record.userFrontmatter ?? [:])
        do {
          let result = try JSONSchema.validate(frontmatter.foundationValue, schema: schema)
          if result.valid == false {
            let schemaDiagnostics = (result.errors ?? []).map { error in
              MarkdownDiagnostic(
                code: "rule.frontmatter.schema",
                severity: check.severity,
                domain: .frontmatter,
                constraintID: check.id,
                location: displayPath(error.instanceLocation.path),
                message: error.description
              )
            }
            diagnostics.append(contentsOf: schemaDiagnostics.isEmpty ? [MarkdownDiagnostic(
              code: "rule.frontmatter.schema",
              severity: check.severity,
              domain: .frontmatter,
              constraintID: check.id,
              location: "frontmatter",
              message: "schema validation failed"
            )] : schemaDiagnostics)
          }
        } catch {
          diagnostics.append(MarkdownDiagnostic(
            code: "rule.frontmatter.schema-engine",
            severity: .error,
            domain: .frontmatter,
            constraintID: check.id,
            location: "frontmatter",
            message: error.localizedDescription
          ))
        }
      case .markdown(let predicate):
        diagnostics.append(contentsOf: try assessMarkdownCheck(
          predicate,
          id: check.id,
          severity: check.severity,
          record: record,
          ruleName: rule.definition.name
        ))
      }
    }

    let hasErrors = diagnostics.contains { $0.severity == .error }
    let status: MarkdownRuleAssessmentStatus
    if hasErrors {
      status = .failed
    } else if rule.definition.checks.isEmpty == false && skippedChecks == rule.definition.checks.count {
      status = .skipped
    } else {
      status = .passed
    }
    return MarkdownRuleAssessment(
      ruleName: rule.definition.name,
      status: status,
      evidence: applicability.evidence,
      diagnostics: diagnostics
    )
  }

  /// Performs path-only narrowing without parsing record content.
  package func isPathCandidate(
    _ path: MarkdownRecordPath?,
    for rule: CompiledMarkdownRule
  ) -> Bool {
    isPathCandidate(path, for: rule.definition.applicability)
  }

  /// Returns the expensive derived record state needed to assess a compiled rule.
  package func analysisRequirements(
    for rule: CompiledMarkdownRule
  ) -> MarkdownRecordAnalysisRequirements {
    rule.analysisRequirements
  }

  private func assessApplicability(
    _ record: AnalyzedMarkdownRecord,
    rule: MarkdownRuleDefinition
  ) throws -> (
    matches: Bool,
    unavailable: Bool,
    evidence: [MarkdownRulePredicateEvidence],
    diagnostics: [MarkdownDiagnostic]
  ) {
    var evidence: [MarkdownRulePredicateEvidence] = []
    var diagnostics: [MarkdownDiagnostic] = []
    var matches = true
    var unavailable = false
    let path = record.record.context.path

    if rule.applicability.paths.isEmpty {
      evidence.append(MarkdownRulePredicateEvidence(
        id: "paths",
        status: .matched,
        message: "no path patterns configured"
      ))
    } else if let path,
              let pattern = rule.applicability.paths.first(where: path.matches(glob:)) {
      evidence.append(MarkdownRulePredicateEvidence(
        id: "paths",
        status: .matched,
        message: "path \"\(path.rawValue)\" matched \"\(pattern)\""
      ))
    } else {
      matches = false
      evidence.append(MarkdownRulePredicateEvidence(
        id: "paths",
        status: .notMatched,
        message: path.map { "path \"\($0.rawValue)\" did not match any configured path pattern" }
          ?? "logical path is unavailable"
      ))
    }

    if let path,
       let pattern = rule.applicability.excludePaths.first(where: path.matches(glob:)) {
      matches = false
      evidence.append(MarkdownRulePredicateEvidence(
        id: "excludePaths",
        status: .notMatched,
        message: "path \"\(path.rawValue)\" is excluded by \"\(pattern)\""
      ))
    }

    for requirement in rule.applicability.requirements {
      let result = try evaluate(requirement, record: record)
      evidence.append(result.evidence)
      switch result.evidence.status {
      case .matched:
        break
      case .notMatched:
        matches = false
      case .unavailable:
        unavailable = true
        diagnostics.append(result.diagnostic ?? MarkdownDiagnostic(
          code: "rule.applicability.context-unavailable",
          severity: .error,
          domain: .context,
          constraintID: requirement.id,
          location: "record.context",
          message: result.evidence.message
        ))
      }
    }

    if rule.applicability.anyTypes.isEmpty == false || rule.applicability.allTypes.isEmpty == false {
      guard let typeRegistry = registry.typeRegistry else {
        unavailable = true
        diagnostics.append(MarkdownDiagnostic(
          code: "rule.applicability.type-registry-unavailable",
          severity: .error,
          domain: .record,
          location: "record.types",
          message: "A Markdown type registry is required"
        ))
        return (matches, unavailable, evidence, diagnostics)
      }
      let assessments = MarkdownTypeChecker(registry: typeRegistry).assessAll(record)
      let conforming = Set(assessments.filter(\.conforms).map(\.type))
      if rule.applicability.anyTypes.isEmpty == false {
        let anyMatches = rule.applicability.anyTypes.contains(where: conforming.contains)
        if anyMatches == false { matches = false }
        evidence.append(MarkdownRulePredicateEvidence(
          id: "anyTypes",
          status: anyMatches ? .matched : .notMatched,
          message: anyMatches
            ? "record conforms to a selected Markdown type"
            : "record does not conform to any selected Markdown type"
        ))
      }
      if rule.applicability.allTypes.isEmpty == false {
        let missing = rule.applicability.allTypes.filter { conforming.contains($0) == false }
        if missing.isEmpty == false { matches = false }
        evidence.append(MarkdownRulePredicateEvidence(
          id: "allTypes",
          status: missing.isEmpty ? .matched : .notMatched,
          message: missing.isEmpty
            ? "record conforms to all selected Markdown types"
            : "record does not conform to required type(s): \(missing.map(\.rawValue).joined(separator: ", "))"
        ))
      }
    }

    return (matches, unavailable, evidence, diagnostics)
  }

  private func evaluate(
    _ requirement: MarkdownRuleRequirement,
    record: AnalyzedMarkdownRecord
  ) throws -> (evidence: MarkdownRulePredicateEvidence, diagnostic: MarkdownDiagnostic?) {
    let predicate = requirement.predicate
    let matched: Bool
    let unavailableMessage: String?
    let detail: String

    switch predicate {
    case .markdown(let markdownPredicate):
      let diagnostics = try assessMarkdownCheck(
        markdownPredicate,
        id: requirement.id,
        severity: .error,
        record: record,
        ruleName: "applicability"
      )
      matched = diagnostics.isEmpty
      unavailableMessage = diagnostics.first(where: { $0.code.hasSuffix("unavailable") })?.message
      detail = matched ? "Markdown predicate matched" : diagnostics.first?.message ?? "Markdown predicate did not match"
    case .pathRegularExpression(let pattern):
      guard let path = record.record.context.path else {
        return unavailable(requirement.id, "A logical path is required to evaluate pathRegex")
      }
      matched = regularExpression(pattern, matches: path.rawValue)
      unavailableMessage = nil
      detail = matched ? "path matched regular expression" : "path did not match regular expression"
    case .filenameEquals(let filename):
      guard let path = record.record.context.path else {
        return unavailable(requirement.id, "A logical path is required to evaluate filenameEquals")
      }
      matched = path.rawValue.split(separator: "/").last.map(String.init) == filename
      unavailableMessage = nil
      detail = matched ? "filename matched \"\(filename)\"" : "filename did not equal \"\(filename)\""
    case .extensionIn(let extensions):
      guard let path = record.record.context.path else {
        return unavailable(requirement.id, "A logical path is required to evaluate extensionIn")
      }
      let filename = path.rawValue.split(separator: "/").last.map(String.init) ?? ""
      let ext = filename.split(separator: ".").last.map { String($0).lowercased() }
      let normalizedExtensions = extensions.map { $0.lowercased() }
      matched = ext.map { normalizedExtensions.contains($0) } ?? false
      unavailableMessage = nil
      detail = matched ? "file extension matched" : "file extension did not match"
    case .modifiedAfter(let operand):
      guard let date = record.record.context.modificationDate else {
        return unavailable(requirement.id, "A modification date is required to evaluate modifiedAfter")
      }
      matched = compare(MarkdownRuleDateTimeLiteral(date: date), operand: operand) == .orderedDescending
      unavailableMessage = nil
      detail = matched ? "modification date is after \(operand.rawValue)" : "modification date is not after \(operand.rawValue)"
    case .modifiedBefore(let operand):
      guard let date = record.record.context.modificationDate else {
        return unavailable(requirement.id, "A modification date is required to evaluate modifiedBefore")
      }
      matched = compare(MarkdownRuleDateTimeLiteral(date: date), operand: operand) == .orderedAscending
      unavailableMessage = nil
      detail = matched ? "modification date is before \(operand.rawValue)" : "modification date is not before \(operand.rawValue)"
    case .frontmatterField(let key, let operation):
      guard record.hasFrontmatter else {
        matched = false
        unavailableMessage = nil
        detail = "frontmatter is not present"
        break
      }
      if let parseError = record.parseDiagnostics.first(where: { $0.domain == .frontmatter }) {
        return (
          MarkdownRulePredicateEvidence(
            id: requirement.id,
            status: .unavailable,
            message: parseError.message
          ),
          parseError
        )
      }
      let object = record.userFrontmatter ?? [:]
      matched = frontmatterValue(object[key], keyExists: object.keys.contains(key), matches: operation)
      unavailableMessage = nil
      detail = matched ? "frontmatter \"\(key)\" matched" : "frontmatter \"\(key)\" did not match"
    case .frontmatterJMESPath(let expression):
      guard record.hasFrontmatter else {
        matched = false
        unavailableMessage = nil
        detail = "frontmatter is not present"
        break
      }
      guard let provider = registry.queryProvider else {
        return unavailable(requirement.id, "JMESPath runtime capability is unavailable")
      }
      let result = try provider.evaluateJMESPath(
        expression,
        frontmatter: .object(record.userFrontmatter ?? [:])
      )
      matched = truthy(result)
      unavailableMessage = nil
      detail = matched ? "frontmatterQuery matched" : "frontmatterQuery did not match"
    case .heading(let predicate):
      matched = record.headings.contains { heading in
        heading.text == predicate.text && (predicate.level == nil || predicate.level == heading.level)
      }
      unavailableMessage = nil
      detail = matched ? "document heading matched" : "document heading did not match"
    case .headingRegularExpression(let pattern):
      matched = record.headings.contains { regularExpression(pattern, matches: $0.text) }
      unavailableMessage = nil
      detail = matched ? "document heading matched regular expression" : "document heading did not match regular expression"
    case .section(let heading):
      matched = record.headings.contains { $0.text == heading && $0.directContentIsEmpty == false }
      unavailableMessage = nil
      detail = matched ? "document section matched" : "document section did not match"
    case .bodyContains(let substring):
      matched = record.body.contains(substring)
      unavailableMessage = nil
      detail = matched ? "document body contained configured text" : "document body did not contain configured text"
    case .bodyRegularExpression(let pattern):
      matched = regularExpression(pattern, matches: record.body)
      unavailableMessage = nil
      detail = matched ? "document body matched regular expression" : "document body did not match regular expression"
    case .wikilink(let target):
      let links = WikilinkScanner.scan(record.body)
      matched = target.map { expected in links.contains { $0.target == expected } }
        ?? (links.isEmpty == false)
      unavailableMessage = nil
      detail = matched ? "document wikilink matched" : "document wikilink did not match"
    case .bodyLineCount(let range):
      let count = record.body.isEmpty ? 0 : record.body.components(separatedBy: "\n").count
      matched = range.contains(count)
      unavailableMessage = nil
      detail = matched ? "document line count matched" : "document line count did not match"
    case .bodyWordCount(let range):
      let count = record.body.split(whereSeparator: \.isWhitespace).count
      matched = range.contains(count)
      unavailableMessage = nil
      detail = matched ? "document word count matched" : "document word count did not match"
    }

    if let unavailableMessage {
      return unavailable(requirement.id, unavailableMessage)
    }
    return (
      MarkdownRulePredicateEvidence(
        id: requirement.id,
        status: matched ? .matched : .notMatched,
        message: detail
      ),
      nil
    )
  }

  private func assessMarkdownCheck(
    _ predicate: MarkdownPredicate,
    id: String,
    severity: MarkdownDiagnosticSeverity,
    record: AnalyzedMarkdownRecord,
    ruleName: String
  ) throws -> [MarkdownDiagnostic] {
    switch predicate {
    case .heading(let heading):
      guard record.headings.contains(where: {
        $0.text == heading.text && (heading.level == nil || heading.level == $0.level)
      }) == false else { return [] }
      return [MarkdownDiagnostic(
        code: "rule.body.required-heading",
        severity: severity,
        domain: .body,
        constraintID: id,
        location: "heading",
        message: "required heading \"\(heading.text)\" not found"
      )]
    case .maxBodyLines(let maximum):
      let count = record.body.isEmpty ? 0 : record.body.components(separatedBy: "\n").count
      guard count > maximum else { return [] }
      return [MarkdownDiagnostic(
        code: "rule.body.max-lines",
        severity: severity,
        domain: .body,
        constraintID: id,
        location: "body.lines",
        message: "line count \(count) exceeds maximum \(maximum)"
      )]
    case .maxBodyWords(let maximum):
      let count = record.body.split(whereSeparator: \.isWhitespace).count
      guard count > maximum else { return [] }
      return [MarkdownDiagnostic(
        code: "rule.body.max-words",
        severity: severity,
        domain: .body,
        constraintID: id,
        location: "body.words",
        message: "word count \(count) exceeds maximum \(maximum)"
      )]
    case .headingRelationship, .section, .path:
      break
    }
    let constraint = MarkdownConstraint(id: id, predicate: predicate)
    let domain: MarkdownDiagnosticDomain
    if case .path = predicate { domain = .context } else { domain = .body }
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "__rule-check-\(ruleName)-\(id)"),
      version: "rule",
      body: domain == .body
        ? MarkdownConstraintGroup(
          requirements: severity == .error ? [constraint] : [],
          recommendations: severity == .advisory ? [constraint] : []
        )
        : MarkdownConstraintGroup(),
      context: domain == .context
        ? MarkdownConstraintGroup(
          requirements: severity == .error ? [constraint] : [],
          recommendations: severity == .advisory ? [constraint] : []
        )
        : MarkdownConstraintGroup()
    )
    let typeRegistry = try MarkdownTypeRegistry(definitions: [definition])
    return try MarkdownTypeChecker(registry: typeRegistry).assess(record, as: definition.name).diagnostics
      .filter { $0.code != "record.frontmatter.invalid-yaml" }
  }

  private func isPathCandidate(
    _ path: MarkdownRecordPath?,
    for applicability: MarkdownRuleApplicability
  ) -> Bool {
    if applicability.paths.isEmpty == false {
      guard let path, applicability.paths.contains(where: path.matches(glob:)) else { return false }
    }
    if let path, applicability.excludePaths.contains(where: path.matches(glob:)) { return false }
    return true
  }

  private func unavailable(
    _ id: String,
    _ message: String
  ) -> (evidence: MarkdownRulePredicateEvidence, diagnostic: MarkdownDiagnostic?) {
    (MarkdownRulePredicateEvidence(id: id, status: .unavailable, message: message), nil)
  }

  private func regularExpression(_ pattern: String, matches value: String) -> Bool {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(value.startIndex..., in: value)
    return expression.firstMatch(in: value, range: range) != nil
  }

  private func frontmatterValue(
    _ value: JSONValue?,
    keyExists: Bool,
    matches operation: MarkdownFrontmatterRuleOperator
  ) -> Bool {
    switch operation {
    case .hasKey:
      return keyExists
    case .doesNotHaveKey:
      return keyExists == false
    default:
      guard keyExists, let value else { return false }
      return existingFrontmatterValue(value, matches: operation)
    }
  }

  private func existingFrontmatterValue(
    _ value: JSONValue,
    matches operation: MarkdownFrontmatterRuleOperator
  ) -> Bool {
    switch operation {
    case .equals(let operand): return value == operand
    case .doesNotEqual(let operand): return value != operand
    case .includes(let operand): return value.arrayValue?.contains(operand) == true
    case .doesNotInclude(let operand):
      guard let values = value.arrayValue else { return false }
      return values.contains(operand) == false
    case .regularExpression(let pattern):
      return value.stringValue.map { regularExpression(pattern, matches: $0) } == true
    case .startsWith(let prefix): return value.stringValue?.hasPrefix(prefix) == true
    case .endsWith(let suffix): return value.stringValue?.hasSuffix(suffix) == true
    case .contains(let substring): return value.stringValue?.contains(substring) == true
    case .empty: return value.isEmptyCollection
    case .emptyString: return value.stringValue == ""
    case .emptyArray: return value.arrayValue?.isEmpty == true
    case .emptyObject: return value.objectValue?.isEmpty == true
    case .notEmpty: return value.isEmptyCollection == false
    case .isIn(let operands): return operands.contains(value)
    case .isNotIn(let operands): return operands.contains(value) == false
    case .greaterThan(let operand): return value.numberValue.map { $0 > operand } == true
    case .greaterThanOrEqual(let operand): return value.numberValue.map { $0 >= operand } == true
    case .lessThan(let operand): return value.numberValue.map { $0 < operand } == true
    case .lessThanOrEqual(let operand): return value.numberValue.map { $0 <= operand } == true
    case .after(let operand): return compare(value, operand: operand) == .orderedDescending
    case .onOrAfter(let operand):
      let result = compare(value, operand: operand)
      return result == .orderedDescending || result == .orderedSame
    case .before(let operand): return compare(value, operand: operand) == .orderedAscending
    case .onOrBefore(let operand):
      let result = compare(value, operand: operand)
      return result == .orderedAscending || result == .orderedSame
    case .between(let range):
      switch range {
      case .number(let from, let through):
        return value.numberValue.map { $0 >= from && $0 <= through } == true
      case .dateTime(let from, let through):
        guard let literal = value.dateTimeLiteral else { return false }
        let lower = compare(literal, operand: from)
        let upper = compare(literal, operand: through)
        return (lower == .orderedDescending || lower == .orderedSame)
          && (upper == .orderedAscending || upper == .orderedSame)
      }
    case .typeIs(let type): return value.ruleJSONType == type
    case .hasKey, .doesNotHaveKey: return false
    }
  }

  private func compare(_ lhs: JSONValue, operand: MarkdownRuleDateTimeLiteral) -> ComparisonResult? {
    guard let literal = lhs.dateTimeLiteral, literal.precision >= operand.precision else { return nil }
    return compare(literal, operand: operand)
  }

  private func compare(
    _ lhs: MarkdownRuleDateTimeLiteral,
    operand rhs: MarkdownRuleDateTimeLiteral
  ) -> ComparisonResult {
    switch rhs.precision {
    case .date: return lhs.dateKey.compare(rhs.dateKey)
    case .dateTime: return lhs.date.compare(rhs.date)
    }
  }

  private func truthy(_ value: JSONValue?) -> Bool {
    guard let value else { return false }
    switch value {
    case .null: return false
    case .boolean(let value): return value
    case .string(let value): return value.isEmpty == false
    case .array(let value): return value.isEmpty == false
    case .object(let value): return value.isEmpty == false
    case .integer, .number: return true
    }
  }

  private func displayPath(_ pointer: String) -> String {
    if pointer.isEmpty || pointer == "/" { return "frontmatter" }
    let trimmed = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
    return trimmed.replacingOccurrences(of: "/", with: ".")
  }
}

/// Errors raised while selecting a compiled rule for assessment.
public enum MarkdownRuleCheckerError: Error, Equatable, LocalizedError {
  case unknownRule(String)

  public var errorDescription: String? {
    switch self {
    case .unknownRule(let name): return "Unknown compiled Markdown rule \"\(name)\""
    }
  }
}

private extension JSONValue {
  var arrayValue: [JSONValue]? {
    guard case .array(let values) = self else { return nil }
    return values
  }

  var numberValue: Double? {
    switch self {
    case .integer(let value): return Double(value)
    case .number(let value): return value
    default: return nil
    }
  }

  var isEmptyCollection: Bool {
    switch self {
    case .string(let value): return value.isEmpty
    case .array(let value): return value.isEmpty
    case .object(let value): return value.isEmpty
    default: return false
    }
  }

  var dateTimeLiteral: MarkdownRuleDateTimeLiteral? {
    guard case .string(let value) = self else { return nil }
    return MarkdownRuleDateTimeLiteral(value)
  }

  var ruleJSONType: MarkdownRuleJSONType {
    switch self {
    case .string: return .string
    case .boolean: return .boolean
    case .integer, .number: return .number
    case .array: return .array
    case .object: return .object
    case .null: return .null
    }
  }
}
