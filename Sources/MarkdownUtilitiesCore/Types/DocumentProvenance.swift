import Foundation

/// A retained summary of observations at one collection-relative path.
///
/// Revisions and times describe observations within one index epoch, not creation
/// dates or canonical identity. The summary cannot reconstruct document content.
public struct DocumentObservation: Codable, Equatable, Sendable {
  /// The collection-relative path, including the filename.
  public var path: String
  /// The earliest retained content revision, or `nil` when unavailable.
  public var firstRevision: String?
  /// The latest retained content revision, or `nil` when unavailable.
  public var lastRevision: String?
  /// The publication generation that first retained this path in the epoch.
  public var firstGeneration: Int
  /// The latest publication generation that observed this path.
  public var lastGeneration: Int
  /// The first retained observation time, in seconds since the Unix epoch.
  public var firstObservedAt: Double
  /// The latest observation time, in seconds since the Unix epoch.
  public var lastObservedAt: Double
  /// Whether the latest observation verified the source bytes successfully.
  public var verified: Bool
  /// Whether the refresh that last observed this path completed its scan.
  public var completeScan: Bool
  /// Whether the path is absent from the current indexed file set.
  public var absent: Bool
  /// Whether retained observations include a disappearance or scan discontinuity.
  public var historyGap: Bool

  /// Creates a summary from host-supplied observations without validating them.
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

/// A retained managed operation with an explicit confirmation source.
///
/// Hosts record these events from confirmed mutation receipts. An operator's
/// confirmation is weaker evidence than a coordinator-verified source commit.
/// Constructing an event does not verify that an operation occurred.
public struct ManagedDocumentEvent: Codable, Equatable, Sendable {
  /// The operation recorded by the mutation coordinator.
  public enum Kind: String, Codable, Sendable {
    /// Creation of a new document.
    case create
    /// A content or metadata edit.
    case edit
    /// An intentional identity change.
    case identity
    /// A targeted UUID repair.
    case repairUUID
    /// Removal of a document.
    case delete
    /// Creation of a document from an existing source.
    case copy
    /// Relocation of a document to another path.
    case move
  }
  /// How the host established that a managed operation occurred.
  public enum Confirmation: String, Codable, Sendable {
    /// The coordinator verified the source-file commit.
    case coordinator
    /// An operator resolved an otherwise unconfirmed operation.
    case operatorConfirmed
  }
  /// The durable receipt identifier used to make evidence replay idempotent.
  public var id: String
  /// The managed operation's category.
  public var kind: Kind
  /// The affected collection-relative path; the destination for copy and move.
  public var path: String
  /// The resulting revision, or `nil` when the operation has no retained result.
  public var revision: String?
  /// The collection-relative source path for a transfer, when available.
  public var sourcePath: String?
  /// The source revision before the operation, when available.
  public var sourceRevision: String?
  /// The evidence used to confirm the operation.
  public var confirmation: Confirmation
  /// The event observation time, in seconds since the Unix epoch.
  public var observedAt: Double

  /// Creates an event from host-supplied receipt details without verifying them.
  public init(id: String, kind: Kind, path: String, revision: String?, sourcePath: String? = nil,
    sourceRevision: String? = nil, confirmation: Confirmation = .coordinator, observedAt: Double,
  ) {
    self.id = id; self.kind = kind; self.path = path; self.revision = revision
    self.sourcePath = sourcePath; self.sourceRevision = sourceRevision
    self.confirmation = confirmation; self.observedAt = observedAt
  }
}

/// A bounded selection of observations and managed events from one cache epoch.
public struct DocumentProvenanceEvidence: Codable, Equatable, Sendable {
  /// The cache lifetime identifier; a full rebuild starts a new epoch.
  public var epoch: String
  /// Retained summaries for the requested paths, which may omit unknown paths.
  public var observations: [DocumentObservation]
  /// Retained managed events involving the requested paths.
  public var events: [ManagedDocumentEvent]
  /// Whether retention has discarded history anywhere in this epoch.
  public var historyPruned: Bool
  /// Whether the query omitted matching events to satisfy its result limit.
  public var truncated: Bool
  /// Creates an evidence bundle without checking completeness or consistency.
  public init(epoch: String, observations: [DocumentObservation], events: [ManagedDocumentEvent],
    historyPruned: Bool = false, truncated: Bool = false,
  ) {
    self.epoch = epoch; self.observations = observations; self.events = events
    self.historyPruned = historyPruned; self.truncated = truncated
  }
}

/// A current holder of the UUID being assessed, verified by the calling host.
public struct UUIDCollisionCandidate: Codable, Equatable, Sendable {
  /// The holder's collection-relative path.
  public var path: String
  /// The current source revision verified from the holder's bytes.
  public var revision: String
  /// Creates a candidate without reading its file or validating its UUID.
  public init(path: String, revision: String) { self.path = path; self.revision = revision }
}

/// An explanation of candidate relationships and remaining ownership uncertainty.
public struct UUIDCollisionExplanation: Codable, Equatable, Sendable {
  /// A directed relationship reported by retained evidence or a content match.
  public struct Relationship: Codable, Equatable, Sendable {
    /// The strength of a relationship, independent of the overall recommendation.
    public enum Strength: String, Codable, Sendable {
      /// Evidence cannot establish the direction or current ownership.
      case possible
      /// A coordinator-confirmed copy matches both holders' current revisions.
      case confirmed
    }
    /// The proposed source path; possible relationships do not establish direction.
    public var source: String
    /// The proposed destination path.
    public var destination: String
    /// Whether retained evidence confirms this particular copy relationship.
    public var strength: Strength
    /// A human-readable explanation of the relationship's strength.
    public var reason: String
  }
  /// Relationships that may remain useful even when overall ownership is ambiguous.
  public var relationships: [Relationship]
  /// Human-readable reasons that prevent an ownership recommendation.
  public var reasons: [String]
  /// A recommendation only; never permission to write a source file.
  public var originalPath: String?
  /// Other current holders, sorted by path, when an original is recommended.
  public var duplicatePaths: [String]
  /// Whether the evidence does not identify a recommended original.
  public var ambiguous: Bool { originalPath == nil }
}

/// Assesses UUID collisions without filesystem access or permission to mutate files.
public enum UUIDCollisionAssessor {
  /// Explains a collision using current holders and retained partial evidence.
  ///
  /// A recommendation requires continuous, complete, verified observations and
  /// a single rooted graph of coordinator-confirmed copies matching current
  /// revisions. Pruned history, truncated evidence, or an incomplete holder set
  /// prevents a recommendation. Discovery order, timestamps, and equal content
  /// do not establish ownership. Managed moves alone do not establish a copy.
  ///
  /// - Parameters:
  ///   - candidates: Two to 256 distinct paths holding the same normalized UUID.
  ///     The host must verify their current revisions and UUID membership.
  ///   - evidence: Retained evidence from a single current cache epoch.
  ///   - completeHolderSet: Whether the host found every current holder,
  ///     including documents outside exposed resource selections.
  /// - Returns: An explanation with an optional recommendation. Invalid candidate
  ///   counts or repeated paths produce ambiguity rather than throwing an error.
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
