import Foundation

public enum MarkdownRelationshipDirection: String, Codable, Sendable { case outgoing, incoming, both }

/// Partitioned occurrence evidence. Self-links are never duplicated in the other sections.
public struct MarkdownRelationshipQuery: Codable, Sendable {
  public var direction: MarkdownRelationshipDirection
  public var source: String
  public var outgoing: [MarkdownRelationshipOccurrence]
  public var incoming: [MarkdownRelationshipOccurrence]
  public var selfLinks: [MarkdownRelationshipOccurrence]
  public var evidence: MarkdownRelationshipEvaluation

  public init(evaluation: MarkdownRelationshipEvaluation, source: String,
    direction: MarkdownRelationshipDirection, type: String, relationship: String? = nil,
    identity: MarkdownRecordIdentity? = nil,
  ) {
    self.direction = direction
    self.source = source
    self.evidence = evaluation
    outgoing = []
    incoming = []
    selfLinks = []
    for occurrence in evaluation.occurrences where occurrence.type == type
      && (relationship == nil || occurrence.relationship == relationship) {
      let from = occurrence.source == source || (identity != nil && occurrence.sourceIdentity == identity)
      let to = occurrence.resolution?.destination == source || (identity != nil && occurrence.targetIdentity == identity)
      let isSelf = occurrence.resolution?.destination != nil
        && (occurrence.sourceIdentity != nil && occurrence.sourceIdentity == occurrence.targetIdentity
          || occurrence.source == occurrence.resolution?.destination)
      if isSelf && (from || to) { selfLinks.append(occurrence) }
      else {
        if from && direction != .incoming { outgoing.append(occurrence) }
        if to && direction != .outgoing { incoming.append(occurrence) }
      }
    }
    // The evidence graph retains assessments/causes without duplicating all occurrences.
    evidence.occurrences = []
  }
}
