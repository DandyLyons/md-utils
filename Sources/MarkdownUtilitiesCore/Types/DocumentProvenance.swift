import Foundation

/// Partial observations, never a canonical identity or a document backup.
public struct DocumentObservation: Codable, Equatable, Sendable {
  public var path: String
  public var firstRevision: String?
  public var lastRevision: String?
  public var firstGeneration: Int
  public var lastGeneration: Int
  public var firstObservedAt: Double
  public var lastObservedAt: Double
  public var verified: Bool
  public var completeScan: Bool
  public var absent: Bool
  public var historyGap: Bool

  public init(path: String, firstRevision: String?, lastRevision: String?, firstGeneration: Int,
    lastGeneration: Int, firstObservedAt: Double, lastObservedAt: Double, verified: Bool,
    completeScan: Bool, absent: Bool = false, historyGap: Bool = false,
  ) {
    self.path = path; self.firstRevision = firstRevision; self.lastRevision = lastRevision
    self.firstGeneration = firstGeneration; self.lastGeneration = lastGeneration
    self.firstObservedAt = firstObservedAt; self.lastObservedAt = lastObservedAt
    self.verified = verified; self.completeScan = completeScan; self.absent = absent; self.historyGap = historyGap
  }
}

/// A coordinator-confirmed operation, separate from filesystem observations.
public struct ManagedDocumentEvent: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case create, edit, identity, repairUUID, delete, copy, move }
  public enum Confirmation: String, Codable, Sendable { case coordinator, operatorConfirmed }
  public var id: String
  public var kind: Kind
  public var path: String
  public var revision: String?
  public var sourcePath: String?
  public var sourceRevision: String?
  public var confirmation: Confirmation
  public var observedAt: Double

  public init(id: String, kind: Kind, path: String, revision: String?, sourcePath: String? = nil,
    sourceRevision: String? = nil, confirmation: Confirmation = .coordinator, observedAt: Double,
  ) {
    self.id = id; self.kind = kind; self.path = path; self.revision = revision
    self.sourcePath = sourcePath; self.sourceRevision = sourceRevision
    self.confirmation = confirmation; self.observedAt = observedAt
  }
}

public struct DocumentProvenanceEvidence: Codable, Equatable, Sendable {
  public var epoch: String
  public var observations: [DocumentObservation]
  public var events: [ManagedDocumentEvent]
  public var historyPruned: Bool
  public var truncated: Bool
  public init(epoch: String, observations: [DocumentObservation], events: [ManagedDocumentEvent],
    historyPruned: Bool = false, truncated: Bool = false,
  ) {
    self.epoch = epoch; self.observations = observations; self.events = events
    self.historyPruned = historyPruned; self.truncated = truncated
  }
}

/// Callers supply all current holders of one normalized UUID after authoritative refresh.
public struct UUIDCollisionCandidate: Codable, Equatable, Sendable {
  public var path: String
  public var revision: String
  public init(path: String, revision: String) { self.path = path; self.revision = revision }
}

public struct UUIDCollisionExplanation: Codable, Equatable, Sendable {
  public struct Relationship: Codable, Equatable, Sendable {
    public enum Strength: String, Codable, Sendable { case possible, confirmed }
    public var source: String
    public var destination: String
    public var strength: Strength
    public var reason: String
  }
  public var relationships: [Relationship]
  public var reasons: [String]
  /// A recommendation only; never permission to write a source file.
  public var originalPath: String?
  public var duplicatePaths: [String]
  public var ambiguous: Bool { originalPath == nil }
}

public enum UUIDCollisionAssessor {
  public static func assess(_ candidates: [UUIDCollisionCandidate], evidence: DocumentProvenanceEvidence,
    completeHolderSet: Bool,
  ) -> UUIDCollisionExplanation {
    var result = UUIDCollisionExplanation(relationships: [], reasons: [], originalPath: nil, duplicatePaths: [])
    let candidates = candidates.sorted { $0.path < $1.path }
    guard candidates.count > 1, candidates.count <= 256, Set(candidates.map(\.path)).count == candidates.count else {
      result.reasons = ["Supply distinct current holders of one UUID."]; return result
    }
    if !completeHolderSet { result.reasons.append("The current holder set is incomplete.") }
    if evidence.historyPruned || evidence.truncated { result.reasons.append("Evidence has been pruned or truncated.") }
    for candidate in candidates {
      guard let observation = evidence.observations.first(where: { $0.path == candidate.path }) else {
        result.reasons.append("No retained observation for \(candidate.path)."); continue
      }
      if !observation.verified || !observation.completeScan || observation.absent || observation.historyGap
        || observation.lastRevision != candidate.revision {
        result.reasons.append("Observation is incomplete, stale, or discontinuous for \(candidate.path).")
      }
    }
    var parents: [String: Set<String>] = [:]
    for event in evidence.events where event.kind == .copy || event.kind == .move {
      guard let source = event.sourcePath, source != event.path else { continue }
      let valid = event.kind == .copy && event.confirmation == .coordinator
        && candidates.contains(where: { $0.path == source && $0.revision == event.sourceRevision })
        && candidates.contains(where: { $0.path == event.path && $0.revision == event.revision })
      result.relationships.append(.init(source: source, destination: event.path,
        strength: valid ? .confirmed : .possible,
        reason: valid ? "Confirmed managed copy with matching current revisions." : "Retained operation does not establish ownership of these current holders."))
      if valid { parents[event.path, default: []].insert(source) }
    }
    // Equal hashes are useful explanations but carry no direction or ownership.
    for (offset, candidate) in candidates.enumerated() {
      for other in candidates.dropFirst(offset + 1) where candidate.revision == other.revision {
        result.relationships.append(.init(source: candidate.path, destination: other.path, strength: .possible,
          reason: "Matching content could reflect a copy, restore, or independent creation; direction is unknown."))
      }
    }
    let roots = candidates.filter { parents[$0.path] == nil }
    if result.reasons.isEmpty, roots.count == 1, let root = roots.first {
      var valid = true
      for candidate in candidates where candidate.path != root.path {
        var visited = Set<String>()
        var path = candidate.path
        while path != root.path {
          guard visited.insert(path).inserted, let values = parents[path], values.count == 1, let parent = values.first else {
            valid = false; break
          }
          path = parent
        }
      }
      if valid {
        result.originalPath = root.path
        result.duplicatePaths = candidates.filter { $0.path != root.path }.map(\.path)
        return result
      }
    }
    result.reasons.append("Discovery order, timestamps, and matching content do not establish UUID ownership. Select a target explicitly.")
    return result
  }
}
