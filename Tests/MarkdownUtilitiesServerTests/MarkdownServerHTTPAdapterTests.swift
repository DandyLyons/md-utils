import Foundation
import Hummingbird
import HummingbirdTesting
import MarkdownUtilitiesCore
import Testing
@testable import MarkdownUtilitiesServer

@Suite("Hummingbird read-only server adapter")
struct MarkdownServerHTTPAdapterTests {
  @Test
  func `Planned routes preserve validity overlap paths missing IDs and collisions`() async throws {
    guard #available(macOS 14.0, *) else { return }
    let fixture = try await makeFixture()
    let router = Router()
    try MarkdownServerHTTPAdapter.register(
      plan: fixture.plan,
      snapshot: fixture.snapshot,
      on: router
    )
    let app = Application(router: router)

    try await app.test(.router) { client in
      try await client.execute(uri: "/books", method: .get) { response in
        #expect(response.status == .ok)
        #expect(response.headers[.contentType] == "application/json; charset=utf-8")
        let records = try decode([GenericMarkdownRecord].self, from: response.body)
        #expect(records.count == 5)

        let invalid = try #require(records.first {
          $0.canonicalIdentity?.rawValue == "canonical-invalid"
        })
        #expect(invalid.valid == false)
        #expect(invalid.diagnostics.contains { $0.source == .type && $0.severity == .error })

        let missing = try #require(records.first {
          $0.canonicalIdentity?.rawValue == "canonical-missing"
        })
        #expect(missing.memberships.first { $0.resourceName == "books" }?.identity == nil)
        #expect(missing.memberships.first { $0.resourceName == "books" }?.identityStatus == .missing)

        let overlapping = try #require(records.first {
          $0.canonicalIdentity?.rawValue == "canonical-dune"
        })
        #expect(overlapping.memberships.map(\.resourceName) == ["books", "library"])
      }

      try await client.execute(uri: "/books/dune", method: .get) { response in
        #expect(response.status == .ok)
        let record = try decode(GenericMarkdownRecord.self, from: response.body)
        #expect(record.canonicalIdentity?.rawValue == "canonical-dune")
        #expect(record.logicalPath?.rawValue == "books/classics/dune.md")
      }

      try await client.execute(uri: "/books/does-not-exist", method: .get) { response in
        #expect(response.status == .notFound)
        let envelope = try decode(MarkdownServerHTTPErrorEnvelope.self, from: response.body)
        #expect(envelope.error.code == "record.not-found")
        #expect(envelope.error.candidates == nil)
      }

      try await client.execute(uri: "/books/canonical-missing", method: .get) { response in
        #expect(response.status == .notFound)
      }

      try await client.execute(uri: "/books/shared", method: .get) { response in
        #expect(response.status == .conflict)
        let envelope = try decode(MarkdownServerHTTPErrorEnvelope.self, from: response.body)
        #expect(envelope.error.code == "record.identity-conflict")
        #expect(envelope.error.candidates?.count == 2)
        #expect(envelope.error.candidates?.compactMap(\.canonicalIdentity?.rawValue) == [
          "canonical-shared-a", "canonical-shared-b",
        ])
      }

      try await client.execute(
        uri: "/_md-utils/path/books/classics/dune.md",
        method: .get
      ) { response in
        #expect(response.status == .ok)
        let record = try decode(GenericMarkdownRecord.self, from: response.body)
        #expect(record.canonicalIdentity?.rawValue == "canonical-dune")
      }

      try await client.execute(
        uri: "/_md-utils/path/books/missing.md",
        method: .get
      ) { response in
        #expect(response.status == .notFound)
        let envelope = try decode(MarkdownServerHTTPErrorEnvelope.self, from: response.body)
        #expect(envelope.error.code == "record.not-found")
      }
    }
  }

  @Test
  func `Registration rejects plan and snapshot drift before serving`() async throws {
    guard #available(macOS 14.0, *) else { return }
    let fixture = try await makeFixture()
    let mismatched = MarkdownServerReadSnapshot(
      resources: [],
      canonicalRecords: [],
      logicalPathLookup: [:]
    )
    let router = Router()

    #expect(throws: MarkdownServerHTTPAdapterError.resourceSnapshotMismatch(
      planned: ["books", "library"],
      available: []
    )) {
      try MarkdownServerHTTPAdapter.register(
        plan: fixture.plan,
        snapshot: mismatched,
        on: router
      )
    }
  }

  private func makeFixture() async throws -> (
    plan: EndpointPlan,
    snapshot: MarkdownServerReadSnapshot
  ) {
    let book = type(named: "Book")
    let libraryItem = type(named: "LibraryItem")
    let typeRegistry = try MarkdownTypeRegistry(definitions: [book, libraryItem])
    let candidates = MarkdownRuleDefinition(
      name: "book-candidates",
      applicability: MarkdownRuleApplicability(paths: ["books/**"])
    )
    let ruleRegistry = try MarkdownRuleCompiler(typeRegistry: typeRegistry).compile([candidates])
    let primaryIdentity = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["slug"], format: .string)
    )
    let plan = try EndpointPlanCompiler(
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).compile(MarkdownServerConfiguration(resources: [
      MarkdownResourceConfiguration(
        name: "books",
        route: "/books",
        operations: [.list, .get],
        selection: .ruleWithExpectedType(rule: candidates.name, expectedType: book.name),
        identityPolicy: primaryIdentity
      ),
      MarkdownResourceConfiguration(
        name: "library",
        route: "/library",
        operations: [.list, .get],
        selection: .type(name: libraryItem.name, searchRoot: "books/"),
        identityPolicy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
      ),
    ]))
    let store = try InMemoryRecordStore(records: [
      record(
        identity: "canonical-dune",
        path: "books/classics/dune.md",
        content: "---\nslug: dune\n---\n# Book\nDune"
      ),
      record(
        identity: "canonical-invalid",
        path: "books/invalid.md",
        content: "---\nslug: invalid\n---\n# Note"
      ),
      record(
        identity: "canonical-missing",
        path: "books/no-slug.md",
        content: "# Book"
      ),
      record(
        identity: "canonical-shared-a",
        path: "books/shared-a.md",
        content: "---\nslug: shared\n---\n# Book\nA"
      ),
      record(
        identity: "canonical-shared-b",
        path: "books/shared-b.md",
        content: "---\nslug: shared\n---\n# Book\nB"
      ),
    ])
    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: store,
      plan: plan,
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).build()
    return (plan, snapshot)
  }

  private func type(named name: String) -> MarkdownTypeDefinition {
    MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: name),
      version: "1",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "\(name).heading",
          predicate: .heading(MarkdownHeadingPredicate(text: "Book"))
        )
      ])
    )
  }

  private func record(
    identity: String,
    path: String,
    content: String
  ) throws -> MarkdownRecord {
    MarkdownRecord(
      identity: MarkdownRecordIdentity(rawValue: identity),
      content: content,
      context: MarkdownRecordContext(path: try MarkdownRecordPath(path))
    )
  }

  private func decode<Value: Decodable>(
    _ type: Value.Type,
    from buffer: ByteBuffer
  ) throws -> Value {
    try JSONDecoder().decode(type, from: Data(buffer.readableBytesView))
  }
}
