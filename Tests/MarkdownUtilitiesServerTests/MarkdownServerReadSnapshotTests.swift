import Foundation
import MarkdownUtilitiesCore
import Testing
@testable import MarkdownUtilitiesServer

@Suite("Markdown server read snapshot")
struct MarkdownServerReadSnapshotTests {
  @Test
  func `All selection modes share canonical records and retain invalid rule candidates`() async throws {
    let book = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "book-heading",
          predicate: .heading(MarkdownHeadingPredicate(text: "Book"))
        )
      ])
    )
    let registry = try MarkdownTypeRegistry(definitions: [book])
    let published = MarkdownRuleDefinition(
      name: "published",
      applicability: MarkdownRuleApplicability(
        paths: ["books/**"],
        excludePaths: ["books/drafts/**"]
      ),
      requirements: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "summary",
          predicate: .heading(MarkdownHeadingPredicate(text: "Summary"))
        )
      ])
    )
    let review = MarkdownRuleDefinition(
      name: "review",
      applicability: MarkdownRuleApplicability(paths: ["queue/**"])
    )
    let rules = [published, review]
    let plan = try makePlan(
      registry: registry,
      rules: rules,
      resources: [
        resource(
          name: "books",
          route: "/books",
          selection: .type(name: book.name, searchRoot: "books/")
        ),
        resource(
          name: "published",
          route: "/published",
          selection: .rule(name: "published")
        ),
        resource(
          name: "reviews",
          route: "/reviews",
          selection: .ruleWithExpectedType(rule: "review", expectedType: book.name)
        ),
      ]
    )
    let store = try InMemoryRecordStore(records: [
      record(
        identity: "dune",
        path: "books/dune.md",
        content: "---\ntitle: Dune\n---\n# Book\n## Summary\nClassic"
      ),
      record(identity: "draft", path: "books/drafts/draft.md", content: "# Book"),
      record(identity: "bad-review", path: "queue/bad.md", content: "# Note"),
    ])

    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: store,
      plan: plan,
      rules: rules,
      typeRegistry: registry,
      pageSize: 1
    ).build()

    let books = try #require(snapshot.resource(named: "books"))
    let publishedView = try #require(snapshot.resource(named: "published"))
    let reviews = try #require(snapshot.resource(named: "reviews"))
    #expect(books.records.compactMap(\.canonicalIdentity?.rawValue) == ["draft", "dune"])
    #expect(publishedView.records.compactMap(\.canonicalIdentity?.rawValue) == ["dune"])
    #expect(reviews.records.compactMap(\.canonicalIdentity?.rawValue) == ["bad-review"])

    let dune = try #require(books.records.first { $0.canonicalIdentity?.rawValue == "dune" })
    #expect(dune.memberships.map(\.resourceName) == ["books", "published"])
    #expect(dune.frontmatter == ["title": .string("Dune")])
    #expect(dune.body == "# Book\n## Summary\nClassic")
    #expect(dune.valid)

    let invalid = try #require(reviews.records.first)
    #expect(invalid.valid == false)
    #expect(invalid.memberships.first?.valid == false)
    #expect(invalid.diagnostics.contains { $0.typeName == book.name && $0.severity == .error })
    #expect(invalid.memberships.first?.assessedTypes.first?.conforms == false)
  }

  @Test
  func `Identity collisions remain visible and lookups are exhaustive`() async throws {
    let registry = try MarkdownTypeRegistry(definitions: [])
    let rule = MarkdownRuleDefinition(name: "all")
    let identityPolicy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["slug"], format: .string)
    )
    let plan = try makePlan(
      registry: registry,
      rules: [rule],
      resources: [resource(
        name: "records",
        route: "/records",
        selection: .rule(name: "all"),
        identityPolicy: identityPolicy
      )]
    )
    let first = try record(
      identity: "canonical-a",
      path: "a.md",
      content: "---\nslug: shared\n---\n# A"
    )
    let second = try record(
      identity: "canonical-b",
      path: "b.md",
      content: "---\nslug: shared\n---\n# B"
    )
    let missing = try record(identity: "canonical-c", path: "c.md", content: "# C")
    let duplicatePath = try record(
      identity: "canonical-d",
      path: "a.md",
      content: "---\nslug: distinct\n---\n# D"
    )
    let store = FixtureRecordStore(pages: [[first, second, missing, duplicatePath]])

    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: store,
      plan: plan,
      rules: [rule],
      typeRegistry: registry
    ).build()
    let resource = try #require(snapshot.resource(named: "records"))

    #expect(resource.records.count == 4)
    #expect(resource.records.filter { $0.memberships.first?.identityStatus == .duplicate }.count == 2)
    #expect(resource.records.first { $0.canonicalIdentity?.rawValue == "canonical-c" }?
      .memberships.first?.identityStatus == .missing)
    guard case .conflict(let conflict) = resource.lookup(
      primary: MarkdownRecordIdentity(rawValue: "shared")
    ) else {
      Issue.record("Expected duplicate resource identity conflict")
      return
    }
    #expect(conflict.candidates.count == 2)

    let path = try MarkdownRecordPath("a.md")
    guard case .conflict(let pathConflict) = snapshot.lookup(logicalPath: path) else {
      Issue.record("Expected duplicate logical path conflict")
      return
    }
    #expect(pathConflict.candidates.count == 2)
    #expect(resource.lookup(primary: MarkdownRecordIdentity(rawValue: "missing")) == .notFound)
  }

  @Test
  func `Paged duplicates are deduplicated and shared records are analyzed once`() async throws {
    let type = MarkdownTypeDefinition(name: MarkdownTypeName(rawValue: "Record"), version: "1")
    let registry = try MarkdownTypeRegistry(definitions: [type])
    let rule = MarkdownRuleDefinition(name: "all")
    let plan = try makePlan(
      registry: registry,
      rules: [rule],
      resources: [
        resource(name: "all", route: "/all", selection: .rule(name: "all")),
        resource(
          name: "typed",
          route: "/typed",
          selection: .type(name: type.name, searchRoot: ".")
        ),
      ]
    )
    let shared = try record(identity: "shared", path: "shared.md", content: "# Shared")
    let store = FixtureRecordStore(pages: [[shared], [shared]])
    let counter = AnalysisCounter()
    let builder = try MarkdownServerReadSnapshotBuilder(
      store: store,
      plan: plan,
      rules: [rule],
      typeRegistry: registry,
      pageSize: 1,
      analyzer: { record in
        await counter.increment()
        return await MarkdownRecordAnalyzer.analyze(record)
      }
    )

    let snapshot = try await builder.build()

    #expect(await counter.value == 1)
    #expect(snapshot.resource(named: "all")?.records.count == 1)
    #expect(snapshot.resource(named: "typed")?.records.count == 1)
    #expect(snapshot.resource(named: "all")?.records.first?.memberships.count == 2)
  }

  @Test
  func `Malformed YAML preserves safe body and emits one parse diagnostic`() async throws {
    let registry = try MarkdownTypeRegistry(definitions: [])
    let rule = MarkdownRuleDefinition(name: "all")
    let plan = try makePlan(
      registry: registry,
      rules: [rule],
      resources: [resource(name: "all", route: "/all", selection: .rule(name: "all"))]
    )
    let malformed = try record(
      identity: "malformed",
      path: "malformed.md",
      content: "---\ntags: [unterminated\n---\n# Body"
    )

    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: FixtureRecordStore(pages: [[malformed]]),
      plan: plan,
      rules: [rule],
      typeRegistry: registry
    ).build()
    let projected = try #require(snapshot.resource(named: "all")?.records.first)

    #expect(projected.frontmatter == nil)
    #expect(projected.body == "# Body")
    #expect(projected.diagnostics.filter { $0.code == "record.frontmatter.invalid-yaml" }.count == 1)
  }

  @Test
  func `Builder rejects dependency drift and repeated continuation tokens`() async throws {
    let type = MarkdownTypeDefinition(name: MarkdownTypeName(rawValue: "Book"), version: "1")
    let registry = try MarkdownTypeRegistry(definitions: [type])
    let rule = MarkdownRuleDefinition(name: "all")
    let rulePlan = try makePlan(
      registry: registry,
      rules: [rule],
      resources: [resource(name: "all", route: "/all", selection: .rule(name: "all"))]
    )
    let emptyStore = FixtureRecordStore(pages: [[]])

    await #expect(throws: MarkdownServerReadSnapshotBuildError.missingRule("all")) {
      try await MarkdownServerReadSnapshotBuilder(
        store: emptyStore,
        plan: rulePlan,
        typeRegistry: registry
      ).build()
    }

    let typePlan = try makePlan(
      registry: registry,
      rules: [],
      resources: [resource(
        name: "books",
        route: "/books",
        selection: .type(name: type.name, searchRoot: ".")
      )]
    )
    let emptyRegistry = try MarkdownTypeRegistry(definitions: [])
    await #expect(throws: MarkdownServerReadSnapshotBuildError.missingType(type.name)) {
      try await MarkdownServerReadSnapshotBuilder(
        store: emptyStore,
        plan: typePlan,
        typeRegistry: emptyRegistry
      ).build()
    }

    let token = RecordStoreContinuationToken(rawValue: "repeat")
    let cyclingStore = RepeatingTokenStore(token: token)
    await #expect(throws: MarkdownServerReadSnapshotBuildError.repeatedContinuationToken(token)) {
      try await MarkdownServerReadSnapshotBuilder(
        store: cyclingStore,
        plan: rulePlan,
        rules: [rule],
        typeRegistry: registry
      ).build()
    }
  }

  @Test
  func `Store failures and cancellation propagate unchanged`() async throws {
    let registry = try MarkdownTypeRegistry(definitions: [])
    let rule = MarkdownRuleDefinition(name: "all")
    let plan = try makePlan(
      registry: registry,
      rules: [rule],
      resources: [resource(name: "all", route: "/all", selection: .rule(name: "all"))]
    )

    await #expect(throws: RecordStoreError.unavailable) {
      try await MarkdownServerReadSnapshotBuilder(
        store: UnavailableStore(),
        plan: plan,
        rules: [rule],
        typeRegistry: registry
      ).build()
    }

    let builder = try MarkdownServerReadSnapshotBuilder(
      store: FixtureRecordStore(pages: [[]]),
      plan: plan,
      rules: [rule],
      typeRegistry: registry
    )
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await builder.build()
    }
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test
  func `Generic envelopes and lookup results round trip through Codable and are Sendable`() async throws {
    let membership = GenericMarkdownResourceMembership(
      resourceName: "records",
      selectionMode: .rule,
      identity: MarkdownRecordIdentity(rawValue: "one"),
      identityStatus: .available,
      ruleAssessment: GenericMarkdownRuleAssessment(name: "all", applicable: true, passes: true),
      selectedType: nil,
      assessedTypes: [],
      valid: true
    )
    let record = GenericMarkdownRecord(
      canonicalIdentity: MarkdownRecordIdentity(rawValue: "one"),
      identityStatus: .available,
      logicalPath: try MarkdownRecordPath("one.md"),
      revision: MarkdownRecordRevision(rawValue: "1"),
      memberships: [membership],
      valid: true,
      frontmatter: ["title": .string("One")],
      body: "# One",
      diagnostics: []
    )
    let lookup = MarkdownServerReadLookupResult.record(record)

    #expect(try JSONDecoder().decode(
      GenericMarkdownRecord.self,
      from: JSONEncoder().encode(record)
    ) == record)
    #expect(try JSONDecoder().decode(
      MarkdownServerReadLookupResult.self,
      from: JSONEncoder().encode(lookup)
    ) == lookup)
    requireSendable(record)
    requireSendable(lookup)
  }

  /// Compiles deterministic resources against the definitions used by the builder.
  private func makePlan(
    registry: MarkdownTypeRegistry,
    rules: [MarkdownRuleDefinition],
    resources: [MarkdownResourceConfiguration]
  ) throws -> EndpointPlan {
    try EndpointPlanCompiler(rules: rules, typeRegistry: registry).compile(
      MarkdownServerConfiguration(resources: resources)
    )
  }

  /// Creates one list-and-get resource with configurable selection and identity.
  private func resource(
    name: String,
    route: String,
    selection: MarkdownResourceSelection,
    identityPolicy: MarkdownRecordIdentityPolicy = MarkdownRecordIdentityPolicy(
      source: .existingIdentity
    )
  ) -> MarkdownResourceConfiguration {
    MarkdownResourceConfiguration(
      name: name,
      route: route,
      operations: [.list, .get],
      selection: selection,
      identityPolicy: identityPolicy
    )
  }

  /// Creates one canonical fixture with optional logical path metadata.
  private func record(
    identity: String,
    path: String? = nil,
    content: String
  ) throws -> MarkdownRecord {
    MarkdownRecord(
      identity: MarkdownRecordIdentity(rawValue: identity),
      content: content,
      context: MarkdownRecordContext(path: try path.map(MarkdownRecordPath.init))
    )
  }

  /// Enforces `Sendable` conformance at compile time.
  private func requireSendable<Value: Sendable>(_ value: Value) {
    _ = value
  }
}

/// Counts shared analyzer invocations without introducing data races in tests.
private actor AnalysisCounter {
  private(set) var value = 0

  /// Records one analyzer invocation.
  func increment() {
    value += 1
  }
}

/// Deterministic paged store used to exercise snapshot enumeration and invalid records.
private actor FixtureRecordStore: RecordStore {
  let pages: [[MarkdownRecord]]

  /// Creates a fixture whose continuation token is the next page index.
  init(pages: [[MarkdownRecord]]) {
    self.pages = pages
  }

  func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    guard let record = pages.flatMap({ $0 }).first(where: { $0.identity == identity }) else {
      throw RecordStoreError.notFound(identity)
    }
    return record
  }

  func records(matching query: RecordStoreQuery) async throws -> RecordStorePage {
    let index = query.continuationToken.flatMap { Int($0.rawValue) } ?? 0
    guard pages.indices.contains(index) else { return RecordStorePage(records: []) }
    let next = index + 1 < pages.count
      ? RecordStoreContinuationToken(rawValue: String(index + 1))
      : nil
    return RecordStorePage(records: pages[index], continuationToken: next)
  }

  func create(_ record: MarkdownRecord) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func replace(
    _ record: MarkdownRecord,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func delete(
    identity: MarkdownRecordIdentity,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws {
    throw RecordStoreError.unavailable
  }
}

/// Invalid store fixture that repeats one continuation token forever.
private actor RepeatingTokenStore: RecordStore {
  let token: RecordStoreContinuationToken

  init(token: RecordStoreContinuationToken) {
    self.token = token
  }

  func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    throw RecordStoreError.notFound(identity)
  }

  func records(matching query: RecordStoreQuery) async throws -> RecordStorePage {
    RecordStorePage(records: [], continuationToken: token)
  }

  func create(_ record: MarkdownRecord) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func replace(
    _ record: MarkdownRecord,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func delete(
    identity: MarkdownRecordIdentity,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws {
    throw RecordStoreError.unavailable
  }
}

/// Store fixture that exposes one stable backend failure.
private actor UnavailableStore: RecordStore {
  func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func records(matching query: RecordStoreQuery) async throws -> RecordStorePage {
    throw RecordStoreError.unavailable
  }

  func create(_ record: MarkdownRecord) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func replace(
    _ record: MarkdownRecord,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws -> MarkdownRecord {
    throw RecordStoreError.unavailable
  }

  func delete(
    identity: MarkdownRecordIdentity,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws {
    throw RecordStoreError.unavailable
  }
}
