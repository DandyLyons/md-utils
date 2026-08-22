import Foundation
import JMESPath
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit
import Yams

/// A completely composed, immutable native server runtime ready for route registration.
public struct MarkdownServerRuntime: Sendable {
  /// Decoded opt-in resource configuration.
  public let configuration: MarkdownServerConfiguration
  /// Validated source of runtime route truth.
  public let plan: EndpointPlan
  /// Immutable records, assessments, and collision-safe lookup indexes.
  public let snapshot: MarkdownServerReadSnapshot
  /// Number of Markdown files imported during the startup scan.
  public let importedRecordCount: Int

  /// Creates a composed server runtime.
  public init(
    configuration: MarkdownServerConfiguration,
    plan: EndpointPlan,
    snapshot: MarkdownServerReadSnapshot,
    importedRecordCount: Int
  ) {
    self.configuration = configuration
    self.plan = plan
    self.snapshot = snapshot
    self.importedRecordCount = importedRecordCount
  }
}

/// Native startup failures produced before Hummingbird begins accepting requests.
public enum MarkdownServerProjectLoaderError: Error, Equatable, LocalizedError, Sendable {
  /// The supplied project root does not exist.
  case projectRootNotFound(String)
  /// The supplied project root is not a directory.
  case projectRootNotDirectory(String)
  /// The server configuration file does not exist.
  case configurationNotFound(String)
  /// The server configuration path is not a regular file.
  case configurationNotFile(String)
  /// YAML could not be decoded as the versioned server configuration model.
  case invalidConfiguration(path: String, message: String)
  /// A recursively discovered symlink resolves outside the selected project root.
  case recordOutsideProject(String)

  /// Human-readable startup failure description.
  public var errorDescription: String? {
    switch self {
    case .projectRootNotFound(let path):
      return "Server project root not found: \(path)"
    case .projectRootNotDirectory(let path):
      return "Server project root is not a directory: \(path)"
    case .configurationNotFound(let path):
      return "Server configuration not found: \(path)"
    case .configurationNotFile(let path):
      return "Server configuration is not a file: \(path)"
    case .invalidConfiguration(let path, let message):
      return "Invalid server configuration at \(path): \(message)"
    case .recordOutsideProject(let path):
      return "Markdown records must remain inside the server project root: \(path)"
    }
  }
}

/// Loads one native project into the immutable read-only server model.
///
/// Markdown files are recursively imported once into ``InMemoryRecordStore``. The
/// resulting snapshot remains fixed until the process restarts; this loader is not a
/// filesystem watcher or a persistent store.
public struct MarkdownServerProjectLoader: @unchecked Sendable {
  /// Default configuration location relative to a project root.
  public static let defaultConfigurationPath = ".md-utils/server/server.yaml"
  /// Supported canonical Markdown filename extensions.
  public static let markdownExtensions: Set<String> = ["md", "markdown"]

  /// Native project root whose Markdown files and `.md-utils/` definitions are loaded.
  public let projectRoot: Path
  /// YAML resource configuration file, absolute or relative to ``projectRoot``.
  public let configurationFile: Path

  /// Creates a startup project loader.
  ///
  /// - Parameters:
  ///   - projectRoot: Root used for record paths, rules, types, and schemas.
  ///   - configurationFile: Optional YAML path. Relative paths resolve from the root.
  public init(
    projectRoot: Path = .current,
    configurationFile: Path? = nil
  ) {
    let root = projectRoot.absolute().normalize()
    self.projectRoot = root
    if let configurationFile {
      self.configurationFile = configurationFile.isAbsolute
        ? configurationFile.normalize()
        : (root + configurationFile).normalize()
    } else {
      self.configurationFile = (root + Path(Self.defaultConfigurationPath)).normalize()
    }
  }

  /// Decodes configuration, compiles definitions, imports records, and builds a snapshot.
  ///
  /// Every step completes before an immutable runtime is returned, so malformed startup
  /// inputs cannot produce a partially registered server.
  public func load() async throws -> MarkdownServerRuntime {
    try validatePaths()
    let configuration = try loadServerConfiguration()
    let typeRegistry = try loadTypeRegistry()
    let ruleRegistry = try loadRuleRegistry(typeRegistry: typeRegistry)
    let plan = try EndpointPlanCompiler(
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).compile(configuration)
    let records = try loadRecords()
    let store = try InMemoryRecordStore(records: records)
    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: store,
      plan: plan,
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).build()
    return MarkdownServerRuntime(
      configuration: configuration,
      plan: plan,
      snapshot: snapshot,
      importedRecordCount: records.count
    )
  }

  private func validatePaths() throws {
    guard projectRoot.exists else {
      throw MarkdownServerProjectLoaderError.projectRootNotFound(projectRoot.string)
    }
    guard projectRoot.isDirectory else {
      throw MarkdownServerProjectLoaderError.projectRootNotDirectory(projectRoot.string)
    }
    guard configurationFile.exists else {
      throw MarkdownServerProjectLoaderError.configurationNotFound(configurationFile.string)
    }
    guard configurationFile.isFile else {
      throw MarkdownServerProjectLoaderError.configurationNotFile(configurationFile.string)
    }
  }

  private func loadServerConfiguration() throws -> MarkdownServerConfiguration {
    do {
      return try YAMLDecoder().decode(
        NativeMarkdownServerConfigurationFile.self,
        from: configurationFile.read(.utf8)
      ).configuration
    } catch {
      throw MarkdownServerProjectLoaderError.invalidConfiguration(
        path: configurationFile.string,
        message: error.localizedDescription
      )
    }
  }

  private func loadTypeRegistry() throws -> MarkdownTypeRegistry {
    let typesDirectory = projectRoot + Path(MarkdownTypeFileRegistryLoader.relativeTypesDirectory)
    guard typesDirectory.exists else {
      return try MarkdownTypeRegistry(definitions: [])
    }
    return try MarkdownTypeFileRegistryLoader.load(projectRoot: projectRoot)
  }

  private func loadRuleRegistry(
    typeRegistry: MarkdownTypeRegistry
  ) throws -> MarkdownRuleRegistry {
    let configurationPath = projectRoot + Path(".md-utils/md-utils.json")
    let configuration: MarkdownRuleConfiguration
    if configurationPath.exists {
      configuration = try MarkdownRuleConfigurationDecoder.decode(
        configurationPath.read(.utf8)
      )
    } else {
      configuration = MarkdownRuleConfiguration()
    }

    let schemaDirectory = Path(configuration.schemaDirectory).isAbsolute
      ? Path(configuration.schemaDirectory)
      : projectRoot + Path(configuration.schemaDirectory)
    let source = URL(
      fileURLWithPath: (schemaDirectory + "__md-utils-server-rule-source.json").string
    ).absoluteString
    let definitions = configuration.rules.map { definition in
      var definition = definition
      definition.source = source
      return definition
    }
    let queryProvider = NativeJMESPathRuleCapabilityProvider()
    return try MarkdownRuleCompiler(
      capabilities: [.modificationDate, .frontmatterJMESPath],
      typeRegistry: typeRegistry,
      schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: projectRoot),
      queryProvider: queryProvider
    ).compile(definitions)
  }

  private func loadRecords() throws -> [MarkdownRecord] {
    let configurationDirectory = (projectRoot + Path(".md-utils/")).normalize()
    let candidates = try projectRoot.recursiveChildren()
      .filter { path in
        guard path.isFile,
              let pathExtension = path.extension?.lowercased(),
              Self.markdownExtensions.contains(pathExtension)
        else { return false }
        return Self.isDescendant(path, of: configurationDirectory) == false
      }
      .sorted { $0.string < $1.string }
    let canonicalRoot = Self.resolvingSymbolicLinks(in: projectRoot)
    let canonicalConfigurationDirectory = Self.resolvingSymbolicLinks(
      in: configurationDirectory
    )
    var records: [MarkdownRecord] = []
    records.reserveCapacity(candidates.count)
    for candidate in candidates {
      let canonical = Self.resolvingSymbolicLinks(in: candidate)
      guard Self.isDescendant(canonical, of: canonicalRoot) else {
        throw MarkdownServerProjectLoaderError.recordOutsideProject(candidate.string)
      }
      guard Self.isDescendant(canonical, of: canonicalConfigurationDirectory) == false else {
        continue
      }
      records.append(try MarkdownRecordFileAdapter.read(candidate, projectRoot: projectRoot))
    }
    return records
  }

  private static func isDescendant(_ path: Path, of directory: Path) -> Bool {
    let directoryString = directory.absolute().normalize().string
    let prefix = directoryString.hasSuffix("/") ? directoryString : directoryString + "/"
    return path.absolute().normalize().string.hasPrefix(prefix)
  }

  private static func resolvingSymbolicLinks(in path: Path) -> Path {
    Path(URL(fileURLWithPath: path.absolute().string).resolvingSymlinksInPath().path)
      .normalize()
  }
}

/// Human-authored YAML boundary mapped into the transport-neutral configuration model.
private struct NativeMarkdownServerConfigurationFile: Decodable {
  let serverConfigVersion: String
  let resources: [NativeMarkdownResourceConfiguration]

  var configuration: MarkdownServerConfiguration {
    MarkdownServerConfiguration(
      serverConfigVersion: serverConfigVersion,
      resources: resources.map(\.configuration)
    )
  }
}

private struct NativeMarkdownResourceConfiguration: Decodable {
  let name: String
  let route: String
  let operations: [MarkdownResourceOperation]
  let selection: MarkdownResourceSelection
  let identityPolicy: NativeMarkdownRecordIdentityPolicy
  let projectionPolicy: MarkdownResourceProjectionPolicy
  let operationIDOverrides: [MarkdownOperationIDOverride]

  private enum CodingKeys: String, CodingKey {
    case name
    case route
    case operations
    case selection
    case identityPolicy
    case projectionPolicy
    case operationIDOverrides
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    route = try container.decode(String.self, forKey: .route)
    operations = try container.decode([MarkdownResourceOperation].self, forKey: .operations)
    selection = try container.decode(MarkdownResourceSelection.self, forKey: .selection)
    identityPolicy = try container.decode(NativeMarkdownRecordIdentityPolicy.self, forKey: .identityPolicy)
    projectionPolicy = try container.decodeIfPresent(
      MarkdownResourceProjectionPolicy.self,
      forKey: .projectionPolicy
    ) ?? .genericRecord
    operationIDOverrides = try container.decodeIfPresent(
      [MarkdownOperationIDOverride].self,
      forKey: .operationIDOverrides
    ) ?? []
  }

  var configuration: MarkdownResourceConfiguration {
    MarkdownResourceConfiguration(
      name: name,
      route: route,
      operations: operations,
      selection: selection,
      identityPolicy: identityPolicy.policy,
      projectionPolicy: projectionPolicy,
      operationIDOverrides: operationIDOverrides
    )
  }
}

private struct NativeMarkdownRecordIdentityPolicy: Decodable {
  enum Source: String, Decodable {
    case existingIdentity
    case logicalPath
    case frontmatter
  }

  enum Format: String, Decodable {
    case string
    case integer
    case uuid
    case slug
  }

  let source: Source
  let path: [String]?
  let format: Format?
  let slugPolicy: MarkdownSlugPolicy?
  let logicalPathFallbackEnabled: Bool

  private enum CodingKeys: String, CodingKey {
    case source
    case path
    case format
    case slugPolicy
    case logicalPathFallbackEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    source = try container.decode(Source.self, forKey: .source)
    path = try container.decodeIfPresent([String].self, forKey: .path)
    format = try container.decodeIfPresent(Format.self, forKey: .format)
    slugPolicy = try container.decodeIfPresent(MarkdownSlugPolicy.self, forKey: .slugPolicy)
    logicalPathFallbackEnabled = try container.decodeIfPresent(
      Bool.self,
      forKey: .logicalPathFallbackEnabled
    ) ?? true

    switch source {
    case .existingIdentity, .logicalPath:
      guard path == nil, format == nil, slugPolicy == nil else {
        throw DecodingError.dataCorruptedError(
          forKey: .source,
          in: container,
          debugDescription: "Identity path, format, and slugPolicy require source: frontmatter"
        )
      }
    case .frontmatter:
      guard let path, path.isEmpty == false, let format else {
        throw DecodingError.dataCorruptedError(
          forKey: .source,
          in: container,
          debugDescription: "Frontmatter identity requires a nonempty path and format"
        )
      }
      if format == .slug, slugPolicy == nil {
        throw DecodingError.dataCorruptedError(
          forKey: .slugPolicy,
          in: container,
          debugDescription: "Slug identity format requires slugPolicy"
        )
      }
      if format != .slug, slugPolicy != nil {
        throw DecodingError.dataCorruptedError(
          forKey: .slugPolicy,
          in: container,
          debugDescription: "slugPolicy is valid only with format: slug"
        )
      }
    }
  }

  var policy: MarkdownRecordIdentityPolicy {
    let modelSource: MarkdownRecordIdentitySource
    switch source {
    case .existingIdentity:
      modelSource = .existingIdentity
    case .logicalPath:
      modelSource = .logicalPath
    case .frontmatter:
      let identityPath = path ?? []
      switch format {
      case .string:
        modelSource = .frontmatter(path: identityPath, format: .string)
      case .integer:
        modelSource = .frontmatter(path: identityPath, format: .integer)
      case .uuid:
        modelSource = .frontmatter(path: identityPath, format: .uuid)
      case .slug:
        modelSource = .frontmatter(
          path: identityPath,
          format: .slug(slugPolicy ?? .strictASCII)
        )
      case nil:
        modelSource = .frontmatter(path: identityPath, format: .string)
      }
    }
    return MarkdownRecordIdentityPolicy(
      source: modelSource,
      logicalPathFallbackEnabled: logicalPathFallbackEnabled
    )
  }
}

/// Serialized native bridge for the non-Sendable JMESPath implementation.
private final class NativeJMESPathRuleCapabilityProvider:
  MarkdownRuleQueryCapabilityProvider,
  @unchecked Sendable
{
  let capabilities: Set<MarkdownRuleRuntimeCapability> = [.frontmatterJMESPath]
  private let lock = NSLock()

  func validateJMESPath(_ expression: String) throws {
    lock.lock()
    defer { lock.unlock() }
    _ = try JMESExpression.compile(expression)
  }

  func evaluateJMESPath(
    _ expression: String,
    frontmatter: JSONValue
  ) throws -> JSONValue? {
    lock.lock()
    defer { lock.unlock() }
    let compiled = try JMESExpression.compile(expression)
    guard let result = try compiled.search(object: frontmatter.foundationValue) else {
      return nil
    }
    return try JSONValue(any: result)
  }
}
