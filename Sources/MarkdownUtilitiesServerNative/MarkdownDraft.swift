import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer

/// An explicit, revision-bound edit stored independently of disposable index content.
public struct MarkdownDraft: Codable, Sendable {
  /// Durable lifecycle; a submitted attempt must be recovered before it can be discarded.
  public enum State: String, Codable, Sendable {
    /// Intent has not been submitted to the mutation coordinator.
    case pending
    /// Planning found a conflict or invalid proposal; the baseline remains unchanged.
    case conflict
    /// An attempt owns a stable receipt ID and may have persisted source.
    case submitted
    /// Source persistence is confirmed but index publication is incomplete.
    case publicationPending
    /// The coordinator cannot establish a terminal outcome without operator resolution.
    case recoveryRequired
    /// Source persistence and publication completed.
    case completed
  }

  /// Version of the JSON draft format, independent of the index cache format.
  public let version: Int
  /// Lowercase UUID identifying this draft.
  public let id: String
  /// Original collection-relative source locator, retained after managed relocation.
  public let path: MarkdownRecordPath
  /// Explicit configured resource supplying codec, selection, and write opt-ins.
  public let resource: String
  /// SHA-256 of authoritative source against which the intent was authored.
  public let baseline: MarkdownRecordRevision
  /// Normalized configured persistent UUID, or nil for a document without one.
  public let uuid: String?
  /// Configured metadata path used to interpret the UUID, or nil when unconfigured.
  public let uuidPath: [String]?
  /// Cache epoch at staging; nil or a changed epoch prevents automatic move following.
  public let provenanceEpoch: String?
  /// Immutable configuration/registry fingerprint used when staging this draft.
  public let configurationFingerprint: String
  /// Patch or replacement operation; other operations are rejected when loading drafts.
  public let operation: MarkdownMutationOperation
  /// Shared mutation envelope, including any explicitly selected validation policy.
  public let payload: [String: JSONValue]
  /// Staging timestamp; discovery order does not establish document ownership.
  public let created: Date
  /// Durable draft lifecycle state.
  public internal(set) var state: State
  /// Stable receipt ID allocated and synced before submitting a source mutation.
  public internal(set) var attemptID: String?
  /// Locator bound to the current attempt, which may differ after a verified move.
  public internal(set) var resolvedPath: MarkdownRecordPath?
  /// Last apply conflict or failure code; dry-run never updates this field.
  public internal(set) var failureCode: String?
  /// Last apply conflict or failure explanation.
  public internal(set) var failureMessage: String?

  init(path: MarkdownRecordPath, resource: String, baseline: MarkdownRecordRevision,
    uuid: String?, uuidPath: [String]?, epoch: String?, fingerprint: String,
    request: MarkdownMutationRequest,
  ) {
    version = 1; id = UUID().uuidString.lowercased(); self.path = path; self.resource = resource
    self.baseline = baseline; self.uuid = uuid; self.uuidPath = uuidPath; provenanceEpoch = epoch
    configurationFingerprint = fingerprint; operation = request.operation; payload = request.payload
    created = Date(); state = .pending
  }

  func request() throws -> MarkdownMutationRequest {
    try MarkdownMutationRequest(operation: operation, data: JSONEncoder().encode(payload))
  }
}

/// One bounded preview or execution result; concrete source is present only during planning.
public struct MarkdownDraftReport: Codable, Sendable {
  /// Draft whose intent was assessed.
  public let draftID: String
  /// Current durable draft state; dry-run does not mutate it.
  public var state: MarkdownDraft.State
  /// Resolved source locator, if established.
  public var path: MarkdownRecordPath?
  /// Human-readable target-resolution evidence or uncertainty.
  public var resolution: String?
  /// Authoritative baseline source for a concrete dry-run preview.
  public var originalSource: String?
  /// Exact codec output for a concrete dry-run preview.
  public var proposedSource: String?
  /// Canonical source hash of the proposed bytes.
  public var proposedRevision: MarkdownRecordRevision?
  /// Shared validation diagnostics, including structured fix-its.
  public var diagnostics: [MarkdownDiagnostic] = []
  /// Full before/after contract assessments, separating selection from conformance.
  public var conformanceChanges: [ResourceConformanceChange] = []
  /// Blocking machine-readable failure code, if any.
  public var failureCode: String?
  /// Blocking human-readable explanation, if any.
  public var failureMessage: String?
  /// Durable mutation receipt, when this draft has been submitted.
  public var receipt: MarkdownMutationReceipt?
  /// Whether this result permits proceeding; an incomplete receipt is not success.
  public var succeeded: Bool { failureCode == nil && (receipt == nil || receipt?.state == .completed) }

  init(_ draft: MarkdownDraft) { draftID = draft.id; state = draft.state }
}
