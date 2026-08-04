import Foundation

/// Runtime facilities that are not implemented by the portable rule evaluator itself.
///
/// See <doc:RuleRuntimeCapabilities> for host responsibilities.
public enum MarkdownRuleRuntimeCapability: String, Codable, CaseIterable, Hashable, Sendable {
  /// A host supplies a modification date on each relevant ``MarkdownRecordContext``.
  case modificationDate
  /// A host can compile and execute JMESPath expressions against frontmatter.
  case frontmatterJMESPath
}

/// Date precision used by rule comparison operands.
public enum MarkdownRuleDateTimePrecision: String, Codable, Comparable, Sendable {
  case date
  case dateTime

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs == .date && rhs == .dateTime
  }
}

/// A validated date-only or RFC 3339 rule operand.
public struct MarkdownRuleDateTimeLiteral: Codable, Equatable, Sendable {
  public let rawValue: String
  public let date: Date
  public let precision: MarkdownRuleDateTimePrecision

  public init?(_ rawValue: String) {
    if let date = Self.dateOnlyFormatter().date(from: rawValue) {
      self.rawValue = rawValue
      self.date = date
      self.precision = .date
      return
    }
    if let date = Self.isoFormatter(fractionalSeconds: true).date(from: rawValue)
      ?? Self.isoFormatter(fractionalSeconds: false).date(from: rawValue) {
      self.rawValue = rawValue
      self.date = date
      self.precision = .dateTime
      return
    }
    return nil
  }

  /// Creates a date-time literal from a host-supplied timestamp.
  public init(date: Date) {
    self.rawValue = Self.isoFormatter(fractionalSeconds: false).string(from: date)
    self.date = date
    self.precision = .dateTime
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    guard let value = Self(rawValue) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected YYYY-MM-DD or an RFC 3339 date-time"
      )
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  package var dateKey: String {
    let calendar = Calendar(identifier: .gregorian)
    let zone = TimeZone(secondsFromGMT: 0) ?? .current
    let components = calendar.dateComponents(in: zone, from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  private static func dateOnlyFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  private static func isoFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = fractionalSeconds
      ? [.withInternetDateTime, .withFractionalSeconds]
      : [.withInternetDateTime]
    return formatter
  }
}

/// An inclusive nonnegative integer range used by body-count predicates.
public struct MarkdownRuleIntegerRange: Codable, Equatable, Sendable {
  public var minimum: Int?
  public var maximum: Int?

  public init(minimum: Int? = nil, maximum: Int? = nil) {
    self.minimum = minimum
    self.maximum = maximum
  }

  public func contains(_ value: Int) -> Bool {
    if let minimum, value < minimum { return false }
    if let maximum, value > maximum { return false }
    return true
  }
}

/// JSON types recognized by frontmatter field predicates.
public enum MarkdownRuleJSONType: String, Codable, Equatable, Sendable {
  case string
  case boolean
  case number
  case array
  case object
  case null
}

/// Inclusive numeric or date/time bounds for a frontmatter field.
public enum MarkdownRuleBetweenRange: Equatable, Sendable {
  case number(from: Double, through: Double)
  case dateTime(from: MarkdownRuleDateTimeLiteral, through: MarkdownRuleDateTimeLiteral)
}

/// One normalized operation applied to a named frontmatter field.
public enum MarkdownFrontmatterRuleOperator: Equatable, Sendable {
  case equals(JSONValue)
  case doesNotEqual(JSONValue)
  case includes(JSONValue)
  case doesNotInclude(JSONValue)
  case hasKey
  case doesNotHaveKey
  case regularExpression(String)
  case startsWith(String)
  case endsWith(String)
  case contains(String)
  case empty
  case emptyString
  case emptyArray
  case emptyObject
  case notEmpty
  case isIn([JSONValue])
  case isNotIn([JSONValue])
  case greaterThan(Double)
  case greaterThanOrEqual(Double)
  case lessThan(Double)
  case lessThanOrEqual(Double)
  case after(MarkdownRuleDateTimeLiteral)
  case onOrAfter(MarkdownRuleDateTimeLiteral)
  case before(MarkdownRuleDateTimeLiteral)
  case onOrBefore(MarkdownRuleDateTimeLiteral)
  case between(MarkdownRuleBetweenRange)
  case typeIs(MarkdownRuleJSONType)
}

/// One applicability predicate in the normalized rule model.
public enum MarkdownRulePredicate: Equatable, Sendable {
  case markdown(MarkdownPredicate)
  case pathRegularExpression(String)
  case filenameEquals(String)
  case extensionIn([String])
  case modifiedAfter(MarkdownRuleDateTimeLiteral)
  case modifiedBefore(MarkdownRuleDateTimeLiteral)
  case frontmatterField(key: String, operation: MarkdownFrontmatterRuleOperator)
  case frontmatterJMESPath(String)
  case heading(MarkdownHeadingPredicate)
  case headingRegularExpression(String)
  case section(String)
  case bodyContains(String)
  case bodyRegularExpression(String)
  case wikilink(target: String?)
  case bodyLineCount(MarkdownRuleIntegerRange)
  case bodyWordCount(MarkdownRuleIntegerRange)
}

/// A stable predicate identifier and its normalized applicability predicate.
public struct MarkdownRuleRequirement: Equatable, Sendable {
  public var id: String
  public var predicate: MarkdownRulePredicate

  public init(id: String, predicate: MarkdownRulePredicate) {
    self.id = id
    self.predicate = predicate
  }
}

/// Selects records before a rule's policy checks are evaluated.
public struct MarkdownRuleApplicability: Equatable, Sendable {
  /// Any-of logical-path globs used to include candidates.
  public var paths: [String]
  /// Logical-path globs that take precedence over includes.
  public var excludePaths: [String]
  /// Additional all-of predicates.
  public var requirements: [MarkdownRuleRequirement]
  /// Markdown types of which a record must conform to at least one.
  public var anyTypes: [MarkdownTypeName]
  /// Markdown types to which a record must conform in full.
  public var allTypes: [MarkdownTypeName]

  public init(
    paths: [String] = [],
    excludePaths: [String] = [],
    requirements: [MarkdownRuleRequirement] = [],
    anyTypes: [MarkdownTypeName] = [],
    allTypes: [MarkdownTypeName] = []
  ) {
    self.paths = paths
    self.excludePaths = excludePaths
    self.requirements = requirements
    self.anyTypes = anyTypes
    self.allTypes = allTypes
  }
}

/// A normalized policy check evaluated after a rule is applicable.
public enum MarkdownRuleCheckPredicate: Equatable, Sendable {
  case frontmatterSchema(source: MarkdownJSONSchemaSource, presence: MarkdownFrontmatterPresence)
  case markdown(MarkdownPredicate)
}

/// One required or advisory rule check.
public struct MarkdownRuleCheck: Equatable, Sendable {
  public var id: String
  public var severity: MarkdownDiagnosticSeverity
  public var predicate: MarkdownRuleCheckPredicate

  public init(
    id: String,
    severity: MarkdownDiagnosticSeverity = .error,
    predicate: MarkdownRuleCheckPredicate
  ) {
    self.id = id
    self.severity = severity
    self.predicate = predicate
  }
}

/// A reusable normalized rule definition.
///
/// See <doc:MarkdownRules> for semantics and <doc:CompilingMarkdownRules> for execution.
public struct MarkdownRuleDefinition: Equatable, Sendable {
  public var name: String
  public var applicability: MarkdownRuleApplicability
  public var checks: [MarkdownRuleCheck]
  /// Optional source used to resolve relative JSON Schema references.
  public var source: String?

  public init(
    name: String,
    applicability: MarkdownRuleApplicability = MarkdownRuleApplicability(),
    checks: [MarkdownRuleCheck] = [],
    source: String? = nil
  ) {
    self.name = name
    self.applicability = applicability
    self.checks = checks
    self.source = source
  }
}

/// Outcome of evaluating one applicability predicate.
public enum MarkdownRuleEvidenceStatus: String, Codable, Equatable, Sendable {
  case matched
  case notMatched
  case unavailable
}

/// Stable evidence used by APIs and CLI explanation output.
public struct MarkdownRulePredicateEvidence: Codable, Equatable, Sendable {
  public var id: String
  public var status: MarkdownRuleEvidenceStatus
  public var message: String

  public init(id: String, status: MarkdownRuleEvidenceStatus, message: String) {
    self.id = id
    self.status = status
    self.message = message
  }
}

/// Overall state of one rule assessment.
public enum MarkdownRuleAssessmentStatus: String, Codable, Equatable, Sendable {
  case notApplicable
  case skipped
  case passed
  case failed
}

/// Structured result of matching and checking one compiled rule against one record.
///
/// See <doc:CompilingMarkdownRules> for status meanings.
public struct MarkdownRuleAssessment: Equatable, Sendable {
  public var ruleName: String
  public var status: MarkdownRuleAssessmentStatus
  public var evidence: [MarkdownRulePredicateEvidence]
  public var applicabilityDiagnostics: [MarkdownDiagnostic]
  public var diagnostics: [MarkdownDiagnostic]

  public init(
    ruleName: String,
    status: MarkdownRuleAssessmentStatus,
    evidence: [MarkdownRulePredicateEvidence] = [],
    applicabilityDiagnostics: [MarkdownDiagnostic] = [],
    diagnostics: [MarkdownDiagnostic] = []
  ) {
    self.ruleName = ruleName
    self.status = status
    self.evidence = evidence
    self.applicabilityDiagnostics = applicabilityDiagnostics
    self.diagnostics = diagnostics
  }

  public var applicable: Bool { status != .notApplicable }
  public var passes: Bool { status == .passed || status == .skipped }
}
