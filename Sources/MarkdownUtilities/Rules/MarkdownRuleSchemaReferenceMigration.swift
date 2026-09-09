import Foundation
import MarkdownUtilitiesCore
import PathKit

/// A resolved legacy schema reference prepared for the 0.3.0 migration writer.
public struct MarkdownRuleSchemaReferenceMigration: Equatable, Sendable {
  public let projectRelativeReference: String
  public let typeRelativeReference: String

  /// Preserves the resource selected by legacy schemaDirectory without writing files.
  /// RFC 0002 places the migrated reference inside an mdtype, relative to that file.
  public static func plan(
    schema: String,
    schemaDirectory: String? = nil,
    projectRoot: Path,
    typeFile: String
  ) throws -> Self {
    let root = projectRoot.absolute().normalize()
    let directory = schemaDirectory ?? ".md-utils/schemas/"
    let source = root + ".md-utils/md-utils.json"
    func invalid(_ message: String) -> MarkdownRuleFileError {
      MarkdownRuleFileError(source: source.string, location: "schemaDirectory/schema", message: message)
    }
    guard schema.isEmpty == false, directory.isEmpty == false,
      Path(directory).isAbsolute == false, Path(schema).isAbsolute == false,
      directory.contains(":") == false, schema.contains(":") == false,
      directory.contains("\\") == false, schema.contains("\\") == false else {
      throw invalid("Migration requires nonempty project-relative schema paths")
    }
    // Use the same validated type-reference grammar as rule files.
    _ = try MarkdownRuleTypeExpression.decode(.string(typeFile), source: source.string)
    let resource = (root + directory + schema).normalize()
    let rootPrefix = root.string.hasSuffix("/") ? root.string : root.string + "/"
    guard resource.string.hasPrefix(rootPrefix) else { throw invalid("Schema reference escapes the project root") }
    let projectRelative = String(resource.string.dropFirst(rootPrefix.count))
    // This checks existence, structured schema content, and transitive path confinement
    // when the graph is compiled below. Relative nested $refs retain their own base.
    let provider = FileMarkdownSchemaResourceProvider(projectRoot: root)
    let resourceValue = try provider.resource(reference: projectRelative,
      relativeTo: URL(fileURLWithPath: (root + "__migration-base.json").string).absoluteString)
    _ = try MarkdownTypeRegistry(definitions: [.init(
      name: .init(rawValue: "__migration_check"), version: "migration",
      frontmatter: .init(schemas: [.inline(resourceValue.schema)]), source: resourceValue.source
    )], schemaProvider: provider)

    let typeDirectory = URL(fileURLWithPath: (root + ".md-utils/types" + typeFile).parent().string).pathComponents
    let schemaComponents = URL(fileURLWithPath: resource.string).pathComponents
    var common = 0
    while common < min(typeDirectory.count, schemaComponents.count), typeDirectory[common] == schemaComponents[common] {
      common += 1
    }
    let relative = Array(repeating: "..", count: typeDirectory.count - common) + schemaComponents.dropFirst(common)
    let typeRelative = relative.joined(separator: "/")
    let fromType = try provider.resource(reference: typeRelative,
      relativeTo: (root + ".md-utils/types" + typeFile).string)
    guard fromType.source == resourceValue.source else {
      throw invalid("The generated type reference would select a different schema resource")
    }
    return Self(projectRelativeReference: projectRelative, typeRelativeReference: typeRelative)
  }
}
