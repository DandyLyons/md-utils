import Foundation

/// An immutable, serialization-ready view of one Markdown type's frontmatter contract.
public struct ResolvedMarkdownTypeFrontmatterSchema: Codable, Equatable, Sendable {
  /// Stable type name associated with the schemas.
  public let name: MarkdownTypeName
  /// Version of the Markdown type definition.
  public let version: String
  /// Whether frontmatter is required, optional, or unconstrained by the type.
  public let presence: MarkdownFrontmatterPresence?
  /// Fully resolved JSON Schema Draft 2020-12 documents in declaration order.
  public let schemas: [JSONValue]
  public var recommendedSchemas: [JSONValue] = []
  public var typeSchemaVersion: String = "1"
  public var requires: [String] = []

  private enum CodingKeys: String, CodingKey {
    case name, version, presence, schemas, recommendedSchemas, typeSchemaVersion, requires
  }

  /// Older serialized views predate the capability gate; omission means no requirements.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(MarkdownTypeName.self, forKey: .name)
    version = try container.decode(String.self, forKey: .version)
    presence = try container.decodeIfPresent(MarkdownFrontmatterPresence.self, forKey: .presence)
    schemas = try container.decode([JSONValue].self, forKey: .schemas)
    recommendedSchemas = try container.decodeIfPresent([JSONValue].self, forKey: .recommendedSchemas) ?? []
    typeSchemaVersion = try container.decodeIfPresent(String.self, forKey: .typeSchemaVersion) ?? "1"
    requires = try container.decodeIfPresent([String].self, forKey: .requires) ?? []
  }

  /// Creates an immutable frontmatter schema view.
  public init(
    name: MarkdownTypeName,
    version: String,
    presence: MarkdownFrontmatterPresence?,
    schemas: [JSONValue]
  ) {
    self.name = name
    self.version = version
    self.presence = presence
    self.schemas = schemas
  }
}

/// An immutable collection of validated and schema-resolved Markdown types.
public struct MarkdownTypeRegistry: Sendable {
  private var definitionsByName: [MarkdownTypeName: MarkdownTypeDefinition]
  private var schemasByName: [MarkdownTypeName: [JSONValue]]
  public let typeResourceBindings: [String: MarkdownTypeName]
  /// Canonical top-level schema bindings, including v1 schemas without an authored $id.
  package let schemaResourceSources: Set<String>

  public init(
    definitions: [MarkdownTypeDefinition],
    schemaProvider: (any MarkdownSchemaResourceProvider)? = nil,
    typeResourceBindings: [String: MarkdownTypeName] = [:],
  ) throws {
    var definitionsByName: [MarkdownTypeName: MarkdownTypeDefinition] = [:]
    var schemasByName: [MarkdownTypeName: [JSONValue]] = [:]
    var schemaResourceSources: Set<String> = []

    for definition in definitions {
      try Self.checkCapabilities(definition.requires, version: definition.typeSchemaVersion)
      guard MarkdownTypeSchemaVersion.supported.contains(definition.typeSchemaVersion) else {
        throw MarkdownTypeDefinitionError.unsupportedSchemaVersion(definition.typeSchemaVersion)
      }
      guard definition.typeSchemaVersion == "2" || definition.frontmatter.recommendedSchemas.isEmpty else {
        throw MarkdownTypeDefinitionError.invalidField("recommendedSchemas requires mdtype v2")
      }
      guard definitionsByName[definition.name] == nil else {
        throw MarkdownTypeDefinitionError.duplicateType(definition.name.rawValue)
      }

      let constraintIDs = definition.body.requirements.map(\.id)
        + definition.body.recommendations.map(\.id)
        + definition.context.requirements.map(\.id)
        + definition.context.recommendations.map(\.id)
      var seenIDs: Set<String> = []
      for id in constraintIDs {
        guard seenIDs.insert(id).inserted else {
          throw MarkdownTypeDefinitionError.duplicateConstraint(type: definition.name.rawValue, id: id)
        }
      }

      let compiler = MarkdownSchemaGraphCompiler(
        typeName: definition.name.rawValue,
        provider: schemaProvider,
        semanticProfile: definition.typeSchemaVersion == "2",
      )
      let schemas = try (definition.frontmatter.schemas + definition.frontmatter.recommendedSchemas).map { source in
        switch source {
        case .inline(let value):
          return try compiler.compile(value, source: definition.source)
        case .reference(let reference):
          guard let schemaProvider else {
            throw MarkdownTypeDefinitionError.unresolvedSchema(
              type: definition.name.rawValue,
              reference: reference
            )
          }
          let resource = try schemaProvider.resource(
            reference: reference,
            relativeTo: definition.source
          )
          schemaResourceSources.insert(resource.source)
          return try compiler.compile(resource.schema, source: resource.source)
        }
      }
      if definition.typeSchemaVersion == "2" {
        for schema in schemas {
          try SemanticSchemaAdapter.check(schema, capabilities: Set(definition.requires))
          try SemanticSchemaDiagnostics(
            root: schema, instance: .null, nativePaths: [], severity: .error,
            constraint: definition.name.rawValue, source: definition.source,
          ).checkReferences()
        }
      }

      definitionsByName[definition.name] = definition
      schemasByName[definition.name] = schemas
    }

    self.definitionsByName = definitionsByName
    self.schemasByName = schemasByName
    self.typeResourceBindings = typeResourceBindings
    self.schemaResourceSources = schemaResourceSources
    for definition in definitions {
      guard definition.relationships.isEmpty || definition.requires.contains("document-relationships") else {
        throw MarkdownTypeDefinitionError.invalidField("relationship.definition.capability: relationships requires document-relationships")
      }
      for (name, relation) in definition.relationships {
        guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines) else {
          throw MarkdownRelationshipDefinition.invalid("relationship names must be nonempty without surrounding whitespace")
        }
        try relation.validate()
        guard let target = typeResourceBindings[relation.target], definitionsByName[target] != nil else {
          throw MarkdownRelationshipDefinition.invalid("unbound target type resource: \(relation.target)")
        }
      }
    }
  }

  /// Reject unsupported capabilities for decoded and programmatically constructed definitions.
  static func checkCapabilities(_ names: [String], version: String) throws {
    guard (version == "2" || names.isEmpty), Set(names).count == names.count,
      Set(names).isSubset(of: ["wikilink-constraints", "document-relationships"]) else {
      throw MarkdownTypeDefinitionError.invalidField("type.format.capability: unsupported or duplicate requires capability; supported in mdtype v2: wikilink-constraints, document-relationships")
    }
  }

  /// All definitions ordered by case-sensitive type name.
  public var definitions: [MarkdownTypeDefinition] {
    definitionsByName.values.sorted { $0.name.rawValue < $1.name.rawValue }
  }

  public func definition(named name: MarkdownTypeName) -> MarkdownTypeDefinition? {
    definitionsByName[name]
  }

  public func definition(named name: String) -> MarkdownTypeDefinition? {
    definition(named: MarkdownTypeName(rawValue: name))
  }

  /// Returns the resolved, read-only frontmatter contract for a loaded type.
  ///
  /// External references are already resolved into the returned schemas, so consumers
  /// can inspect or publish the contract without retaining the registry's resource provider.
  ///
  /// - Parameter name: Type whose frontmatter contract should be inspected.
  /// - Returns: The resolved contract, or `nil` when the type is not loaded.
  public func resolvedFrontmatterSchema(
    for name: MarkdownTypeName
  ) -> ResolvedMarkdownTypeFrontmatterSchema? {
    guard let definition = definitionsByName[name] else { return nil }
    var uniqueSchemas: [JSONValue] = []
    for schema in resolvedSchemas(for: name) where uniqueSchemas.contains(schema) == false {
      uniqueSchemas.append(schema)
    }
    var result = ResolvedMarkdownTypeFrontmatterSchema(
      name: name,
      version: definition.version,
      presence: definition.frontmatter.effectivePresence,
      schemas: uniqueSchemas
    )
    result.recommendedSchemas = resolvedRecommendedSchemas(for: name)
    result.typeSchemaVersion = definition.typeSchemaVersion
    result.requires = definition.requires
    return result
  }

  func resolvedSchemas(for name: MarkdownTypeName) -> [JSONValue] {
    Array((schemasByName[name] ?? []).prefix(definitionsByName[name]?.frontmatter.schemas.count ?? 0))
  }

  func resolvedRecommendedSchemas(for name: MarkdownTypeName) -> [JSONValue] {
    Array((schemasByName[name] ?? []).dropFirst(definitionsByName[name]?.frontmatter.schemas.count ?? 0))
  }
}

private final class MarkdownSchemaGraphCompiler {
  private let typeName: String
  private let provider: (any MarkdownSchemaResourceProvider)?
  private let semanticProfile: Bool
  private var resources: [String: JSONValue] = [:]
  private var activeResources: [String] = []
  private var identifiers: [String: JSONValue] = [:]

  init(typeName: String, provider: (any MarkdownSchemaResourceProvider)?, semanticProfile: Bool) {
    self.typeName = typeName
    self.provider = provider
    self.semanticProfile = semanticProfile
  }

  func compile(_ schema: JSONValue, source: String?) throws -> JSONValue {
    guard schema.objectValue != nil else {
      throw MarkdownTypeDefinitionError.schemaNotAnObject(type: typeName)
    }
    resources = [:]
    activeResources = source.map { [$0] } ?? []
    let root = try rewrite(schema, source: source)
    guard case .object(var rootObject) = root else {
      throw MarkdownTypeDefinitionError.schemaNotAnObject(type: typeName)
    }
    if rootObject["$schema"] == nil {
      rootObject["$schema"] = .string("https://json-schema.org/draft/2020-12/schema")
    }
    if semanticProfile, rootObject["$id"] == nil, let source {
      rootObject["$id"] = .string(source)
    }
    guard resources.isEmpty == false else { return .object(rootObject) }

    var definitions = rootObject["$defs"]?.objectValue ?? [:]
    for (index, key) in resources.keys.sorted().enumerated() {
      var definitionKey = "mdUtilsResource\(index)"
      while definitions[definitionKey] != nil {
        definitionKey += "_"
      }
      definitions[definitionKey] = resources[key]
    }
    rootObject["$defs"] = .object(definitions)
    return .object(rootObject)
  }

  private func rewrite(_ value: JSONValue, source: String?) throws -> JSONValue {
    switch value {
    case .array(let values):
      return .array(try values.map { try rewrite($0, source: source) })
    case .object(var object):
      try recordIdentifier(in: value)
      if let reference = object["$ref"]?.stringValue,
         reference.hasPrefix("#") == false {
        guard let provider else {
          throw MarkdownTypeDefinitionError.unresolvedSchema(type: typeName, reference: reference)
        }
        let parts = splitReference(reference)
        let resource = try provider.resource(reference: parts.resource, relativeTo: source)
        if activeResources.contains(resource.source) {
          let cycleStart = activeResources.firstIndex(of: resource.source) ?? activeResources.startIndex
          throw MarkdownTypeDefinitionError.schemaReferenceCycle(
            type: typeName,
            resources: Array(activeResources[cycleStart...]) + [resource.source]
          )
        }
        if resources[resource.source] == nil {
          activeResources.append(resource.source)
          var resolved = try rewrite(resource.schema, source: resource.source)
          activeResources.removeLast()
          guard case .object(var resourceObject) = resolved else {
            throw MarkdownTypeDefinitionError.schemaNotAnObject(type: typeName)
          }
          resourceObject["$id"] = .string(resource.source)
          resolved = .object(resourceObject)
          resources[resource.source] = resolved
        }
        object["$ref"] = .string(resource.source + parts.fragment)
      }
      for (key, child) in object where key != "$ref" {
        object[key] = try rewrite(child, source: source)
      }
      return .object(object)
    default:
      return value
    }
  }

  private func recordIdentifier(in schema: JSONValue) throws {
    guard case .object(let object) = schema,
          let identifier = object["$id"]?.stringValue else { return }
    if let existing = identifiers[identifier], existing != schema {
      throw MarkdownTypeDefinitionError.conflictingSchemaIdentifier(
        type: typeName,
        identifier: identifier
      )
    }
    identifiers[identifier] = schema
  }

  private func splitReference(_ reference: String) -> (resource: String, fragment: String) {
    guard let separator = reference.firstIndex(of: "#") else {
      return (reference, "")
    }
    return (String(reference[..<separator]), String(reference[separator...]))
  }
}
