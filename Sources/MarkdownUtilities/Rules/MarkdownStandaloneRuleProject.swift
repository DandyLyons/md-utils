import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Shared native loading of RFC 0002 project settings, rules, and type bindings.
public struct MarkdownStandaloneRuleProject {
  public let projectRoot: Path
  public let files: [MarkdownRuleFile]
  public let definitions: [MarkdownRuleDefinition]
  public let types: MarkdownTypeRegistry

  /// Nonstandard config locations require an explicit root. Legacy loading is separate.
  public init(configPath: Path, projectRoot explicitRoot: Path? = nil, typeRegistry: MarkdownTypeRegistry? = nil) throws {
    let path = configPath.absolute().normalize()
    let value = try JSONValue(any: JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path.string))))
    guard case .object(let object) = value,
      object["configVersion"] == .string("0.3.0"),
      Set(object.keys).subtracting(["configVersion", "$schema"]).isEmpty,
      object["$schema"] == nil || object["$schema"]?.stringValue?.isEmpty == false else {
      throw MarkdownRuleFileError(source: path.string, location: "$", message: "Expected 0.3.0 project settings with only configVersion and optional $schema")
    }
    if let explicitRoot {
      projectRoot = explicitRoot.absolute().normalize()
    } else if path.lastComponent == "md-utils.json" && path.parent().lastComponent == ".md-utils" {
      projectRoot = path.parent().parent()
    } else {
      throw MarkdownRuleFileError(source: path.string, location: "$", message: "A nonstandard config location requires an explicit project root")
    }
    let store = MarkdownRuleFileStore(projectRoot: projectRoot)
    files = try store.load()
    let typeDirectory = projectRoot + MarkdownTypeFileRegistryLoader.relativeTypesDirectory
    let canonicalTypeDirectory = URL(fileURLWithPath: typeDirectory.string).resolvingSymlinksInPath().path
    let canonicalRoot = URL(fileURLWithPath: projectRoot.string).resolvingSymlinksInPath().path
    guard canonicalTypeDirectory.hasPrefix(canonicalRoot + "/") else {
      throw MarkdownRuleFileError(source: typeDirectory.string, location: "types", message: "Types directory escapes the project")
    }
    for file in try MarkdownTypeFileRegistryLoader.definitionFiles(projectRoot: projectRoot) {
      let canonical = URL(fileURLWithPath: file.string).resolvingSymlinksInPath().path
      guard canonical.hasPrefix(canonicalTypeDirectory + "/") else {
        throw MarkdownRuleFileError(source: file.string, location: "types", message: "Type definition escapes types/")
      }
    }
    if let typeRegistry {
      types = typeRegistry
    } else {
      types = typeDirectory.exists
        ? try MarkdownTypeFileRegistryLoader.load(projectRoot: projectRoot)
        : try MarkdownTypeRegistry(definitions: [])
    }
    let registry = types
    definitions = try files.map { file in
      MarkdownRuleDefinition(name: file.name, source: file.source,
        matchExpression: try file.decodedMatch(), typeExpression: file.types,
        typeBindings: try store.typeBindings(for: file, registry: registry))
    }
  }

  /// Compiles all branches before a CLI scan or server snapshot starts.
  public func compile(
    capabilities: Set<MarkdownRuleRuntimeCapability> = [],
    queryProvider: (any MarkdownRuleQueryCapabilityProvider)? = nil
  ) throws -> MarkdownRuleRegistry {
    try MarkdownRuleCompiler(capabilities: capabilities, typeRegistry: types,
      schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: projectRoot),
      queryProvider: queryProvider).compile(definitions)
  }
}
