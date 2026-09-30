import Foundation
import Hummingbird
import HummingbirdTesting
import JSONSchema
import MarkdownUtilitiesCore
import enum OpenAPIKit.OpenAPI
import Testing
import Yams
@testable import MarkdownUtilitiesServer

@Suite("Mutation OpenAPI contract")
struct MarkdownMutationOpenAPITests {
  private func fixture(bodyWritable: Bool = true) async throws -> (EndpointPlan, MarkdownServerReadSnapshot) {
    let types = try MarkdownTypeRegistry(definitions: [])
    let rules = try MarkdownRuleCompiler(typeRegistry: types).compile([.init(name: "all")])
    let config = MarkdownServerConfiguration(serverConfigVersion: "3", resources: [
      .init(name: "books", route: "/books", operations: [.list, .get], selection: .rule(name: "all"),
        identityPolicy: .init(source: .frontmatter(path: ["slug"], format: .string)),
        writable: .init(codec: .init(frontmatterFields: ["title", "subtitle"], bodyWritable: bodyWritable), creation: .init(template: "# Book")),
        mutations: .init(operations: MarkdownMutationOperation.allCases,
          creation: .init(directory: try #require(.init(rawValue: "books/")), identifiers: ["slug"]), identityFields: ["slug"]),
        lookups: [.init(name: "uuid", source: .persistentIdentity)],
      ),
      .init(name: "readonly", route: "/readonly", operations: [.list, .get], selection: .rule(name: "all"), identityPolicy: .init(source: .logicalPath)),
    ], persistentIdentity: .init(path: ["uuid"]))
    let plan = try EndpointPlanCompiler(ruleRegistry: rules, typeRegistry: types).compile(config)
    let snapshot = try await MarkdownServerReadSnapshotBuilder(store: InMemoryRecordStore(), plan: plan,
      ruleRegistry: rules, typeRegistry: types).build()
    return (plan, snapshot)
  }

  @Test
  func `all routes match registration and served JSON matches deterministic exports`() async throws {
    guard #available(macOS 14.0, *) else { return }
    let (plan, snapshot) = try await fixture()
    let document = try MarkdownServerOpenAPIGenerator.generate(from: plan)
    let json = try document.serialized(format: .json)
    let yaml = try document.serialized(format: .yaml)
    let repeated = try MarkdownServerOpenAPIGenerator.generate(from: plan)
    #expect(json == (try repeated.serialized(format: .json)))
    #expect(yaml == (try repeated.serialized(format: .yaml)))
    #expect(try YAMLDecoder().decode(JSONValue.self, from: yaml) == document.value)
    try JSONDecoder().decode(OpenAPI.Document.self, from: json).validate(strict: true)
    try YAMLDecoder().decode(OpenAPI.Document.self, from: yaml).validate(strict: true)
    let paths = try #require(document.value.objectValue?["paths"]?.objectValue)
    var actual: [String] = []
    for (path, methods) in paths {
      for (method, operation) in try #require(methods.objectValue) {
        actual.append("\(path) \(method.uppercased()) \(try #require(operation.objectValue?["operationId"]?.stringValue))")
      }
    }
    #expect(actual.sorted() == plan.routes.map { "\($0.path.rawValue) \($0.method.rawValue) \($0.operationID)" }.sorted())
    #expect(Set(try #require(paths["/readonly"]?.objectValue).keys) == ["get"])
    let router = Router()
    let installed = try MarkdownServerHTTPAdapter.register(plan: plan,
      repository: MarkdownSnapshotReadRepository(snapshot: snapshot), mutations: ReceiptService(), on: router)
    #expect(installed == plan.routes)
    try await Application(router: router).test(.router) { client in
      try await client.execute(uri: "/openapi.json", method: .get) { response in
        #expect(Data(response.body.readableBytesView) == json)
      }
    }
  }

  @Test
  func `metadata-only codecs reject body input without requiring it on replacement`() async throws {
    let (plan, _) = try await fixture(bodyWritable: false)
    let document = try MarkdownServerOpenAPIGenerator.generate(from: plan).value
    let path = try #require(document.objectValue?["paths"]?.objectValue?["/books/{id}"]?.objectValue)
    for method in ["put", "patch"] {
      let schema = try #require(path[method]?.objectValue?["requestBody"]?.objectValue?["content"]?.objectValue?["application/json"]?.objectValue?["schema"])
      #expect(try valid(["frontmatter": [:]], schema: schema, document: document))
      #expect(try !valid(["frontmatter": [:], "body": "changed"], schema: schema, document: document))
    }
  }

  @Test
  func `request schemas describe explicit codec and required preconditions`() async throws {
    let (plan, _) = try await fixture()
    let document = try MarkdownServerOpenAPIGenerator.generate(from: plan).value
    let paths = try #require(document.objectValue?["paths"]?.objectValue)
    func request(_ path: String, _ method: String) throws -> JSONValue {
      try #require(paths[path]?.objectValue?[method]?.objectValue?["requestBody"]?.objectValue?["content"]?.objectValue?["application/json"]?.objectValue?["schema"])
    }
    let put = try request("/books/{id}", "put")
    #expect(try valid(["frontmatter": ["title": "Book"], "body": "# Book"], schema: put, document: document))
    #expect(try !valid(["frontmatter": ["title": "Book"]], schema: put, document: document))
    #expect(try !valid(["frontmatter": ["uuid": "protected"], "body": "# Book"], schema: put, document: document))
    let patch = try request("/books/{id}", "patch")
    #expect(try valid(["frontmatter": ["set": ["title": NSNull()], "remove": ["subtitle"]]], schema: patch, document: document))
    #expect(try !valid(["body": NSNull()], schema: patch, document: document))
    #expect(try !valid(["frontmatter": ["remove": ["title", "title"]]], schema: patch, document: document))
    #expect(try !valid(["revision": "no"], schema: patch, document: document))
    let create = try request("/books", "post")
    #expect(try valid(["identifiers": ["slug": "book"], "frontmatter": ["title": "Book"]], schema: create, document: document))
    #expect(try !valid(["validationPolicy": "endpointOnly"], schema: create, document: document))
    #expect(try !valid(["identifiers": ["uuid": "no"]], schema: create, document: document))
    let repair = try request("/books/{id}/repair-uuid", "post")
    #expect(try valid([:], schema: repair, document: document))
    #expect(try !valid(["uuid": "no"], schema: repair, document: document))
    for route in plan.routes where route.kind == .mutation {
      let operation = try #require(paths[route.path.rawValue]?.objectValue?[route.method.rawValue.lowercased()]?.objectValue)
      guard case .array(let parameters) = operation["parameters"] else {
        Issue.record("Missing parameters"); continue
      }
      let header = route.mutationOperation == .create ? "Idempotency-Key" : "MD-Utils-If-Revision"
      #expect(parameters.contains { $0.objectValue?["name"] == .string(header) && $0.objectValue?["required"] == .boolean(true) })
      if route.lookupUsesQuery == true {
        #expect(parameters.contains { $0.objectValue?["name"] == .string(route.lookupName == nil ? "path" : "value") })
      }
    }
  }

  @Test(arguments: ["completed", "committed", "prepared", "recoveryRequired", "abandoned"])
  func `actual HTTP receipts and errors validate against generated components`(state: String) async throws {
    guard #available(macOS 14.0, *) else { return }
    let (plan, snapshot) = try await fixture()
    let document = try MarkdownServerOpenAPIGenerator.generate(from: plan).value
    let service = ReceiptService(state: try #require(MarkdownMutationReceipt.State(rawValue: state)))
    let router = Router()
    try MarkdownServerHTTPAdapter.register(plan: plan, repository: MarkdownSnapshotReadRepository(snapshot: snapshot), mutations: service, on: router)
    let revision = try #require(HTTPFields.Element.Name("MD-Utils-If-Revision"))
    let idempotency = try #require(HTTPFields.Element.Name("Idempotency-Key"))
    let writeHeaders: HTTPFields = [.contentType: "application/json", revision: MarkdownRevisionHeader.encode(.init(rawValue: "abc"))]
    try await Application(router: router).test(.router) { client in
      let requests: [(String, HTTPRequest.Method, String, HTTPFields, String)] = [
        ("/books/_operations/test", HTTPRequest.Method.get, "/books/_operations/{id}", HTTPFields(), ""),
        ("/books", .post, "/books", [.contentType: "application/json", idempotency: "one"], "{}"),
        ("/books/test", .put, "/books/{id}", writeHeaders, "{\"frontmatter\":{},\"body\":\"Book\"}"),
        ("/books/test", .patch, "/books/{id}", writeHeaders, "{}"),
        ("/books/test/identity", .post, "/books/{id}/identity", writeHeaders, "{\"identifiers\":{\"slug\":\"new\"}}"),
        ("/books/test/repair-uuid", .post, "/books/{id}/repair-uuid", writeHeaders, "{}"),
        ("/books/_operations/test/resolve", .post, "/books/_operations/{id}/resolve", [.contentType: "application/json"], "{\"decision\":\"confirmCommitted\"}"),
        ("/books/test", .delete, "/books/{id}", [revision: MarkdownRevisionHeader.encode(.init(rawValue: "abc"))], ""),
        ("/books/test", .patch, "/books/{id}", [.contentType: "application/json"], "{}"),
        ("/books/test", .patch, "/books/{id}", [.contentType: "application/json", revision: MarkdownRevisionHeader.encode(.init(rawValue: "abc"))], "{\"unknown\":true}"),
      ]
      for (uri, method, path, headers, body) in requests {
        try await client.execute(uri: uri, method: method, headers: headers, body: ByteBuffer(string: body)) { response in
          let operation = try #require(document.objectValue?["paths"]?.objectValue?[path]?.objectValue?[method.rawValue.lowercased()]?.objectValue)
          let schema = try #require(operation["responses"]?.objectValue?[String(response.status.code)]?.objectValue?["content"]?.objectValue?["application/json"]?.objectValue?["schema"])
          let payload = try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView))
          #expect(try valid(payload, schema: schema, document: document))
        }
      }
    }
  }

  private func valid(_ instance: Any, schema: JSONValue, document: JSONValue) throws -> Bool {
    var root = try #require(schema.objectValue)
    root["components"] = document.objectValue?["components"]
    let data = try JSONEncoder().encode(JSONValue.object(root))
    let foundation = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try JSONSchema.validate(instance, schema: foundation).valid
  }
}

private struct ReceiptService: MarkdownMutationService {
  var state: MarkdownMutationReceipt.State = .completed
  var operationKind: MarkdownMutationOperation = .delete
  func operation(resource: String, id: String) async throws -> MarkdownMutationReceipt {
    var receipt = MarkdownMutationReceipt(id: id, resource: resource, operation: operationKind,
      path: try .init("books/test.md"), revision: .init(rawValue: "abc"), baseline: .init(rawValue: "old"), requestHash: "hash", keyHash: nil,
      diagnostics: [.init(code: "template.knap.warning", severity: .advisory, domain: .body, location: "template:1:1", message: "Warning",
        fixIts: [.init(id: "fix", title: "Fix", safety: .requiresInput, edits: [
          .ensureFrontmatter, .setFrontmatterValue(path: ["title"], value: .null),
          .requestFrontmatterValue(path: ["author"]), .appendHeading(text: "Book", level: 1),
        ])])],
    )
    receipt.state = state
    receipt.sourceCommitted = state == .committed || state == .completed
    receipt.completedAt = state == .completed ? Date() : nil
    receipt.record = GenericMarkdownRecord(canonicalIdentity: .init(rawValue: "canonical"), identityStatus: .available,
      logicalPath: try .init("books/test.md"), revision: .init(rawValue: "abc"), memberships: [], valid: true,
      frontmatter: ["title": .string("Book")], body: "# Book", diagnostics: [])
    receipt.conformanceChanges = try JSONDecoder().decode([ResourceConformanceChange].self, from: Data(#"[{"kind":"type","name":"Book","previouslyPassed":true,"passes":false,"previouslySelected":true,"selected":false,"diagnostics":[]}]"#.utf8))
    return receipt
  }
  func mutate(resource: String, identity: String?, path: MarkdownRecordPath?, request: MarkdownMutationRequest,
    revision: MarkdownRecordRevision?, idempotencyKey: String?,
  ) async throws -> MarkdownMutationReceipt {
    var service = self
    service.operationKind = request.operation
    return try await service.operation(resource: resource, id: "test")
  }
  func resolveOperation(resource: String, id: String, decision: MarkdownRecoveryDecision) async throws -> MarkdownMutationReceipt {
    try await operation(resource: resource, id: id)
  }
}
