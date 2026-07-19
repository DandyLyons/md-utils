import Foundation
import MarkdownUtilitiesCore
import PathKit
import Yams

/// Loads project Markdown type definitions and schema resources from native files.
public enum MarkdownTypeFileRegistryLoader {
  public static let relativeTypesDirectory = ".md-utils/types/"
  public static let definitionFileSuffixes = [
    ".mdtype.yaml",
    ".mdtype.yml",
    ".mdtype.json",
  ]

  public static func load(projectRoot: Path) throws -> MarkdownTypeRegistry {
    let root = projectRoot.absolute()
    let directory = (root + Path(relativeTypesDirectory)).normalize()
    guard directory.exists else {
      throw MarkdownTypeFileLoaderError.typesDirectoryNotFound(directory.string)
    }
    guard directory.isDirectory else {
      throw MarkdownTypeFileLoaderError.notADirectory(directory.string)
    }

    let files = try definitionFiles(in: directory)
    let definitions = try files.map { file in
      let format = try definitionFormat(for: file)
      return try MarkdownTypeDefinitionDecoder.decode(
        file.read(.utf8),
        format: format,
        source: file.absolute().string
      )
    }
    let provider = FileMarkdownSchemaResourceProvider(projectRoot: root)
    return try MarkdownTypeRegistry(definitions: definitions, schemaProvider: provider)
  }

  public static func definitionFiles(projectRoot: Path) throws -> [Path] {
    let directory = (projectRoot.absolute() + Path(relativeTypesDirectory)).normalize()
    guard directory.exists else { return [] }
    return try definitionFiles(in: directory)
  }

  public static func isDefinitionFile(_ path: Path) -> Bool {
    guard path.isFile else { return false }
    let name = path.lastComponent.lowercased()
    return definitionFileSuffixes.contains { suffix in
      name.hasSuffix(suffix)
    }
  }

  private static func definitionFiles(in directory: Path) throws -> [Path] {
    try directory.recursiveChildren()
      .filter(isDefinitionFile)
      .sorted { $0.string < $1.string }
  }

  private static func definitionFormat(for path: Path) throws -> MarkdownTypeDefinitionFormat {
    switch path.extension?.lowercased() {
    case "yaml", "yml":
      return .yaml
    case "json":
      return .json
    default:
      throw MarkdownTypeFileLoaderError.unsupportedDefinitionFormat(path.string)
    }
  }
}

/// A native schema provider that confines references to the project root.
public struct FileMarkdownSchemaResourceProvider: MarkdownSchemaResourceProvider, @unchecked Sendable {
  public var projectRoot: Path

  public init(projectRoot: Path) {
    self.projectRoot = Path(
      URL(fileURLWithPath: projectRoot.absolute().string).resolvingSymlinksInPath().path
    )
  }

  public func resource(
    reference: String,
    relativeTo source: String?
  ) throws -> MarkdownSchemaResource {
    guard reference.isEmpty == false else {
      throw MarkdownTypeFileLoaderError.invalidSchemaReference(reference)
    }
    let referencePath = Path(reference)
    guard referencePath.isAbsolute == false else {
      throw MarkdownTypeFileLoaderError.schemaOutsideProject(reference)
    }

    let baseDirectory: Path
    if let source {
      if let url = URL(string: source), url.isFileURL {
        baseDirectory = Path(url.path).absolute().parent()
      } else {
        baseDirectory = Path(source).absolute().parent()
      }
    } else {
      baseDirectory = projectRoot
    }
    let resolved = (baseDirectory + referencePath).absolute().normalize()
    try ensureInsideProject(resolved)
    guard resolved.exists, resolved.isFile else {
      throw MarkdownTypeFileLoaderError.schemaNotFound(resolved.string)
    }
    let canonical = Path(
      URL(fileURLWithPath: resolved.string).resolvingSymlinksInPath().path
    )
    try ensureInsideProject(canonical)

    let content = try canonical.read(.utf8)
    let dynamic: Any
    if canonical.extension?.lowercased() == "json" {
      guard let data = content.data(using: .utf8) else {
        throw MarkdownTypeFileLoaderError.invalidSchema(canonical.string)
      }
      dynamic = try JSONSerialization.jsonObject(with: data)
    } else {
      guard let node = try Yams.compose(yaml: content) else {
        throw MarkdownTypeFileLoaderError.invalidSchema(canonical.string)
      }
      dynamic = try YAMLConversion.safeNodeToSwiftValue(node)
    }
    let schema = try JSONValue(any: dynamic)
    guard schema.objectValue != nil else {
      throw MarkdownTypeFileLoaderError.invalidSchema(canonical.string)
    }
    return MarkdownSchemaResource(
      source: URL(fileURLWithPath: canonical.string).absoluteString,
      schema: schema
    )
  }

  private func ensureInsideProject(_ path: Path) throws {
    let rootString = projectRoot.absolute().normalize().string
    let normalizedRoot = rootString.hasSuffix("/") ? rootString : rootString + "/"
    let pathString = path.absolute().normalize().string
    guard pathString.hasPrefix(normalizedRoot) else {
      throw MarkdownTypeFileLoaderError.schemaOutsideProject(pathString)
    }
  }
}

/// Reads and atomically writes filesystem-backed Markdown records.
public enum MarkdownRecordFileAdapter {
  public static func read(_ path: Path, projectRoot: Path) throws -> MarkdownRecord {
    let root = projectRoot.absolute().normalize()
    let file = path.absolute().normalize()
    let logicalPath = try MarkdownRecordPath(relativePath(from: root, to: file))
    return MarkdownRecord(
      identity: MarkdownRecordIdentity(rawValue: logicalPath.rawValue),
      content: try file.read(.utf8),
      context: MarkdownRecordContext(path: logicalPath)
    )
  }

  public static func write(_ record: MarkdownRecord, to path: Path) throws {
    guard let data = record.content.data(using: .utf8) else {
      throw MarkdownTypeFileLoaderError.recordNotUTF8(path.string)
    }
    try data.write(to: URL(fileURLWithPath: path.absolute().string), options: .atomic)
  }

  private static func relativePath(from root: Path, to path: Path) throws -> String {
    let rootString = root.string
    let normalizedRoot = rootString.hasSuffix("/") ? rootString : rootString + "/"
    if path.string.hasPrefix(normalizedRoot) {
      return String(path.string.dropFirst(normalizedRoot.count))
    }
    throw MarkdownTypeFileLoaderError.recordOutsideProject(path.string)
  }
}

/// Native type-definition and schema-loading failures.
public enum MarkdownTypeFileLoaderError: Error, Equatable, LocalizedError {
  case typesDirectoryNotFound(String)
  case notADirectory(String)
  case unsupportedDefinitionFormat(String)
  case invalidSchemaReference(String)
  case schemaOutsideProject(String)
  case schemaNotFound(String)
  case invalidSchema(String)
  case recordNotUTF8(String)
  case recordOutsideProject(String)

  public var errorDescription: String? {
    switch self {
    case .typesDirectoryNotFound(let path):
      return "Markdown types directory not found: \(path)"
    case .notADirectory(let path):
      return "Markdown types path is not a directory: \(path)"
    case .unsupportedDefinitionFormat(let path):
      return "Unsupported Markdown type-definition format: \(path)"
    case .invalidSchemaReference(let reference):
      return "Invalid JSON Schema reference: \(reference)"
    case .schemaOutsideProject(let path):
      return "JSON Schema references must remain inside the project: \(path)"
    case .schemaNotFound(let path):
      return "Referenced JSON Schema was not found: \(path)"
    case .invalidSchema(let path):
      return "Referenced JSON Schema must be a JSON or YAML object: \(path)"
    case .recordNotUTF8(let path):
      return "Markdown record could not be encoded as UTF-8: \(path)"
    case .recordOutsideProject(let path):
      return "Markdown record must be inside the project root: \(path)"
    }
  }
}
