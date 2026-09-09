import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import MarkdownUtilities

@Suite("Rule schema reference migration")
struct MarkdownRuleSchemaReferenceMigrationTests {
  @Test
  func `Default custom and normalized references preserve the same schema resource`() throws {
    let root = try project()
    defer { try? root.delete() }
    for directory in [".md-utils/schemas", "shared/schemas"] {
      try (root + directory).mkpath()
      try (root + directory + "book.schema.json").write("{\"type\":\"object\"}")
    }
    let cases: [(String?, String, String)] = [
      (nil, ".md-utils/schemas/book.schema.json", "../schemas/book.schema.json"),
      ("shared/schemas/", "shared/schemas/book.schema.json", "../../shared/schemas/book.schema.json"),
      ("shared/../shared/schemas/", "shared/schemas/book.schema.json", "../../shared/schemas/book.schema.json")
    ]
    for (directory, expectedProject, expectedType) in cases {
      let result = try MarkdownRuleSchemaReferenceMigration.plan(schema: "book.schema.json", schemaDirectory: directory,
        projectRoot: root, typeFile: "book.mdtype.json")
      #expect(result.projectRelativeReference == expectedProject)
      #expect(result.typeRelativeReference == expectedType)
      let provider = FileMarkdownSchemaResourceProvider(projectRoot: root)
      let fromProject = try provider.resource(reference: result.projectRelativeReference, relativeTo: (root + "base.json").string)
      let fromType = try provider.resource(reference: result.typeRelativeReference, relativeTo: (root + ".md-utils/types/book.mdtype.json").string)
      #expect(fromProject.source == fromType.source)
      #expect(fromProject.schema == fromType.schema)
    }
  }

  @Test
  func `Missing absolute escaping and symlink resources fail without writes`() throws {
    let root = try project()
    defer { try? root.delete() }
    for directory in ["missing/", "../", "/outside/"] {
      #expect(throws: (any Error).self) {
        try MarkdownRuleSchemaReferenceMigration.plan(schema: "book.schema.json", schemaDirectory: directory,
          projectRoot: root, typeFile: "book.mdtype.json")
      }
    }
    #expect(throws: MarkdownRuleFileError.self) {
      try MarkdownRuleSchemaReferenceMigration.plan(schema: "/absolute.schema.json", projectRoot: root, typeFile: "book.mdtype.json")
    }
    let outside = root + "outside"
    try outside.mkpath()
    try (outside + "book.schema.json").write("{}")
    let nestedProject = root + "project"
    try nestedProject.mkpath()
    try FileManager.default.createSymbolicLink(atPath: (nestedProject + "schemas").string, withDestinationPath: outside.string)
    #expect(throws: (any Error).self) {
      try MarkdownRuleSchemaReferenceMigration.plan(schema: "book.schema.json", schemaDirectory: "schemas/",
        projectRoot: nestedProject, typeFile: "book.mdtype.json")
    }
    #expect((root + ".md-utils").exists == false)
  }

  private func project() throws -> Path {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/schema-migration-\(UUID().uuidString)"
    try root.mkpath()
    return root
  }
}
