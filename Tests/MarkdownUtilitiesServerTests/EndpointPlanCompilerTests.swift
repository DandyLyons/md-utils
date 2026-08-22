import Foundation
import MarkdownUtilitiesCore
import Testing
@testable import MarkdownUtilitiesServer

@Suite("Endpoint plan compiler")
struct EndpointPlanCompilerTests {
  // MARK: Successful compilation

  @Test
  func `Compile all three selection modes into deterministic routes`() async throws {
    let registry = try makeRegistry("Book")
    let rules = [makeRule("published"), makeRule("review-queue")]
    let configuration = MarkdownServerConfiguration(resources: [
      makeResource(
        name: "reviews",
        route: "/reviews",
        operations: [.get],
        selection: .ruleWithExpectedType(
          rule: "review-queue",
          expectedType: MarkdownTypeName(rawValue: "Book")
        )
      ),
      makeResource(
        name: "books",
        route: "/books",
        operations: [.list, .get],
        selection: .type(name: MarkdownTypeName(rawValue: "Book"), searchRoot: "books/")
      ),
      makeResource(
        name: "published",
        route: "/published",
        operations: [.list],
        selection: .rule(name: "published")
      ),
    ])

    let ruleRegistry = try MarkdownRuleCompiler(typeRegistry: registry).compile(rules)
    let plan = try EndpointPlanCompiler(
      ruleRegistry: ruleRegistry,
      typeRegistry: registry
    ).compile(configuration)

    #expect(plan.serverConfigVersion == "1")
    #expect(plan.resources.map(\.name) == ["books", "published", "reviews"])
    #expect(plan.typeSchemas.map(\.name.rawValue) == ["Book"])
    #expect(plan.routes.map(\.path.rawValue) == [
      "/_md-utils/path/{path}",
      "/books",
      "/books/{id}",
      "/openapi.json",
      "/published",
      "/reviews/{id}",
    ])
    #expect(plan.routes.map(\.operationID) == [
      "md-utils.path.get",
      "books.list",
      "books.get",
      "md-utils.openapi.get",
      "published.list",
      "reviews.get",
    ])
    let books = try #require(plan.resources.first { $0.name == "books" })
    #expect(books.operations == [.get, .list])
    #expect(books.projectionPolicy == .genericRecord)
    #expect(books.identityPolicy == MarkdownRecordIdentityPolicy(source: .existingIdentity))
    #expect(books.selection == .type(
      name: MarkdownTypeName(rawValue: "Book"),
      searchRoot: try #require(MarkdownSearchRoot(rawValue: "books/"))
    ))
  }

  @Test
  func `Explicit operation IDs override deterministic defaults`() async throws {
    let resource = makeResource(
      operations: [.list, .get],
      operationIDOverrides: [
        MarkdownOperationIDOverride(operation: .get, operationID: "fetchBook"),
      ]
    )

    let plan = try compiler().compile(MarkdownServerConfiguration(resources: [resource]))

    #expect(plan.routes.first { $0.kind == .collection }?.operationID == "books.list")
    #expect(plan.routes.first { $0.kind == .item }?.operationID == "fetchBook")
  }

  @Test
  func `Logical path route is conditional and emitted once`() async throws {
    let fallback = MarkdownRecordIdentityPolicy(source: .existingIdentity)
    let resources = [
      makeResource(name: "books", route: "/books", identityPolicy: fallback),
      makeResource(name: "authors", route: "/authors", identityPolicy: fallback),
    ]

    let plan = try compiler().compile(MarkdownServerConfiguration(resources: resources))
    #expect(plan.routes.filter { $0.kind == .logicalPath }.count == 1)

    let disabled = makeResource(
      identityPolicy: MarkdownRecordIdentityPolicy(
        source: .existingIdentity,
        logicalPathFallbackEnabled: false
      )
    )
    let disabledPlan = try compiler().compile(MarkdownServerConfiguration(resources: [disabled]))
    #expect(disabledPlan.routes.contains { $0.kind == .logicalPath } == false)

    let listOnly = makeResource(operations: [.list], identityPolicy: fallback)
    let listPlan = try compiler().compile(MarkdownServerConfiguration(resources: [listOnly]))
    #expect(listPlan.routes.contains { $0.kind == .logicalPath } == false)
  }

  @Test
  func `Empty configuration produces only the contract route`() async throws {
    let plan = try compiler().compile(MarkdownServerConfiguration())

    #expect(plan.resources.isEmpty)
    #expect(plan.routes.map(\.path.rawValue) == ["/openapi.json"])
  }

  @Test
  func `Equivalent reordered inputs produce identical plans`() async throws {
    let first = makeResource(name: "books", route: "/books", operations: [.list, .get])
    let second = makeResource(name: "authors", route: "/authors", operations: [.get, .list])
    let forward = try compiler().compile(MarkdownServerConfiguration(resources: [first, second]))
    let reverse = try compiler().compile(MarkdownServerConfiguration(resources: [second, first]))

    #expect(forward == reverse)
  }

  @Test
  func `Overlapping type membership across resources is allowed`() async throws {
    let registry = try makeRegistry("Person")
    let resources = [
      makeResource(
        name: "people",
        route: "/people",
        selection: .type(name: MarkdownTypeName(rawValue: "Person"), searchRoot: "people/")
      ),
      makeResource(
        name: "authors",
        route: "/authors",
        selection: .type(name: MarkdownTypeName(rawValue: "Person"), searchRoot: "authors/")
      ),
    ]

    let plan = try EndpointPlanCompiler(
      ruleRegistry: try MarkdownRuleCompiler(typeRegistry: registry).compile([]),
      typeRegistry: registry
    ).compile(
      MarkdownServerConfiguration(resources: resources)
    )

    #expect(plan.resources.count == 2)
  }

  // MARK: Structured validation failures

  @Test
  func `Missing references produce structured diagnostics`() async throws {
    let resources = [
      makeResource(name: "missing-rule", route: "/missing-rule", selection: .rule(name: "absent")),
      makeResource(
        name: "missing-type",
        route: "/missing-type",
        selection: .type(name: MarkdownTypeName(rawValue: "Absent"), searchRoot: ".")
      ),
    ]
    let diagnostics = try compilationDiagnostics(
      configuration: MarkdownServerConfiguration(resources: resources),
      compiler: EndpointPlanCompiler(
        ruleRegistry: try MarkdownRuleCompiler(typeRegistry: makeRegistry("Book")).compile([]),
        typeRegistry: makeRegistry("Book")
      )
    )

    #expect(Set(diagnostics.map(\.code)) == [.missingRule, .missingType])
  }

  @Test
  func `Configuration identity and operation errors are aggregated`() async throws {
    let invalid = makeResource(
      name: " books ",
      operations: [.get, .get],
      operationIDOverrides: [
        MarkdownOperationIDOverride(operation: .get, operationID: " "),
        MarkdownOperationIDOverride(operation: .get, operationID: "again"),
        MarkdownOperationIDOverride(operation: .list, operationID: "disabled"),
      ]
    )
    let empty = makeResource(name: "empty", route: "/empty", operations: [])
    let duplicateOne = makeResource(name: "same", route: "/same-one")
    let duplicateTwo = makeResource(name: "same", route: "/same-two")

    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(
      serverConfigVersion: "2",
      resources: [invalid, empty, duplicateOne, duplicateTwo]
    ))
    let codes = Set(diagnostics.map(\.code))

    #expect(codes.contains(.unsupportedConfigurationVersion))
    #expect(codes.contains(.invalidResourceName))
    #expect(codes.contains(.duplicateResourceName))
    #expect(codes.contains(.missingOperations))
    #expect(codes.contains(.duplicateOperation))
    #expect(codes.contains(.duplicateOperationIDOverride))
    #expect(codes.contains(.operationIDForDisabledOperation))
    #expect(codes.contains(.invalidOperationID))
  }

  @Test(arguments: [
    "books",
    "/",
    "/books/",
    "/books//published",
    "/books/../private",
    "/books/{slug}",
    "/books/:slug",
    "/books/*",
    "/books?draft=true",
    "/books#drafts",
    "/books%2Fprivate",
    "/books\\private",
  ])
  func `Unsafe resource routes fail compilation`(_ route: String) async throws {
    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(resources: [
      makeResource(route: route),
    ]))

    #expect(diagnostics.map(\.code).contains(.unsafeRoute))
  }

  @Test(arguments: ["/_md-utils", "/_md-utils/path", "/_md-utils/custom"])
  func `Reserved resource routes fail compilation`(_ route: String) async throws {
    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(resources: [
      makeResource(route: route),
    ]))

    #expect(diagnostics.map(\.code).contains(.reservedRoute))
  }

  @Test(arguments: [
    "",
    "/books/",
    "books",
    "./books/",
    "books/../private/",
    "books//published/",
  ])
  func `Invalid type search roots fail compilation`(_ searchRoot: String) async throws {
    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(resources: [
      makeResource(selection: .type(
        name: MarkdownTypeName(rawValue: "Book"),
        searchRoot: searchRoot
      )),
    ]))

    #expect(diagnostics.map(\.code).contains(.invalidSearchRoot))
  }

  @Test
  func `Literal collection route cannot overlap an item route`() async throws {
    let resources = [
      makeResource(name: "books", route: "/books", operations: [.get]),
      makeResource(name: "featured", route: "/books/featured", operations: [.list]),
    ]

    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(
      resources: resources
    ))

    #expect(diagnostics.map(\.code).contains(.routeCollision))
  }

  @Test
  func `Duplicate routes and operation IDs fail compilation`() async throws {
    let resources = [
      makeResource(
        name: "books",
        route: "/content",
        operations: [.list],
        operationIDOverrides: [
          MarkdownOperationIDOverride(operation: .list, operationID: "content.list"),
        ]
      ),
      makeResource(
        name: "articles",
        route: "/content",
        operations: [.list],
        operationIDOverrides: [
          MarkdownOperationIDOverride(operation: .list, operationID: "content.list"),
        ]
      ),
    ]

    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(
      resources: resources
    ))
    let codes = Set(diagnostics.map(\.code))

    #expect(codes.contains(.routeCollision))
    #expect(codes.contains(.duplicateOperationID))
  }

  // MARK: Public value guarantees

  @Test
  func `Configuration plan diagnostics and values round trip through Codable`() async throws {
    let configuration = MarkdownServerConfiguration(resources: [makeResource(
      operationIDOverrides: [
        MarkdownOperationIDOverride(operation: .get, operationID: "fetchBook"),
      ]
    )])
    let configurationData = try JSONEncoder().encode(configuration)
    #expect(try JSONDecoder().decode(MarkdownServerConfiguration.self, from: configurationData) == configuration)

    let plan = try compiler().compile(configuration)
    let planData = try JSONEncoder().encode(plan)
    #expect(try JSONDecoder().decode(EndpointPlan.self, from: planData) == plan)

    let diagnostics = try compilationDiagnostics(configuration: MarkdownServerConfiguration(
      serverConfigVersion: "unsupported"
    ))
    let error = EndpointPlanCompilationError(diagnostics: diagnostics)
    let errorData = try JSONEncoder().encode(error)
    #expect(try JSONDecoder().decode(EndpointPlanCompilationError.self, from: errorData) == error)
  }

  @Test
  func `Public configuration and plan values are Sendable`() async throws {
    let configuration = MarkdownServerConfiguration(resources: [makeResource()])
    let plan = try compiler().compile(configuration)

    requireSendable(configuration)
    requireSendable(plan)
    requireSendable(try compiler())
  }

  // MARK: Fixtures

  /// Creates the common compiler fixture used by successful and failing scenarios.
  private func compiler() throws -> EndpointPlanCompiler {
    let typeRegistry = try makeRegistry("Book")
    return EndpointPlanCompiler(
      ruleRegistry: try MarkdownRuleCompiler(typeRegistry: typeRegistry).compile([
        makeRule("published")
      ]),
      typeRegistry: typeRegistry
    )
  }

  /// Creates a validated registry containing minimal definitions for the supplied names.
  private func makeRegistry(_ names: String...) throws -> MarkdownTypeRegistry {
    try MarkdownTypeRegistry(definitions: names.map { name in
      MarkdownTypeDefinition(name: MarkdownTypeName(rawValue: name), version: "1")
    })
  }

  /// Creates a reusable rule definition whose behavior is irrelevant to plan compilation.
  private func makeRule(_ name: String) -> MarkdownRuleDefinition {
    MarkdownRuleDefinition(name: name)
  }

  /// Creates a representative resource while allowing each validation dimension to vary.
  private func makeResource(
    name: String = "books",
    route: String = "/books",
    operations: [MarkdownResourceOperation] = [.get],
    selection: MarkdownResourceSelection = .type(
      name: MarkdownTypeName(rawValue: "Book"),
      searchRoot: "books/"
    ),
    identityPolicy: MarkdownRecordIdentityPolicy = MarkdownRecordIdentityPolicy(
      source: .existingIdentity
    ),
    operationIDOverrides: [MarkdownOperationIDOverride] = []
  ) -> MarkdownResourceConfiguration {
    MarkdownResourceConfiguration(
      name: name,
      route: route,
      operations: operations,
      selection: selection,
      identityPolicy: identityPolicy,
      operationIDOverrides: operationIDOverrides
    )
  }

  /// Compiles an invalid fixture and extracts its structured diagnostics.
  private func compilationDiagnostics(
    configuration: MarkdownServerConfiguration,
    compiler: EndpointPlanCompiler? = nil
  ) throws -> [EndpointPlanDiagnostic] {
    do {
      _ = try (compiler ?? self.compiler()).compile(configuration)
      Issue.record("Expected endpoint plan compilation to fail")
      return []
    } catch let error as EndpointPlanCompilationError {
      return error.diagnostics
    }
  }

  /// Enforces `Sendable` conformance at compile time.
  private func requireSendable<Value: Sendable>(_ value: Value) {
    _ = value
  }
}
