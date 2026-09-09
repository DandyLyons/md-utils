import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit
import Yams

/// An in-memory overlay. Validation sees the whole proposed project without staging files.
struct InteractiveDraftSession {
  struct Change {
    let path: Path
    let before: Data?
    var after: Data?
  }

  let root: Path
  private(set) var changes: [Change] = []

  init(root: Path) {
    self.root = Path(URL(fileURLWithPath: root.absolute().string).resolvingSymlinksInPath().path)
  }

  func resourcePath(_ relative: String, types: Bool) throws -> Path {
    if types {
      _ = try MarkdownRuleTypeExpression.decode(.string(relative), source: "Type destination")
    } else {
      // Use the existing resource-reference grammar, with the rule suffix translated.
      guard relative.lowercased().hasSuffix(".mdrule.json"), relative.hasPrefix("legacy/") == false else {
        throw ValidationError("Expected an active .mdrule.json path outside legacy/")
      }
      _ = try MarkdownRuleTypeExpression.decode(
        .string(String(relative.dropLast(".mdrule.json".count)) + ".mdtype.json"), source: "Rule destination")
    }
    let directory = root + (types ? ".md-utils/types/" : ".md-utils/rules/")
    let path = directory + relative
    try requireContained(path, in: directory)
    return path
  }

  mutating func stage(path: Path, content: String?, creating: Bool = false) throws {
    let path = path.absolute().normalize()
    try requireResource(path)
    if creating && (path.exists || changes.contains(where: { $0.path == path })) {
      throw ValidationError("Destination already exists: \(path)")
    }
    let data = content.map { Data($0.utf8) }
    if let index = changes.firstIndex(where: { $0.path == path }) {
      changes[index].after = data
    } else {
      changes.append(Change(path: path, before: try readIfPresent(path), after: data))
    }
  }

  func typeDefinitions() throws -> [MarkdownTypeDefinition] {
    var paths = Set(try MarkdownTypeFileRegistryLoader.definitionFiles(projectRoot: root))
    paths.formUnion(changes.filter { isType($0.path) }.map(\.path))
    return try paths.sorted { $0.string < $1.string }.compactMap { path in
      try requireResource(path)
      guard let data = try proposedData(path) else { return nil }
      return try MarkdownTypeDefinitionDecoder.decode(String(decoding: data, as: UTF8.self),
        format: Self.format(path), source: path.string)
    }
  }

  func ruleFiles() throws -> [MarkdownRuleFile] {
    let existing = try MarkdownRuleFileStore(projectRoot: root).load()
    var paths = Set(existing.map { Path($0.source) })
    paths.formUnion(changes.filter { isType($0.path) == false }.map(\.path))
    return try paths.sorted { $0.string < $1.string }.compactMap { path in
      guard let data = try proposedData(path) else { return nil }
      return try MarkdownRuleFile.decode(String(decoding: data, as: UTF8.self), source: path.string)
    }
  }

  func validate() throws {
    let provider = FileMarkdownSchemaResourceProvider(projectRoot: root)
    let types = try MarkdownTypeRegistry(definitions: typeDefinitions(), schemaProvider: provider)
    let definitions = try ruleFiles().map { file in
      var bindings: [String: MarkdownTypeName] = [:]
      for reference in file.types.references {
        let path = try resourcePath(reference, types: true)
        guard let definition = types.definitions.first(where: {
          $0.source.map { canonical(Path($0)) == canonical(path) } ?? false
        }) else {
          throw ValidationError("\(file.source): types: Referenced type does not exist: \(reference)")
        }
        bindings[reference] = definition.name
      }
      return MarkdownRuleDefinition(name: file.name, source: file.source,
        matchExpression: try file.decodedMatch(), typeExpression: file.types, typeBindings: bindings)
    }
    _ = try MarkdownRuleCompiler(capabilities: [.modificationDate, .frontmatterJMESPath],
      typeRegistry: types, schemaProvider: provider, queryProvider: JMESPathRuleCapabilityProvider()).compile(definitions)
  }

  func preview() -> String {
    changes.map { change in
      let action = change.after == nil ? "Remove" : (change.before == nil ? "Create" : "Update")
      let content = change.after ?? change.before ?? Data()
      return "\(CLIStyle.heading(action)) \(CLIStyle.path(change.path.string))\n\(String(decoding: content, as: UTF8.self))"
    }.joined(separator: "\n")
  }

  /// Individual writes and removals are atomic. A multi-file save is not a transaction.
  func commit() throws {
    try validate()
    for change in changes {
      try requireResource(change.path)
      guard try readIfPresent(change.path) == change.before else {
        throw ValidationError("Resource changed during authoring; restart: \(change.path)")
      }
    }
    var completed: [String] = []
    do {
      // Shared types must be present before their new rules become active.
      for change in changes.sorted(by: { isType($0.path) && isType($1.path) == false }) {
        if let data = change.after {
          try change.path.parent().mkpath()
          try requireResource(change.path)
          if change.before == nil {
            // Publish a complete file with an exclusive link, so a concurrent create
            // cannot be overwritten between the preflight check and publication.
            let temporary = change.path.parent() + ".md-utils-authoring-\(UUID().uuidString).tmp"
            defer { try? temporary.delete() }
            try data.write(to: URL(fileURLWithPath: temporary.string), options: .withoutOverwriting)
            try FileManager.default.linkItem(atPath: temporary.string, toPath: change.path.string)
          } else {
            try data.write(to: URL(fileURLWithPath: change.path.string), options: .atomic)
          }
        } else if change.before != nil {
          try change.path.delete()
        }
        completed.append(change.path.string)
      }
    } catch {
      throw ValidationError("Save failed: \(error.localizedDescription). Completed resources: \(completed.joined(separator: ", ")). Inspect these files before retrying; the proposed changes are shown above.")
    }
  }

  static func format(_ path: Path) -> MarkdownTypeDefinitionFormat {
    switch path.extension?.lowercased() {
    case "yaml", "yml": return .yaml
    case "toml": return .toml
    default: return .json
    }
  }

  static func encode(_ definition: MarkdownTypeDefinition, path: Path) throws -> String {
    let object = TypesRenderer.definitionObject(definition)
    switch format(path) {
    case .json: return try json(object)
    case .yaml: return try Yams.dump(object: object, sortKeys: true)
    case .toml: return try FrontMatterConversion.serializeTOMLValue(object)
    }
  }

  static func json(_ object: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]), as: UTF8.self) + "\n"
  }

  private func proposedData(_ path: Path) throws -> Data? {
    if let change = changes.first(where: { $0.path == path }) { return change.after }
    return try readIfPresent(path)
  }

  private func readIfPresent(_ path: Path) throws -> Data? {
    try path.exists ? Data(contentsOf: URL(fileURLWithPath: path.string)) : nil
  }

  private func isType(_ path: Path) -> Bool {
    MarkdownTypeFileRegistryLoader.definitionFileSuffixes.contains(where: path.lastComponent.lowercased().hasSuffix)
  }

  private func canonical(_ path: Path) -> String {
    URL(fileURLWithPath: path.string).standardizedFileURL.resolvingSymlinksInPath().path
  }

  private func requireResource(_ path: Path) throws {
    let directory = root + (isType(path) ? ".md-utils/types/" : ".md-utils/rules/")
    try requireContained(path, in: directory)
    // Reject aliases so editing cannot replace a symlink or mutate its target unexpectedly.
    guard canonical(path) == path.absolute().normalize().string else {
      throw ValidationError("Authoring through symbolic links is unsupported: \(path)")
    }
  }

  private func requireContained(_ path: Path, in directory: Path) throws {
    guard canonical(directory).hasPrefix(root.string + "/"),
      canonical(path).hasPrefix(canonical(directory) + "/") else {
      throw ValidationError("Resource escapes \(directory.string)/: \(path)")
    }
  }
}
