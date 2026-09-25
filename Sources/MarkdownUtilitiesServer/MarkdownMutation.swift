import Foundation
import MarkdownUtilitiesCore

/// Reversible wire encoding; distinct from representation ETags and index generations.
public enum MarkdownRevisionHeader {
  public static func encode(_ revision: MarkdownRecordRevision) -> String {
    "r1." + Data(revision.rawValue.utf8).base64EncodedString()
  }
  public static func decode(_ value: String?) throws -> MarkdownRecordRevision {
    guard let value else { throw MarkdownMutationError(428, "revision.required", "Supply MD-Utils-If-Revision.") }
    guard value.utf8.count <= 4096, value.hasPrefix("r1."),
      let data = Data(base64Encoded: String(value.dropFirst(3))),
      let raw = String(data: data, encoding: .utf8), !raw.isEmpty,
      encode(.init(rawValue: raw)) == value else {
      throw MarkdownMutationError(400, "revision.invalid", "Expected a versioned canonical revision token.")
    }
    return .init(rawValue: raw)
  }
}

public struct MarkdownMutationError: Error, Sendable, LocalizedError {
  public let status: Int
  public let code: String
  public let message: String
  public let diagnostics: [MarkdownDiagnostic]
  public var errorDescription: String? { message }
  public init(_ status: Int, _ code: String, _ message: String, diagnostics: [MarkdownDiagnostic] = []) {
    self.status = status; self.code = code; self.message = message; self.diagnostics = diagnostics
  }
}

/// Strict transport envelope; no canonical identity, revision, or host context is writable.
public struct MarkdownMutationRequest: Sendable {
  public var lookupName: String?
  public let operation: MarkdownMutationOperation
  public let payload: [String: JSONValue]
  public let validationPolicy: ResourceMutationValidationPolicy
  public init(operation: MarkdownMutationOperation, data: Data) throws {
    guard data.count <= 8 * 1024 * 1024 else { throw MarkdownMutationError(413, "request.too-large", "Mutation exceeds 8 MiB.") }
    let payload: [String: JSONValue]
    if operation == .delete && data.isEmpty { payload = [:] }
    else {
      guard let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
        throw MarkdownMutationError(400, "request.invalid", "Expected a JSON object.")
      }
      payload = decoded
    }
    let allowed: Set<String>
    switch operation {
    case .create: allowed = ["frontmatter", "data", "identifiers", "filename"]
    case .replace, .patch: allowed = ["frontmatter", "body", "validationPolicy"]
    case .identity: allowed = ["identifiers", "validationPolicy"]
    case .repairUUID, .delete: allowed = []
    }
    guard Set(payload.keys).isSubset(of: allowed) else {
      throw MarkdownMutationError(400, "request.unknown-field", "Unknown request field.")
    }
    if let value = payload["validationPolicy"] {
      guard case .string(let raw) = value, let policy = ResourceMutationValidationPolicy(rawValue: raw) else {
        throw MarkdownMutationError(400, "request.policy", "Invalid validation policy.")
      }
      validationPolicy = policy
    } else { validationPolicy = .preserveExistingConformance }
    self.operation = operation; self.payload = payload
    _ = try body()
    if operation == .replace || operation == .patch { _ = try edit() }
    if operation == .create { _ = try object("frontmatter"); _ = try object("identifiers"); _ = try string("filename") }
    if operation == .identity { _ = try object("identifiers", required: true) }
  }
  public func object(_ key: String, required: Bool = false) throws -> [String: JSONValue] {
    guard let value = payload[key] else {
      if required { throw MarkdownMutationError(400, "request.missing-field", "Missing \(key) object.") }
      return [:]
    }
    guard case .object(let result) = value else {
      throw MarkdownMutationError(400, "request.invalid-field", "\(key) must be an object.")
    }
    return result
  }
  public func string(_ key: String) throws -> String? {
    guard let value = payload[key] else { return nil }
    guard case .string(let result) = value else {
      throw MarkdownMutationError(400, "request.invalid-field", "\(key) must be a string.")
    }
    return result
  }
  public func body() throws -> String? { try string("body") }
  public func edit() throws -> ResourceEdit {
    if operation == .replace { return .replace(frontmatter: try object("frontmatter", required: true), body: try body()) }
    let patch = try object("frontmatter")
    guard Set(patch.keys).isSubset(of: ["set", "remove"]) else {
      throw MarkdownMutationError(400, "request.patch", "Patch accepts set and remove only.")
    }
    var changes: [String: ResourceFieldPatch] = [:]
    if let set = patch["set"] {
      guard case .object(let values) = set else { throw MarkdownMutationError(400, "request.patch", "set must be an object.") }
      for (key, value) in values { changes[key] = .set(value) }
    }
    if let remove = patch["remove"] {
      guard case .array(let values) = remove else { throw MarkdownMutationError(400, "request.patch", "remove must be an array.") }
      for value in values {
        guard case .string(let key) = value, changes[key] == nil else {
          throw MarkdownMutationError(400, "request.patch", "Removal names must be unique and not also set.")
        }
        changes[key] = .remove
      }
    }
    return .patch(frontmatter: changes, body: try body())
  }
}

/// Receipt persisted independently of rebuildable index projections.
public struct MarkdownMutationReceipt: Codable, Sendable {
  public enum State: String, Codable, Sendable { case prepared, committed, completed, recoveryRequired, abandoned }
  public var state: State
  public var sourceCommitted: Bool
  public let id: String
  public let resource: String
  public let operation: MarkdownMutationOperation
  public let path: MarkdownRecordPath
  public let revision: MarkdownRecordRevision?
  public let baseline: MarkdownRecordRevision?
  public let requestHash: String
  public let keyHash: String?
  public let created: Date
  public var completedAt: Date?
  public var record: GenericMarkdownRecord?
  public var lostConformance: [String]
  public var lostMembership: [String]
  public var diagnostics: [MarkdownDiagnostic]
  public var validationPolicy: ResourceMutationValidationPolicy
  public var conformanceChanges: [ResourceConformanceChange]
  public var committed: Bool { sourceCommitted }
  public init(id: String = UUID().uuidString.lowercased(), resource: String, operation: MarkdownMutationOperation,
    path: MarkdownRecordPath, revision: MarkdownRecordRevision?, baseline: MarkdownRecordRevision?,
    requestHash: String, keyHash: String?, lostConformance: [String] = [], lostMembership: [String] = [],
    diagnostics: [MarkdownDiagnostic] = [],
  ) {
    state = .prepared; sourceCommitted = false; self.id = id; self.resource = resource; self.operation = operation; self.path = path
    self.revision = revision; self.baseline = baseline; self.requestHash = requestHash; self.keyHash = keyHash
    validationPolicy = .preserveExistingConformance; conformanceChanges = []
    created = Date(); completedAt = nil; self.lostConformance = lostConformance; self.lostMembership = lostMembership
    self.diagnostics = diagnostics
  }
}

public enum MarkdownRecoveryDecision: String, Codable, Sendable {
  /// Operator confirms the proposed change committed; the current source must match.
  case confirmCommitted
  /// Operator confirms no change committed; the current source must match the baseline.
  case confirmNotCommitted
}

public protocol MarkdownMutationService: Sendable {
  func resolveOperation(resource: String, id: String, decision: MarkdownRecoveryDecision) async throws -> MarkdownMutationReceipt
  func mutate(resource: String, identity: String?, path: MarkdownRecordPath?,
    request: MarkdownMutationRequest, revision: MarkdownRecordRevision?, idempotencyKey: String?,
  ) async throws -> MarkdownMutationReceipt
  func operation(resource: String, id: String) async throws -> MarkdownMutationReceipt
}
