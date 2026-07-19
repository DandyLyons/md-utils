import Foundation

/// An immutable collection of validated and schema-resolved Markdown types.
public struct MarkdownTypeRegistry: Sendable {
  private var definitionsByName: [MarkdownTypeName: MarkdownTypeDefinition]
  private var schemasByName: [MarkdownTypeName: [JSONValue]]

  public init(
    definitions: [MarkdownTypeDefinition],
    schemaProvider: (any MarkdownSchemaResourceProvider)? = nil
  ) throws {
    var definitionsByName: [MarkdownTypeName: MarkdownTypeDefinition] = [:]
    var schemasByName: [MarkdownTypeName: [JSONValue]] = [:]

    for definition in definitions {
      guard definition.typeSchemaVersion == MarkdownTypeSchemaVersion.current else {
        throw MarkdownTypeDefinitionError.unsupportedSchemaVersion(definition.typeSchemaVersion)
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
        provider: schemaProvider
      )
      let schemas = try definition.frontmatter.schemas.map { source in
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
          return try compiler.compile(resource.schema, source: resource.source)
        }
      }

      definitionsByName[definition.name] = definition
      schemasByName[definition.name] = schemas
    }

    self.definitionsByName = definitionsByName
    self.schemasByName = schemasByName
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

  func resolvedSchemas(for name: MarkdownTypeName) -> [JSONValue] {
    schemasByName[name] ?? []
  }
}

private final class MarkdownSchemaGraphCompiler {
  private let typeName: String
  private let provider: (any MarkdownSchemaResourceProvider)?
  private var resources: [String: JSONValue] = [:]
  private var activeResources: [String] = []
  private var identifiers: [String: JSONValue] = [:]

  init(typeName: String, provider: (any MarkdownSchemaResourceProvider)?) {
    self.typeName = typeName
    self.provider = provider
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
