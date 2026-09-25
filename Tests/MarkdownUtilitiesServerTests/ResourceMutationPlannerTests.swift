import Foundation
import Testing
import MarkdownUtilitiesCore
@testable import MarkdownUtilitiesServer

@Suite("Configured resource mutation planning")
struct ResourceMutationPlannerTests {
  private func types() throws -> MarkdownTypeRegistry {
    try MarkdownTypeRegistry(definitions: [MarkdownTypeDefinition(name: .init(rawValue: "Book"), version: "1",
      frontmatter: .init(presence: .required, schemas: [.inline(.object([
        "type": .string("object"), "required": .array([.string("title")])
      ]))]))])
  }

  private func configuration(writable: Bool = true, fields: [String] = ["title"]) -> MarkdownResourceConfiguration {
    .init(name: "books", route: "/books", operations: [.list, .get],
      selection: .ruleWithExpectedType(rule: "books", expectedType: .init(rawValue: "Book")),
      identityPolicy: .init(source: .frontmatter(path: ["id"], format: .string)),
      writable: writable ? .init(codec: .init(frontmatterFields: fields, bodyWritable: true),
        creation: .init(template: "{{ 'Book' | h1 }}\n{{ data.description }}")) : nil)
  }

  private func compiler() throws -> EndpointPlanCompiler {
    let types = try types()
    return EndpointPlanCompiler(ruleRegistry: try rules(types), typeRegistry: types)
  }

  private func rules(_ types: MarkdownTypeRegistry) throws -> MarkdownRuleRegistry {
    try MarkdownRuleCompiler(typeRegistry: types).compile([.init(name: "books",
      applicability: .init(paths: ["books/**"]))])
  }

  @Test
  func `configuration round trips and adds no mutation routes`() throws {
    let config = MarkdownServerConfiguration(resources: [configuration()])
    let decoded = try JSONDecoder().decode(MarkdownServerConfiguration.self, from: JSONEncoder().encode(config))
    #expect(decoded == config)
    let plan = try compiler().compile(decoded)
    let resource = try #require(plan.resources.first)
    #expect(resource.writable == config.resources.first?.writable)
    #expect(plan.routes.allSatisfy { $0.method == .get })
  }

  @Test
  func `compiler rejects writable identity and reserved fields`() throws {
    for fields in [["id"], ["$md-utils"], ["title", "title"]] {
      #expect(throws: (any Error).self) {
        try compiler().compile(.init(resources: [configuration(fields: fields)]))
      }
    }
  }

  @Test
  func `read only resources reject mutation planning`() async throws {
    let resource = try #require(compiler().compile(.init(resources: [configuration(writable: false)])).resources.first)
    let types = try types()
    let planner = ResourceMutationPlanner(types: types, rules: try rules(types))
    let source = try ResourceMutationSource(record: .init(identity: .init(rawValue: "17"), content: "Body",
      revision: .init(rawValue: "original")), expectedRevision: .init(rawValue: "original"))
    await #expect(throws: ResourceCodecError.self) {
      try await planner.plan(.patch(frontmatter: [:], body: "New"), source: source, resource: resource)
    }
  }

  @Test
  func `creation enforces configured rule and type and does not persist`() async throws {
    let resource = try #require(compiler().compile(.init(resources: [configuration()])).resources.first)
    let types = try types()
    let planner = ResourceMutationPlanner(types: types, rules: try rules(types))
    let valid = try await planner.planCreation(input: .init(frontmatter: ["title": .string("Dune")],
      data: .object(["description": .string("Novel")])), identity: .init(rawValue: "17"),
      context: .init(path: MarkdownRecordPath("books/17.md")),
      protectedFrontmatter: ["id": .string("17")], resource: resource)
    #expect(valid.isValid)
    let missing = try await planner.planCreation(input: .init(frontmatter: [:], data: .object([:])),
      identity: .init(rawValue: "17"), context: .init(path: MarkdownRecordPath("books/17.md")), resource: resource)
    #expect(!missing.isValid)
    let wrongPath = try await planner.planCreation(input: .init(frontmatter: ["title": .string("Dune")], data: .object([:])),
      identity: .init(rawValue: "17"), context: .init(path: MarkdownRecordPath("stories/17.md")), resource: resource)
    #expect(!wrongPath.isValid)
  }

  @Test
  func `failed replacement leaves source store unchanged and revision available for later commit`() async throws {
    let resource = try #require(compiler().compile(.init(resources: [configuration()])).resources.first)
    let types = try types()
    let planner = ResourceMutationPlanner(types: types, rules: try rules(types))
    let store = try InMemoryRecordStore()
    let stored = try await store.create(.init(identity: .init(rawValue: "17"),
      content: "---\nid: '17'\ntitle: Dune\n---\nBody",
      context: .init(path: MarkdownRecordPath("books/17.md"))))
    let revision = try #require(stored.revision)
    let source = try ResourceMutationSource(record: stored, expectedRevision: revision)
    let result = try await planner.plan(.replace(frontmatter: [:], body: "New"), source: source, resource: resource)
    #expect(!result.isValid)
    #expect(result.proposal.baselineRevision == revision)
    #expect(try await store.record(for: .init(rawValue: "17")) == stored)
  }
}
