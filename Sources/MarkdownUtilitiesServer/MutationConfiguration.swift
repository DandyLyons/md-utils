import Foundation
import MarkdownUtilitiesCore

/// Write capabilities are separate from read operations and require configuration v3.
public enum MarkdownMutationOperation: String, Codable, CaseIterable, Sendable {
  /// Creates a document through the configured creation codec and allocation policy.
  case create
  /// Replaces the complete writable projection of an existing document.
  case replace
  /// Applies a partial update to writable metadata or body content.
  case patch
  /// Deletes the canonical document rather than only its resource membership.
  case delete
  /// Updates explicitly configured identity fields on a selected document.
  case identity
  /// Assigns a new UUID to an explicitly selected document without rewriting references.
  case repairUUID
  /// Copies a document with a fresh UUID when persistent UUID identity is configured.
  ///
  /// Requires a source revision, an idempotency key, and a destination filename.
  /// The destination must not exist; creation templates are not rendered.
  case copy
  /// Relocates a document while preserving its source bytes and configured UUID.
  ///
  /// Requires a source revision and an idempotency key. Native recovery coordinates
  /// both paths; the operation is not an atomic filesystem transaction.
  case move

  /// The HTTP method used by this operation's configured routes.
  public var method: EndpointHTTPMethod {
    switch self {
    case .create, .identity, .repairUUID, .copy, .move: .post
    case .replace: .put
    case .patch: .patch
    case .delete: .delete
    }
  }
}

/// Host-owned allocation settings. Filenames are never slugified.
public struct MarkdownCreationAllocation: Codable, Equatable, Sendable {
  public let directory: MarkdownSearchRoot
  public let filenameField: String
  public let collision: Collision
  public let identifiers: [String]
  public let slug: Slug?
  public enum Collision: String, Codable, Sendable { case reject, suffix }
  public struct Slug: Codable, Equatable, Sendable {
    public let field: String
    public let sourceField: String
    public let policy: MarkdownSlugPolicy
    public let collision: Collision
    public init(field: String, sourceField: String = "title", policy: MarkdownSlugPolicy = .unicode, collision: Collision = .reject) {
      self.field = field; self.sourceField = sourceField; self.policy = policy; self.collision = collision
    }
    public init(from decoder: Decoder) throws {
      try rejectUnknownLookupKeys(decoder, allowed: ["field", "sourceField", "policy", "collision"])
      let c = try decoder.container(keyedBy: CodingKeys.self)
      self.init(field: try c.decode(String.self, forKey: .field),
        sourceField: try c.decodeIfPresent(String.self, forKey: .sourceField) ?? "title",
        policy: try c.decodeIfPresent(MarkdownSlugPolicy.self, forKey: .policy) ?? .unicode,
        collision: try c.decodeIfPresent(Collision.self, forKey: .collision) ?? .reject)
    }
  }
  public init(directory: MarkdownSearchRoot, filenameField: String = "title",
    collision: Collision = .reject, identifiers: [String] = [], slug: Slug? = nil,
  ) {
    self.directory = directory; self.filenameField = filenameField
    self.collision = collision; self.identifiers = identifiers; self.slug = slug
  }
  public init(from decoder: Decoder) throws {
    try rejectUnknownLookupKeys(decoder, allowed: ["directory", "filenameField", "collision", "identifiers", "slug"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(directory: try c.decode(MarkdownSearchRoot.self, forKey: .directory),
      filenameField: try c.decodeIfPresent(String.self, forKey: .filenameField) ?? "title",
      collision: try c.decodeIfPresent(Collision.self, forKey: .collision) ?? .reject,
      identifiers: try c.decodeIfPresent([String].self, forKey: .identifiers) ?? [],
      slug: try c.decodeIfPresent(Slug.self, forKey: .slug))
  }
}

/// Configured per resource, never per Markdown document.
public struct MarkdownMutationConfiguration: Codable, Equatable, Sendable {
  public let operations: [MarkdownMutationOperation]
  public let creation: MarkdownCreationAllocation?
  public let identityFields: [String]
  public let idempotencyRetentionSeconds: Int
  public init(operations: [MarkdownMutationOperation], creation: MarkdownCreationAllocation? = nil,
    identityFields: [String] = [], idempotencyRetentionSeconds: Int = 604_800,
  ) {
    self.operations = operations; self.creation = creation; self.identityFields = identityFields
    self.idempotencyRetentionSeconds = idempotencyRetentionSeconds
  }
  public init(from decoder: Decoder) throws {
    try rejectUnknownLookupKeys(decoder, allowed: ["operations", "creation", "identityFields", "idempotencyRetentionSeconds"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(operations: try c.decode([MarkdownMutationOperation].self, forKey: .operations),
      creation: try c.decodeIfPresent(MarkdownCreationAllocation.self, forKey: .creation),
      identityFields: try c.decodeIfPresent([String].self, forKey: .identityFields) ?? [],
      idempotencyRetentionSeconds: try c.decodeIfPresent(Int.self, forKey: .idempotencyRetentionSeconds) ?? 604_800)
  }
}
