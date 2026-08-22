import Foundation
import PathKit
import Testing
@testable import MarkdownUtilitiesServer

@Suite("Native server project loading")
struct MarkdownServerProjectLoaderTests {
  @Test
  func `Server initialization creates valid configuration and preserves existing YAML`() async throws {
    let root = Path("tmp/server-loader-tests/\(UUID().uuidString)/").absolute()
    defer { try? root.delete() }
    try root.mkpath()

    let first = try MarkdownServerConfigurationBootstrapper.initialize(projectRoot: root)

    #expect(first.configurationCreated)
    #expect(first.configurationFile == root + ".md-utils/server/server.yaml")
    #expect(first.schemaFile == root + ".md-utils/server/server.schema.json")
    #expect(first.configurationFile.exists)
    #expect(first.schemaFile.exists)
    #expect(
      try first.schemaFile.read(.utf8) == MarkdownServerConfigurationSchema.content()
    )

    let runtime = try await MarkdownServerProjectLoader(projectRoot: root).load()
    #expect(runtime.configuration.serverConfigVersion == "1")
    #expect(runtime.configuration.resources.isEmpty)

    try first.configurationFile.write(
      """
      serverConfigVersion: "1"
      resources: []
      # retained marker
      """
    )
    let second = try MarkdownServerConfigurationBootstrapper.initialize(projectRoot: root)

    #expect(second.configurationCreated == false)
    #expect(try second.configurationFile.read(.utf8).contains("# retained marker"))
  }

  @Test
  func `Bundled server schema is valid JSON`() throws {
    let content = try MarkdownServerConfigurationSchema.content()
    let data = try #require(content.data(using: .utf8))
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(schema["$schema"] as? String == "https://json-schema.org/draft/2020-12/schema")
    #expect(schema["title"] as? String == "md-utils server configuration")
  }

  @Test
  func `Default YAML loads rules and recursively imports Markdown once`() async throws {
    let root = Path("tmp/server-loader-tests/\(UUID().uuidString)/").absolute()
    defer { try? root.delete() }
    try (root + ".md-utils/server/").mkpath()
    try (root + "books/classics/").mkpath()
    try (root + "notes/").mkpath()

    try (root + ".md-utils/server/server.yaml").write(
      """
      serverConfigVersion: "1"
      resources:
        - name: books
          route: /books
          operations: [list, get]
          selection:
            mode: rule
            rule: books
          identityPolicy:
            source: frontmatter
            path: [slug]
            format: string
            logicalPathFallbackEnabled: true
      """
    )
    try (root + ".md-utils/md-utils.json").write(
      """
      {
        "configVersion": "0.2.0",
        "schemaDirectory": ".md-utils/schemas/",
        "rules": [{
          "name": "books",
          "match": { "paths": ["books/**"] },
          "checks": [{ "type": "requiredHeading", "heading": "Book" }]
        }]
      }
      """
    )
    try (root + "books/classics/dune.md").write("---\nslug: dune\n---\n# Book\nDune")
    try (root + "notes/ignored.md").write("# Note")
    try (root + ".md-utils/ignored.md").write("# Configuration documentation")

    let loader = MarkdownServerProjectLoader(projectRoot: root)
    let runtime = try await loader.load()

    #expect(loader.configurationFile == root + ".md-utils/server/server.yaml")
    #expect(runtime.importedRecordCount == 2)
    #expect(runtime.plan.resources.map(\.name) == ["books"])
    #expect(runtime.plan.routes.map(\.path.rawValue) == [
      "/_md-utils/path/{path}", "/books", "/books/{id}", "/openapi.json",
    ])
    let books = try #require(runtime.snapshot.resource(named: "books"))
    #expect(books.records.count == 1)
    #expect(books.records.first?.canonicalIdentity?.rawValue == "books/classics/dune.md")
    #expect(books.records.first?.logicalPath?.rawValue == "books/classics/dune.md")
    #expect(books.records.first?.revision != nil)
    #expect(books.records.first?.valid == true)
    #expect(books.records.first?.memberships.first?.identity?.rawValue == "dune")
  }

  @Test
  func `Missing default configuration fails before partial startup`() async throws {
    let root = Path("tmp/server-loader-tests/\(UUID().uuidString)/").absolute()
    defer { try? root.delete() }
    try root.mkpath()
    let expectedPath = (root + ".md-utils/server/server.yaml").normalize().string

    await #expect(throws: MarkdownServerProjectLoaderError.configurationNotFound(expectedPath)) {
      try await MarkdownServerProjectLoader(projectRoot: root).load()
    }
  }

  @Test
  func `Plan-only loading does not scan Markdown records`() throws {
    let base = Path("tmp/server-loader-tests/\(UUID().uuidString)/").absolute()
    let root = base + "project/"
    defer { try? base.delete() }
    try (root + ".md-utils/server/").mkpath()
    try (root + ".md-utils/server/server.yaml").write(
      """
      serverConfigVersion: "1"
      resources: []
      """
    )
    let outside = base + "outside.md"
    try outside.write("# Outside")
    try FileManager.default.createSymbolicLink(
      atPath: (root + "linked.md").string,
      withDestinationPath: outside.string
    )

    let runtime = try MarkdownServerProjectLoader(projectRoot: root).loadPlan()

    #expect(runtime.plan.routes.map(\.path.rawValue) == ["/openapi.json"])
  }

  @Test
  func `Recursive import rejects a symlink outside the project`() async throws {
    let base = Path("tmp/server-loader-tests/\(UUID().uuidString)/").absolute()
    let root = base + "project/"
    defer { try? base.delete() }
    try (root + ".md-utils/server/").mkpath()
    try (root + ".md-utils/server/server.yaml").write(
      """
      serverConfigVersion: "1"
      resources: []
      """
    )
    let outside = base + "outside.md"
    try outside.write("# Outside")
    let link = root + "linked.md"
    try FileManager.default.createSymbolicLink(
      atPath: link.string,
      withDestinationPath: outside.string
    )

    await #expect(throws: MarkdownServerProjectLoaderError.recordOutsideProject(link.string)) {
      try await MarkdownServerProjectLoader(projectRoot: root).load()
    }
  }
}
