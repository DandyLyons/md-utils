import Foundation

/// Presentation never changes the evidence used to execute a query.
public enum MarkdownQueryDetail: String, Codable, Sendable { case summary, explain, evidence }
public enum MarkdownSelectionMode: String, Codable, Sendable { case union, intersection }

/// Persisted membership facts; absent entries mean unavailable, not nonmembership.
package struct MarkdownIndexedQueryEvidence: Sendable {
  package init() {}
  package var types: [String: [String: MarkdownAssessmentOutcome]] = [:]
  package var rules: [String: [String: MarkdownAssessmentOutcome]] = [:]
}

/// Publication-time facts, independent of query direction and presentation detail.
/// Raw body text is deliberately not part of this projection.
package struct MarkdownPreparedQueryDocument: Codable, Sendable {
  package var bindings: [String: [MarkdownQueryApplicability]] = [:]
  package var rules: [String: MarkdownAssessmentOutcome] = [:]
  package var requiredTypes: [String: MarkdownAssessmentOutcome] = [:]
  package var typeOutcomes: [String: MarkdownAssessmentOutcome] = [:]
  package var limitations: [String] = []
  package var linkLimitations: [String] = []
  package var parseFailed = false
  package var tags: [String] = []
  package var occurrences: [MarkdownQueryOccurrence] = []
  package var nodes: [MarkdownRelationshipNodeAssessment] = []
  package var assertions: [MarkdownRelationshipOccurrence] = []
  package var revision: MarkdownRecordRevision?
  package init() {}
}

/// Simple sets, not a second query language. Hosts validate names before discovery.
public enum MarkdownDocumentSelector: Sendable {
  case files(Set<String>), folder(String), type(String), requiredType(String)
  case rule(String), tag(String), jmespath(String)
}

public struct MarkdownCollectionQueryRequest: Sendable {
  package var suppliedSourceBound: Set<String>? {
    let sets = selectors.compactMap { selector -> Set<String>? in
      if case .files(let paths) = selector { return paths }
      return nil
    }
    guard let first = sets.first else { return nil }
    if mode == .intersection { return sets.dropFirst().reduce(first) { $0.intersection($1) } }
    guard sets.count == selectors.count else { return nil }
    return sets.reduce(into: Set<String>()) { $0.formUnion($1) }
  }
  /// A conservative source set computed without parsing document contents.
  /// Content-dependent selectors keep candidates until their actual assessment.
  package func candidateSources(in paths: Set<String>) -> Set<String> {
    var markdown = paths.filter { ["md", "markdown"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
    for selector in selectors {
      if case .files(let supplied) = selector { markdown.formUnion(supplied) }
    }
    func candidates(_ selector: MarkdownDocumentSelector) -> Set<String> {
      switch selector {
      case .files(let files): return files
      case .folder(let folder): return markdown.filter { folder.isEmpty || $0.hasPrefix(folder) }
      default: return markdown
      }
    }
    var result = mode == .intersection ? (selectors.first.map(candidates) ?? []) : []
    for selector in selectors {
      if mode == .intersection { result.formIntersection(candidates(selector)) }
      else { result.formUnion(candidates(selector)) }
    }
    for exclusion in exclusions {
      switch exclusion {
      case .files, .folder: result.subtract(candidates(exclusion))
      default: break
      }
    }
    return result
  }
  public var direction: MarkdownRelationshipDirection
  public var selectors: [MarkdownDocumentSelector]
  public var exclusions: [MarkdownDocumentSelector]
  public var mode: MarkdownSelectionMode
  public var types: [String]
  public var relation: String?
  public var detail: MarkdownQueryDetail

  public init(direction: MarkdownRelationshipDirection, selectors: [MarkdownDocumentSelector],
    exclusions: [MarkdownDocumentSelector] = [], mode: MarkdownSelectionMode = .union,
    types: [String] = [], relation: String? = nil, detail: MarkdownQueryDetail = .summary,
  ) {
    self.direction = direction; self.selectors = selectors; self.exclusions = exclusions
    self.mode = mode; self.types = types; self.relation = relation; self.detail = detail
  }
}

public struct MarkdownQueryNotice: Codable, Sendable {
  public var code: String
  public var message: String
  public var hint: String?
  public init(code: String, message: String, hint: String? = nil) {
    self.code = code; self.message = message; self.hint = hint
  }
}

public struct MarkdownQueryCoverage: Codable, Sendable {
  public var selection = "complete"
  public var sources = "complete"
  public var candidates = "complete"
  public var interpretations = "complete"
  public var limitations: [String] = []
  public var complete: Bool {
    [selection, sources, candidates, interpretations].allSatisfy { $0 == "complete" }
  }
}

public struct MarkdownQueryTriple: Codable, Equatable, Sendable {
  public var subject: String
  public var predicate: String
  public var object: String
  public var occurrenceCount: Int
}

public struct MarkdownQueryLocation: Codable, Equatable, Sendable {
  public var region: String
  public var propertyPath: [WikilinkPropertyComponent]?
  public var line: Int?
  public var decodedUTF8Range: Range<Int>?
  public var sourceUTF8Range: Range<Int>?
}

/// Both recognized ordinary links and malformed selected named values live here.
public struct MarkdownQueryOccurrence: Codable, Sendable {
  public var id: String
  public var source: String
  public var sourceIdentity: MarkdownRecordIdentity?
  public var sourceRevision: MarkdownRecordRevision?
  public var location: MarkdownQueryLocation
  public var value: JSONValue
  public var syntax: String?
  public var resolution: CollectionWikilinkResolution?
  public var link: Wikilink? = nil
  public var nativeTemporal: Bool? = nil
}

/// Declaration and assessment evidence, without repeating the authored occurrence.
public struct MarkdownQueryNamedContract: Codable, Sendable {
  public var type: String
  public var typeVersion: String
  public var definitionSource: String?
  public var definitionRevision: String?
  public var declarationLocation: String
  public var relationship: String
  public var targetType: String
  public var targetIdentity: MarkdownRecordIdentity?
  public var targetRevision: MarkdownRecordRevision?
  public var outcome: MarkdownAssessmentOutcome
  public var targetOutcome: MarkdownAssessmentOutcome?
  public var severity: MarkdownDiagnosticSeverity
  public var diagnostics: [MarkdownDiagnostic]
  public var dependency: String?

  init(_ occurrence: MarkdownRelationshipOccurrence) {
    type = occurrence.type; typeVersion = occurrence.typeVersion
    definitionSource = occurrence.definitionSource; definitionRevision = occurrence.definitionRevision
    declarationLocation = occurrence.declarationLocation; relationship = occurrence.relationship
    targetType = occurrence.targetType; targetIdentity = occurrence.targetIdentity
    targetRevision = occurrence.targetRevision; outcome = occurrence.outcome
    targetOutcome = occurrence.targetOutcome; severity = occurrence.severity
    diagnostics = occurrence.diagnostics; dependency = occurrence.dependency
  }
}

public struct MarkdownQueryApplicability: Codable, Equatable, Sendable {
  public var kind: String
  public var rule: String?
  public var expressionLocation: String?
  public var verification: MarkdownAssessmentOutcome?
}

public struct MarkdownQueryInterpretation: Codable, Sendable {
  public var id: String
  public var occurrence: String
  public var applicability: [MarkdownQueryApplicability]
  public var assertion: MarkdownQueryNamedContract
  /// Recognized substrings of a malformed whole-value assertion are related
  /// evidence, not independent unnamed assertions.
  public var containedOccurrences: [String] = []
}

public struct MarkdownQueryDirections: Codable, Sendable {
  public var outgoing: [String]?
  public var incoming: [String]?
  public var selfLinks: [String] = []
  init(_ direction: MarkdownRelationshipDirection) {
    outgoing = direction == .incoming ? nil : []
    incoming = direction == .outgoing ? nil : []
  }
}

public struct MarkdownQueryFile: Codable, Sendable {
  public var path: String
  public var named: MarkdownQueryDirections
  public var unnamed: MarkdownQueryDirections
}

public struct MarkdownQueryExplanation: Codable, Sendable {
  public var source: String
  public var predicate: String
  public var location: MarkdownQueryLocation
  public var applicability: [MarkdownQueryApplicability]
  public var outcome: MarkdownAssessmentOutcome
  public var diagnostics: [MarkdownDiagnostic]
}

public struct MarkdownQueryDiagnostic: Codable, Sendable {
  public var source: String
  public var type: String
  public var diagnostic: MarkdownDiagnostic
}

/// One envelope, with detail-dependent fields; nil fields are omitted by Codable.
public struct MarkdownCollectionQueryResult: Codable, Sendable {
  public var schemaVersion = 1
  public var detail: MarkdownQueryDetail
  public var direction: MarkdownRelationshipDirection
  public var selected: [String]
  public var relationships: [MarkdownQueryTriple]
  public var links: [MarkdownQueryTriple]
  public var notices: [MarkdownQueryNotice]
  public var coverage: MarkdownQueryCoverage?
  public var explanations: [MarkdownQueryExplanation]?
  public var skipped: [String]?
  public var files: [MarkdownQueryFile]?
  public var occurrences: [MarkdownQueryOccurrence]?
  public var namedRelationships: [MarkdownQueryInterpretation]?
  public var assessments: [MarkdownRelationshipNodeAssessment]?
  public var diagnostics: [MarkdownQueryDiagnostic]?
  public var collection: String?
  public var generation: String?
  public var evaluatorProfile: String?
}

extension MarkdownRuleTypeExpression {
  /// Only requirements shared by every alternative are unconditional.
  package var unconditionalQueryReferences: Set<String> {
    switch self {
    case .reference(let name): return [name]
    case .not: return []
    case .allOf(let children): return children.reduce(into: []) { $0.formUnion($1.unconditionalQueryReferences) }
    case .anyOf(let children), .oneOf(let children):
      guard let first = children.first else { return [] }
      return children.dropFirst().reduce(first.unconditionalQueryReferences) { $0.intersection($1.unconditionalQueryReferences) }
    }
  }

  package func positiveQueryReferences(at location: String = "types") -> [(String, String)] {
    switch self {
    case .reference(let name): return [(name, location)]
    case .not: return []
    case .allOf(let children), .anyOf(let children), .oneOf(let children):
      let key: String
      switch self { case .allOf: key = "allOf"; case .anyOf: key = "anyOf"; default: key = "oneOf" }
      return children.enumerated().flatMap { $0.element.positiveQueryReferences(at: "\(location).\(key)[\($0.offset)]") }
    }
  }
}
