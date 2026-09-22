import Foundation
import MarkdownUtilitiesCore

/// Write capabilities are separate from read operations and require configuration v3.
public enum MarkdownMutationOperation: String, Codable, CaseIterable, Sendable {
  case create, replace, patch, delete, identity, repairUUID

  public var method: EndpointHTTPMethod {
    switch self {
    case .create, .identity, .repairUUID: .post
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
