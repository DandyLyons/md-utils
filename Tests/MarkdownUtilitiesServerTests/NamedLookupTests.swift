import Foundation
import MarkdownUtilitiesCore
import Testing
import Yams
@testable import MarkdownUtilitiesServer

@Suite("Named resource lookups")
struct NamedLookupTests {
  private func resource(lookups: [MarkdownResourceLookup], constraints: [MarkdownLookupConstraint] = [],
    operations: [MarkdownResourceOperation] = [.get],
  ) -> MarkdownResourceConfiguration {
    MarkdownResourceConfiguration(name: "books", route: "/books", operations: operations,
      selection: .type(name: .init(rawValue: "Book"), searchRoot: "books/"),
      identityPolicy: .init(source: .frontmatter(path: ["uuid"], format: .uuid)),
      lookups: lookups, constraints: constraints,
    )
  }

  private func compiler() throws -> EndpointPlanCompiler {
    let types = try MarkdownTypeRegistry(definitions: [MarkdownTypeDefinition(name: .init(rawValue: "Book"), version: "1")])
    return EndpointPlanCompiler(ruleRegistry: try MarkdownRuleCompiler(typeRegistry: types).compile([]), typeRegistry: types)
  }

  @Test func `version two routes preserve values and carry generated contract metadata`() throws {
    let config = MarkdownServerConfiguration(serverConfigVersion: "2", resources: [resource(lookups: [
      .init(name: "filename", source: .filename),
      .init(name: "path", source: .logicalPath),
      .init(name: "uuid", source: .persistentIdentity),
    ])], persistentIdentity: .init(path: ["uuid"]))
    let plan = try compiler().compile(config)
    let aliases = plan.routes.filter { $0.kind == .namedLookup }
    #expect(aliases.count == 5)
    #expect(aliases.contains { $0.path.rawValue == "/books/by/path" && $0.lookupUsesQuery == true })
    #expect(try JSONDecoder().decode(EndpointPlan.self, from: JSONEncoder().encode(plan)) == plan)
    let openAPI = try MarkdownServerOpenAPIGenerator.generate(from: plan).serialized(format: .json)
    let object = try #require(JSONSerialization.jsonObject(with: openAPI) as? [String: Any])
    let paths = try #require(object["paths"] as? [String: Any])
    #expect(paths["/books/by/filename/{id}"] != nil)
    #expect(paths["/books/by/path"] != nil)
    #expect(plan.resources[0].protectedIdentityFields(persistentIdentity: plan.persistentIdentity) == ["uuid"])
  }

  @Test func `invalid lookup declarations fail before routes are installed`() throws {
    let invalid: [[MarkdownResourceLookup]] = [
      [.init(name: "bad/name", source: .filename)],
      [.init(name: "same", source: .filename), .init(name: "same", source: .logicalPath)],
      [.init(name: "uuid", source: .persistentIdentity)],
      [.init(name: "slug", source: .frontmatter, path: ["slug"], format: .slug)],
      [.init(name: "file", source: .filename, path: ["oops"])],
      [.init(name: "field", source: .frontmatter, path: [], format: .string)],
    ]
    for lookups in invalid {
      #expect(throws: EndpointPlanCompilationError.self) {
        try compiler().compile(.init(serverConfigVersion: "2", resources: [resource(lookups: lookups)]))
      }
    }
    #expect(throws: EndpointPlanCompilationError.self) {
      try compiler().compile(.init(resources: [resource(lookups: [.init(name: "file", source: .filename)])]))
    }
    #expect(throws: EndpointPlanCompilationError.self) {
      try compiler().compile(.init(serverConfigVersion: "2", resources: [resource(lookups: [], constraints: [.init(lookup: "missing")])]))
    }
    let disabled = try compiler().compile(.init(serverConfigVersion: "2", resources: [resource(
      lookups: [.init(name: "file", source: .filename)], operations: [.list],
    )]))
    #expect(!disabled.routes.contains { $0.kind == .namedLookup })
    let collision = MarkdownResourceConfiguration(name: "other", route: "/books/by/file", operations: [.list],
      selection: .type(name: .init(rawValue: "Book"), searchRoot: "."), identityPolicy: .init(source: .logicalPath),
    )
    #expect(throws: EndpointPlanCompilationError.self) {
      try compiler().compile(.init(serverConfigVersion: "2", resources: [
        resource(lookups: [.init(name: "file", source: .filename)]), collision,
      ]))
    }
    #expect(throws: (any Error).self) {
      try YAMLDecoder().decode(MarkdownResourceLookup.self, from: "name: file\nsource: filename\nunique: true")
    }
  }

  @Test func `portable lookup includes hidden UUID holders without exposing them`() async throws {
    let config = MarkdownServerConfiguration(serverConfigVersion: "2", resources: [resource(lookups: [
      .init(name: "uuid", source: .persistentIdentity),
      .init(name: "slug", source: .frontmatter, path: ["slug"], format: .string),
      .init(name: "isbn", source: .frontmatter, path: ["isbn"], format: .string, protectedIdentifier: true),
    ], constraints: [.init(lookup: "isbn", uniqueWithin: .resource, requireValue: true)])], persistentIdentity: .init(path: ["uuid"]))
    let types = try MarkdownTypeRegistry(definitions: [.init(name: .init(rawValue: "Book"), version: "1")])
    let rules = try MarkdownRuleCompiler(typeRegistry: types).compile([])
    let plan = try EndpointPlanCompiler(ruleRegistry: rules, typeRegistry: types).compile(config)
    let uuid = "550e8400-e29b-41d4-a716-446655440000"
    let records = try ["books/a.md", "hidden/a.md"].map { path in
      MarkdownRecord(identity: .init(rawValue: path), content: "---\nuuid: \(uuid)\nslug: shared\n---\n# Book",
        context: .init(path: try MarkdownRecordPath(path)),
      )
    }
    let snapshot = try await MarkdownServerReadSnapshotBuilder(store: InMemoryRecordStore(records: records),
      plan: plan, ruleRegistry: rules, typeRegistry: types,
    ).build()
    let books = try #require(snapshot.resource(named: "books"))
    guard case .conflict(let conflict) = books.lookup(named: "uuid", value: uuid) else {
      Issue.record("Expected global UUID conflict"); return
    }
    #expect(conflict.totalCandidates == 2)
    #expect(conflict.candidates.count == 1)
    #expect(books.lookup(primary: .init(rawValue: uuid)) == books.lookup(named: "uuid", value: uuid))
    guard case .record = books.lookup(named: "slug", value: "shared") else {
      Issue.record("Unconstrained slug is resource scoped"); return
    }
    #expect(books.lookupEvidence["books/a.md"]?.first(where: { $0.lookup == "isbn" })?.violatesConstraint == true)
    #expect(books.records[0].diagnostics.contains { $0.code == "identity.lookup.missing" })
    #expect(plan.resources[0].protectedIdentityFields(persistentIdentity: plan.persistentIdentity) == ["uuid", "isbn"])
    #expect(books.lookupEvidence["books/a.md"]?.first(where: { $0.lookup == "slug" })?.protectedIdentifier == false)
  }
}
