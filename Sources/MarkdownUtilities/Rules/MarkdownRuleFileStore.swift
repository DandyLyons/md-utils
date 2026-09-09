import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Native storage for standalone rule definitions under `.md-utils/rules/`.
/// Legacy project config loading remains version-specific and opt-in to this store.
public struct MarkdownRuleFileStore {
  public let projectRoot: Path

  public init(projectRoot: Path) {
    self.projectRoot = Path(URL(fileURLWithPath: projectRoot.absolute().string).resolvingSymlinksInPath().path)
  }

  private var directory: Path { projectRoot + ".md-utils/rules" }

  /// Loads active files in stable path order and rejects duplicate rule identities.
  public func load() throws -> [MarkdownRuleFile] {
    guard directory.exists else { return [] }
    try requireContained(directory, under: projectRoot)
    var files: [Path] = []
    try discover(directory, files: &files)
    var byName: [String: String] = [:]
    return try files.sorted { $0.string < $1.string }.map { path in
      let rule = try read(path)
      if let previous = byName[rule.name] {
        throw failure(path, "name", "Duplicate rule \"\(rule.name)\" also defined in \(previous)")
      }
      byName[rule.name] = path.string
      return rule
    }
  }

  /// Resolves explicit type filenames to declared identities without basename search.
  public func typeBindings(for rule: MarkdownRuleFile) throws -> [String: MarkdownTypeName] {
    try typeBindings(for: rule, registry: MarkdownTypeFileRegistryLoader.load(projectRoot: projectRoot))
  }

  /// Binds against the same immutable registry used to compile the project.
  public func typeBindings(for rule: MarkdownRuleFile, registry: MarkdownTypeRegistry) throws -> [String: MarkdownTypeName] {
    let types = projectRoot + ".md-utils/types"
    try requireContained(types, under: projectRoot)
    var result: [String: MarkdownTypeName] = [:]
    for reference in rule.types.references where result[reference] == nil {
      let path = types + reference
      do {
        try requireContained(path, under: types)
        guard path.isFile else { throw failure(path, "types", "Type file does not exist") }
        let canonical = canonicalPath(path)
        guard let definition = registry.definitions.first(where: {
          guard let source = $0.source else { return false }
          return canonicalPath(Path(source)) == canonical
        }) else { throw failure(path, "types", "File is not a loaded mdtype definition") }
        result[reference] = definition.name
      } catch {
        throw failure(Path(rule.source), "types", "\(reference): \(error.localizedDescription)")
      }
    }
    return result
  }

  /// Creates one validated rule without overwriting any existing file or identity.
  @discardableResult
  public func create(_ content: String, relativePath: String) throws -> MarkdownRuleFile {
    let destination = try activePath(relativePath)
    let rule = try MarkdownRuleFile.decode(content, source: destination.string)
    let existing = try load()
    if let duplicate = existing.first(where: { $0.name == rule.name }) {
      throw failure(destination, "name", "Rule \"\(rule.name)\" already exists in \(duplicate.source)")
    }
    _ = try typeBindings(for: rule)
    guard destination.exists == false else { throw failure(destination, "$", "Destination already exists") }
    try destination.parent().mkpath()
    try requireContained(destination, under: directory)
    try Data(try rule.encoded().utf8).write(to: URL(fileURLWithPath: destination.string), options: .withoutOverwriting)
    return try read(destination)
  }

  /// Replaces one rule at its existing source path after validation and collision checks.
  @discardableResult
  public func replace(named name: String, with content: String) throws -> MarkdownRuleFile {
    let rules = try load()
    guard let original = rules.first(where: { $0.name == name }) else {
      throw failure(directory, "name", "Rule \"\(name)\" was not found")
    }
    let path = Path(original.source)
    let replacement = try MarkdownRuleFile.decode(content, source: original.source)
    if let duplicate = rules.first(where: { $0.name == replacement.name && $0.source != original.source }) {
      throw failure(path, "name", "Rule \"\(replacement.name)\" already exists in \(duplicate.source)")
    }
    _ = try typeBindings(for: replacement)
    try requireContained(path, under: directory)
    guard try read(path) == original else { throw failure(path, "$", "Rule changed before replacement; retry") }
    try Data(try replacement.encoded().utf8).write(to: URL(fileURLWithPath: path.string), options: .atomic)
    return try read(path)
  }

  /// Removes only the file defining this identity; referenced resources are preserved.
  @discardableResult
  public func remove(named name: String) throws -> MarkdownRuleFile {
    guard let rule = try load().first(where: { $0.name == name }) else {
      throw failure(directory, "name", "Rule \"\(name)\" was not found")
    }
    let path = Path(rule.source)
    try requireContained(path, under: directory)
    guard try read(path) == rule else { throw failure(path, "$", "Rule changed before removal; retry") }
    try path.delete()
    return rule
  }

  private func read(_ path: Path) throws -> MarkdownRuleFile {
    do { return try MarkdownRuleFile.decode(path.read(.utf8), source: path.string) }
    catch let error as MarkdownRuleFileError { throw error }
    catch { throw failure(path, "$", error.localizedDescription) }
  }

  private func discover(_ path: Path, files: inout [Path]) throws {
    guard path.isDirectory else { throw failure(path, "$", "Expected a rules directory") }
    for child in try path.children().sorted(by: { $0.string < $1.string }) {
      if path == directory && child.lastComponent == "legacy" { continue }
      let symbolic = (try FileManager.default.attributesOfItem(atPath: child.string)[.type] as? FileAttributeType) == .typeSymbolicLink
      // Do not recurse through symlink directories, including cycles or aliases
      // to the legacy subtree. Active symbolic files are rejected explicitly.
      if symbolic {
        if child.isDirectory || child.lastComponent.lowercased().hasSuffix(".mdrule.json") {
          throw failure(child, "$", "Symbolic links are not supported for active rule discovery")
        }
        continue
      }
      try requireContained(child, under: directory)
      if child.isDirectory { try discover(child, files: &files) }
      else if child.isFile && child.lastComponent.lowercased().hasSuffix(".mdrule.json") { files.append(child) }
    }
  }

  private func activePath(_ relative: String) throws -> Path {
    let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
    guard relative.lowercased().hasSuffix(".mdrule.json"),
      relative.contains("\\") == false, relative.contains(":") == false,
      parts.first != "legacy",
      parts.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }) else {
      throw failure(directory, "$", "Expected an active relative .mdrule.json path outside legacy/")
    }
    let destination = directory + relative
    try requireContained(directory, under: projectRoot)
    try requireContained(destination, under: directory)
    return destination
  }

  private func canonicalPath(_ path: Path) -> String {
    URL(fileURLWithPath: path.absolute().string).standardizedFileURL.resolvingSymlinksInPath().path
  }

  private func requireContained(_ path: Path, under root: Path) throws {
    let rootPath = canonicalPath(root)
    let resolved = canonicalPath(path)
    guard resolved == rootPath || resolved.hasPrefix(rootPath + "/") else {
      throw failure(path, "$", "Resource escapes \(rootPath)/")
    }
  }

  private func failure(_ path: Path, _ location: String, _ message: String) -> MarkdownRuleFileError {
    MarkdownRuleFileError(source: path.string, location: location, message: message)
  }
}
