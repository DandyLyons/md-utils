import Foundation

/// Required evidence conjunction; uncertainty is never ordinary nonconformance.
public enum MarkdownAssessmentOutcome: String, Codable, Equatable, Sendable {
  case pass, fail, unavailable

  public static func all(_ values: [Self]) -> Self {
    if values.contains(.fail) { return .fail }
    return values.contains(.unavailable) ? .unavailable : .pass
  }
}

/// Explicit finite limits for one relationship assessment, including graph discovery.
public struct MarkdownRelationshipLimits: Codable, Sendable {
  public var records = 10_000
  public var bytes = 64 * 1_024 * 1_024
  public var occurrences = 100_000
  public var candidates = 100_000
  public var definitions = 1_000
  public var nodes = 100_000
  public var edges = 100_000
  public var diagnostics = 10_000
  public var policies = 1_000
  public var policySteps = 5_000_000
  public init() {}
}

/// An immutable host snapshot. Paths are resolution keys; record identities are vertices.
public struct MarkdownRelationshipCollection: Sendable {
  public let identity: String
  public let generation: String
  public let records: [String: MarkdownRecord]
  public let resolver: CollectionWikilinkResolver
  public let sourcesComplete: Bool
  public let limitations: [String]

  public init(identity: String, generation: String, records: [String: MarkdownRecord],
    paths: Set<String>, sourcesComplete: Bool, candidatesComplete: Bool,
    completeExactPaths: Set<String> = [], limitations: [String] = [],
  ) {
    self.identity = identity
    self.generation = generation
    self.records = records
    self.resolver = .init(paths: paths, namespaceComplete: candidatesComplete, completeExactPaths: completeExactPaths)
    self.sourcesComplete = sourcesComplete
    self.limitations = limitations
  }
}

/// One selected value, including malformed assertions. Raw-file ranges are unavailable.
public struct MarkdownRelationshipOccurrence: Codable, Equatable, Sendable {
  public var source: String
  public var sourceIdentity: MarkdownRecordIdentity?
  public var sourceRevision: MarkdownRecordRevision?
  public var type: String
  public var typeVersion: String
  public var definitionSource: String?
  public var definitionRevision: String?
  public var declarationLocation: String
  /// Decoded scalar coordinates; never a range in the original YAML/TOML file.
  public var decodedUTF8Range: Range<Int>?
  public var sourceUTF8Range: Range<Int>? = nil
  public var relationship: String
  public var propertyPath: [WikilinkPropertyComponent]
  public var value: JSONValue
  public var nativeTemporal: Bool = false
  public var link: Wikilink?
  public var resolution: CollectionWikilinkResolution?
  public var targetIdentity: MarkdownRecordIdentity?
  public var targetRevision: MarkdownRecordRevision?
  public var targetType: String
  public var outcome: MarkdownAssessmentOutcome = .pass
  public var targetOutcome: MarkdownAssessmentOutcome?
  public var severity: MarkdownDiagnosticSeverity
  public var diagnostics: [MarkdownDiagnostic] = []
  /// Stable references into the result's node assessments avoid recursive diagnostic expansion.
  public var dependency: String?
}

/// A node's converged required result and direct causes. Dependency IDs can form cycles.
public struct MarkdownRelationshipNodeAssessment: Codable, Sendable {
  public var id: String
  public var source: String
  public var type: String
  public var sourceRevision: MarkdownRecordRevision?
  public var definitionRevision: String?
  public var outcome: MarkdownAssessmentOutcome
  public var dependencies: [String]
  /// False when selection could not enumerate every branch; omitted advisories were not evaluated.
  public var selectionComplete: [String: Bool]
  public var diagnostics: [MarkdownDiagnostic]
}

/// Complete evidence for one bounded evaluation, never an assertion of domain truth.
public struct MarkdownRelationshipEvaluation: Codable, Sendable {
  public var evaluatorProfile: String = MarkdownRelationshipEvaluator.profile
  public var collection: String?
  public var generation: String?
  public var sourcesComplete: Bool
  public var candidatesComplete: Bool
  public var limitations: [String]
  public var occurrences: [MarkdownRelationshipOccurrence]
  public var assessments: [MarkdownRelationshipNodeAssessment]
  public var diagnosticsTruncated: Bool

  public func assessment(source: String, type: String) -> MarkdownRelationshipNodeAssessment? {
    assessments.first { $0.source == source && $0.type == type }
  }
}
