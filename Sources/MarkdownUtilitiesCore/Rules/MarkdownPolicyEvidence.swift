import Foundation

/// Provenance for one policy declaration. Conflicts retain both origins.
public struct MarkdownPolicyOrigin: Codable, Equatable, Sendable {
  public var rule: String
  public var policy: String
  public var definitionSource: String?
  public var location: String
  public var declaration: JSONValue
}

/// A diagnostic and its ordered occurrence witnesses. Indices refer to extraction.occurrences.
public struct MarkdownPolicyDiagnostic: Codable, Sendable {
  public var diagnostic: MarkdownDiagnostic
  public var origins: [MarkdownPolicyOrigin]
  public var occurrences: [Int]
}

public struct MarkdownPolicyAssessment: Codable, Sendable {
  public var origin: MarkdownPolicyOrigin
  public var outcome: MarkdownAssessmentOutcome
  public var severity: MarkdownDiagnosticSeverity
  public var scope: MarkdownPolicyScope
  public var checkedRecords: [String]
  public var graphComplete: Bool
  public var boundaryEdges: [Int]
  public var cycleWitnessMode: MarkdownCycleWitnessMode
  public var cycleSearchStoppedEarly: Bool
  public var diagnostics: [MarkdownPolicyDiagnostic]
  public var diagnosticsTruncated: Bool
}

public struct MarkdownCollectionRecordAssessment: Codable, Sendable {
  public var path: String
  public var membership: MarkdownRuleEvidenceStatus
  public var outcome: MarkdownAssessmentOutcome
  public var assessment: MarkdownRuleAssessment
}

public struct MarkdownCollectionRuleAssessment: Codable, Sendable {
  public var rule: String
  public var outcome: MarkdownAssessmentOutcome
  public var sourcesComplete: Bool
  public var records: [MarkdownCollectionRecordAssessment]
  public var policies: [MarkdownPolicyAssessment]
}

/// Portable evidence; native hosts may persist it with a verified dependency certificate.
public struct MarkdownRuleCollectionAssessment: Codable, Sendable {
  public var evaluatorProfile = MarkdownRuleCollectionEvaluator.profile
  public var collection: String
  public var generation: String
  public var rules: [MarkdownCollectionRuleAssessment]
  public var extraction: MarkdownRelationshipEvaluation
  public var typeEvidence: MarkdownRelationshipEvaluation
  public var conflicts: [MarkdownPolicyDiagnostic]
  public var diagnosticsTruncated: Bool
  public var limitations: [String]
  public var outcome: MarkdownAssessmentOutcome
}
