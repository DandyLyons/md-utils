import Foundation

/// The supported version of the md-utils Markdown type-definition schema.
public enum MarkdownTypeSchemaVersion {
  public static let current = "1"
}

/// A stable, case-sensitive Markdown type name.
public struct MarkdownTypeName: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// Controls how absent frontmatter is treated by a type definition.
public enum MarkdownFrontmatterPresence: String, Codable, Equatable, Sendable {
  case required
  case optional
}

/// An inline or referenced JSON Schema resource.
public enum MarkdownJSONSchemaSource: Equatable, Sendable {
  case inline(JSONValue)
  case reference(String)
}

/// Frontmatter constraints for a Markdown type.
public struct MarkdownFrontmatterDefinition: Equatable, Sendable {
  public var presence: MarkdownFrontmatterPresence?
  public var schemas: [MarkdownJSONSchemaSource]

  public init(
    presence: MarkdownFrontmatterPresence? = nil,
    schemas: [MarkdownJSONSchemaSource] = []
  ) {
    self.presence = presence
    self.schemas = schemas
  }

  /// The explicit or inferred presence behavior.
  public var effectivePresence: MarkdownFrontmatterPresence? {
    presence ?? (schemas.isEmpty ? nil : .required)
  }
}

/// Matches a Markdown heading by rendered text and, optionally, level.
public struct MarkdownHeadingPredicate: Codable, Equatable, Sendable {
  public var text: String
  public var level: Int?

  public init(text: String, level: Int? = nil) {
    self.text = text
    self.level = level
  }
}

/// Supported relationships between two headings.
public enum MarkdownHeadingRelationship: String, Codable, Equatable, Sendable {
  case directChild
  case descendant
}

/// Requires a relationship between matching parent and child headings.
public struct MarkdownHeadingRelationshipPredicate: Codable, Equatable, Sendable {
  public var parent: MarkdownHeadingPredicate
  public var child: MarkdownHeadingPredicate
  public var relationship: MarkdownHeadingRelationship

  public init(
    parent: MarkdownHeadingPredicate,
    child: MarkdownHeadingPredicate,
    relationship: MarkdownHeadingRelationship
  ) {
    self.parent = parent
    self.child = child
    self.relationship = relationship
  }
}

/// Controls whether a section must contain direct body content.
public enum MarkdownSectionContentRequirement: String, Codable, Equatable, Sendable {
  case any
  case nonEmpty
}

/// Matches a Markdown section and optionally its direct content.
public struct MarkdownSectionPredicate: Codable, Equatable, Sendable {
  public var heading: MarkdownHeadingPredicate
  public var content: MarkdownSectionContentRequirement

  public init(
    heading: MarkdownHeadingPredicate,
    content: MarkdownSectionContentRequirement = .any
  ) {
    self.heading = heading
    self.content = content
  }
}

/// Matches the logical path associated with a Markdown record.
public struct MarkdownPathPredicate: Codable, Equatable, Sendable {
  public var glob: String

  public init(glob: String) {
    self.glob = glob
  }
}

/// Portable structural predicates shared by Markdown types and rules.
public enum MarkdownPredicate: Equatable, Sendable {
  case heading(MarkdownHeadingPredicate)
  case headingRelationship(MarkdownHeadingRelationshipPredicate)
  case section(MarkdownSectionPredicate)
  case path(MarkdownPathPredicate)
  case maxBodyLines(Int)
  case maxBodyWords(Int)
}

/// A stable constraint and its predicate.
public struct MarkdownConstraint: Equatable, Sendable {
  public var id: String
  public var predicate: MarkdownPredicate

  public init(id: String, predicate: MarkdownPredicate) {
    self.id = id
    self.predicate = predicate
  }
}

/// Required and recommended constraints within one conformance domain.
public struct MarkdownConstraintGroup: Equatable, Sendable {
  public var requirements: [MarkdownConstraint]
  public var recommendations: [MarkdownConstraint]

  public init(
    requirements: [MarkdownConstraint] = [],
    recommendations: [MarkdownConstraint] = []
  ) {
    self.requirements = requirements
    self.recommendations = recommendations
  }
}

/// A named, versioned structural contract for complete Markdown records.
public struct MarkdownTypeDefinition: Equatable, Sendable {
  public var typeSchemaVersion: String
  public var name: MarkdownTypeName
  public var version: String
  public var frontmatter: MarkdownFrontmatterDefinition
  public var body: MarkdownConstraintGroup
  public var context: MarkdownConstraintGroup
  public var source: String?

  public init(
    typeSchemaVersion: String = MarkdownTypeSchemaVersion.current,
    name: MarkdownTypeName,
    version: String,
    frontmatter: MarkdownFrontmatterDefinition = MarkdownFrontmatterDefinition(),
    body: MarkdownConstraintGroup = MarkdownConstraintGroup(),
    context: MarkdownConstraintGroup = MarkdownConstraintGroup(),
    source: String? = nil
  ) {
    self.typeSchemaVersion = typeSchemaVersion
    self.name = name
    self.version = version
    self.frontmatter = frontmatter
    self.body = body
    self.context = context
    self.source = source
  }
}

/// A JSON Schema resource returned by a host-specific resolver.
public struct MarkdownSchemaResource: Equatable, Sendable {
  /// A canonical identifier used as the base for nested references.
  public var source: String
  public var schema: JSONValue

  public init(source: String, schema: JSONValue) {
    self.source = source
    self.schema = schema
  }
}

/// Resolves JSON Schema references without assuming a filesystem or network.
public protocol MarkdownSchemaResourceProvider: Sendable {
  func resource(reference: String, relativeTo source: String?) throws -> MarkdownSchemaResource
}
