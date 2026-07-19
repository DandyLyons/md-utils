import Foundation

/// Severity of a Markdown type diagnostic.
public enum MarkdownDiagnosticSeverity: String, Codable, Equatable, Sendable {
  case error
  case advisory
}

/// The conformance domain associated with a diagnostic.
public enum MarkdownDiagnosticDomain: String, Codable, Equatable, Sendable {
  case record
  case frontmatter
  case body
  case context
  case typeHint
}

/// Describes whether a fix can be applied without requesting a domain value.
public enum MarkdownFixItSafety: String, Codable, Equatable, Sendable {
  case automatic
  case requiresInput
  case advisoryOnly
}

/// A portable edit to canonical Markdown record content.
public enum MarkdownRecordEdit: Equatable, Sendable {
  case ensureFrontmatter
  case setFrontmatterValue(path: [String], value: JSONValue)
  case requestFrontmatterValue(path: [String])
  case appendHeading(text: String, level: Int)
}

/// A structured remediation proposed by a Markdown diagnostic.
public struct MarkdownFixIt: Equatable, Sendable {
  public var id: String
  public var title: String
  public var safety: MarkdownFixItSafety
  public var edits: [MarkdownRecordEdit]

  public init(
    id: String,
    title: String,
    safety: MarkdownFixItSafety,
    edits: [MarkdownRecordEdit]
  ) {
    self.id = id
    self.title = title
    self.safety = safety
    self.edits = edits
  }
}

/// A stable, structured type-assessment diagnostic.
public struct MarkdownDiagnostic: Equatable, Sendable {
  public var code: String
  public var severity: MarkdownDiagnosticSeverity
  public var domain: MarkdownDiagnosticDomain
  public var constraintID: String?
  public var location: String
  public var message: String
  public var fixIts: [MarkdownFixIt]

  public init(
    code: String,
    severity: MarkdownDiagnosticSeverity,
    domain: MarkdownDiagnosticDomain,
    constraintID: String? = nil,
    location: String,
    message: String,
    fixIts: [MarkdownFixIt] = []
  ) {
    self.code = code
    self.severity = severity
    self.domain = domain
    self.constraintID = constraintID
    self.location = location
    self.message = message
    self.fixIts = fixIts
  }
}

/// The result of assessing one record against one Markdown type.
public struct MarkdownTypeAssessment: Equatable, Sendable {
  public var type: MarkdownTypeName
  public var version: String
  public var diagnostics: [MarkdownDiagnostic]

  public init(
    type: MarkdownTypeName,
    version: String,
    diagnostics: [MarkdownDiagnostic]
  ) {
    self.type = type
    self.version = version
    self.diagnostics = diagnostics
  }

  public var conforms: Bool {
    diagnostics.contains(where: { $0.severity == .error }) == false
  }

  public var errors: [MarkdownDiagnostic] {
    diagnostics.filter { $0.severity == .error }
  }

  public var advisories: [MarkdownDiagnostic] {
    diagnostics.filter { $0.severity == .advisory }
  }
}

/// Result of verifying one type hint declared by a record.
public struct MarkdownTypeHintAssessment: Equatable, Sendable {
  public enum Status: String, Codable, Equatable, Sendable {
    case confirmed
    case rejected
    case unknownType
    case unavailableVersion
  }

  public var hint: MarkdownTypeHint
  public var status: Status
  public var assessment: MarkdownTypeAssessment?

  public init(
    hint: MarkdownTypeHint,
    status: Status,
    assessment: MarkdownTypeAssessment? = nil
  ) {
    self.hint = hint
    self.status = status
    self.assessment = assessment
  }
}
