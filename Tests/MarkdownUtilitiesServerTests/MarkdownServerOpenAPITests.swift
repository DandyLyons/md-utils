import Foundation
import Hummingbird
import MarkdownUtilitiesCore
import OpenAPIKit
import Testing
import Yams
@testable import MarkdownUtilitiesServer

@Suite("Generated OpenAPI contract")
struct MarkdownServerOpenAPITests {
  @Test
  func `JSON and YAML are deterministic equivalent and valid OpenAPI 3 point 1`() throws {
    let plan = try makePlan()
    let first = try MarkdownServerOpenAPIGenerator.generate(from: plan)
    let second = try MarkdownServerOpenAPIGenerator.generate(from: plan)

    let firstJSON = try first.serialized(format: .json)
    let secondJSON = try second.serialized(format: .json)
    let firstYAML = try first.serialized(format: .yaml)
    let secondYAML = try second.serialized(format: .yaml)
    #expect(firstJSON == secondJSON)
    #expect(firstYAML == secondYAML)

    let jsonValue = try JSONDecoder().decode(JSONValue.self, from: firstJSON)
    let yamlValue = try YAMLDecoder().decode(JSONValue.self, from: firstYAML)
    #expect(jsonValue == yamlValue)

    let jsonDocument = try JSONDecoder().decode(OpenAPI.Document.self, from: firstJSON)
    let yamlDocument = try YAMLDecoder().decode(OpenAPI.Document.self, from: firstYAML)
    try jsonDocument.validate(strict: true)
    try yamlDocument.validate(strict: true)
  }

  @Test
  func `Generated operations exactly match plan routes`() async throws {
    guard #available(macOS 14.0, *) else { return }
    let plan = try makePlan()
    let document = try MarkdownServerOpenAPIGenerator.generate(from: plan)
    let generated = try operationTuples(document.value)
    let planned = plan.routes.map { ($0.path.rawValue, $0.method.rawValue, $0.operationID) }

    let typeRegistry = try makeTypeRegistry()
    let ruleRegistry = try makeRuleRegistry(typeRegistry: typeRegistry)
    let snapshot = try await MarkdownServerReadSnapshotBuilder(
      store: InMemoryRecordStore(),
      plan: plan,
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).build()
    let installed = try MarkdownServerHTTPAdapter.register(
      plan: plan,
      snapshot: snapshot,
      on: Router()
    ).map { ($0.path.rawValue, $0.method.rawValue, $0.operationID) }

    #expect(generated.map(TupleValue.init) == planned.map(TupleValue.init))
    #expect(installed.map(TupleValue.init) == planned.map(TupleValue.init))
  }

  @Test
  func `Type selection constrains frontmatter while expected type documents invalid records`() throws {
    let document = try MarkdownServerOpenAPIGenerator.generate(from: makePlan())
    let root = try #require(document.value.objectValue)
    let paths = try #require(root["paths"]?.objectValue)
    let booksGet = try operation(path: "/books", in: paths)
    let draftsGet = try operation(path: "/drafts", in: paths)
    let bookSchemaReference = "#/components/schemas/MarkdownType_426F6F6B_Frontmatter"

    #expect(draftsGet["x-md-utils-expected-frontmatter-schema"]?.objectValue?["$ref"]?.stringValue
      == bookSchemaReference)
    let booksSchema = try responseSchema(in: booksGet)
    #expect(containsReference(bookSchemaReference, in: booksSchema))
    let draftsSchema = try responseSchema(in: draftsGet)
    #expect(containsReference("#/components/schemas/GenericMarkdownRecord", in: draftsSchema))
    #expect(containsReference(bookSchemaReference, in: draftsSchema) == false)
  }

  @Test
  func `Unsupported resolved schemas fail with a located diagnostic`() throws {
    let valid = try makePlan()
    let invalidSchema = ResolvedMarkdownTypeFrontmatterSchema(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1",
      presence: .required,
      schemas: [.object(["type": .integer(1)])]
    )
    let invalid = EndpointPlan(
      serverConfigVersion: valid.serverConfigVersion,
      resources: valid.resources,
      routes: valid.routes,
      typeSchemas: [invalidSchema]
    )

    do {
      _ = try MarkdownServerOpenAPIGenerator.generate(from: invalid)
      Issue.record("Expected unsupported schema generation to fail")
    } catch let error as MarkdownServerOpenAPIGenerationError {
      #expect(error.diagnostics.map(\.code) == [.unsupportedSchema])
      #expect(error.diagnostics.first?.location == "typeSchemas[0].schemas[0]")
    }
  }

  @Test
  func `Decoded plan route drift fails instead of overwriting an operation`() throws {
    let valid = try makePlan()
    let duplicateRoute = try #require(valid.routes.first)
    let invalid = EndpointPlan(
      serverConfigVersion: valid.serverConfigVersion,
      resources: valid.resources,
      routes: valid.routes + [duplicateRoute],
      typeSchemas: valid.typeSchemas
    )

    do {
      _ = try MarkdownServerOpenAPIGenerator.generate(from: invalid)
      Issue.record("Expected duplicate generated path to fail")
    } catch let error as MarkdownServerOpenAPIGenerationError {
      #expect(error.diagnostics.contains {
        $0.code == .invalidPlan && $0.location.hasSuffix(".path")
      })
    }
  }

  private func makePlan() throws -> EndpointPlan {
    let typeRegistry = try makeTypeRegistry()
    let ruleRegistry = try makeRuleRegistry(typeRegistry: typeRegistry)
    let book = MarkdownTypeName(rawValue: "Book")
    return try EndpointPlanCompiler(
      ruleRegistry: ruleRegistry,
      typeRegistry: typeRegistry
    ).compile(MarkdownServerConfiguration(resources: [
      MarkdownResourceConfiguration(
        name: "books",
        route: "/books",
        operations: [.list, .get],
        selection: .type(name: book, searchRoot: "."),
        identityPolicy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
      ),
      MarkdownResourceConfiguration(
        name: "drafts",
        route: "/drafts",
        operations: [.list],
        selection: .ruleWithExpectedType(rule: "all", expectedType: book),
        identityPolicy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
      ),
    ]))
  }

  private func makeTypeRegistry() throws -> MarkdownTypeRegistry {
    try MarkdownTypeRegistry(definitions: [
      MarkdownTypeDefinition(
        name: MarkdownTypeName(rawValue: "Book"),
        version: "1",
        frontmatter: MarkdownFrontmatterDefinition(
          schemas: [.inline(.object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "type": .string("object"),
            "required": .array([.string("title")]),
            "properties": .object([
              "title": .object(["type": .string("string")]),
            ]),
          ]))]
        )
      ),
    ])
  }

  private func makeRuleRegistry(
    typeRegistry: MarkdownTypeRegistry
  ) throws -> MarkdownRuleRegistry {
    try MarkdownRuleCompiler(typeRegistry: typeRegistry).compile([
      MarkdownRuleDefinition(name: "all"),
    ])
  }

  private func operationTuples(
    _ value: JSONValue
  ) throws -> [(String, String, String)] {
    let root = try #require(value.objectValue)
    let paths = try #require(root["paths"]?.objectValue)
    return try paths.keys.sorted().map { path in
      let operation = try operation(path: path, in: paths)
      return (path, "GET", try #require(operation["operationId"]?.stringValue))
    }
  }

  private func operation(
    path: String,
    in paths: [String: JSONValue]
  ) throws -> [String: JSONValue] {
    let pathItem = try #require(paths[path]?.objectValue)
    return try #require(pathItem["get"]?.objectValue)
  }

  private func responseSchema(in operation: [String: JSONValue]) throws -> JSONValue {
    let responses = try #require(operation["responses"]?.objectValue)
    let success = try #require(responses["200"]?.objectValue)
    let content = try #require(success["content"]?.objectValue)
    let json = try #require(content["application/json"]?.objectValue)
    let schema = try #require(json["schema"])
    if schema.objectValue?["type"]?.stringValue == "array" {
      return try #require(schema.objectValue?["items"])
    }
    return schema
  }

  private func containsReference(_ reference: String, in value: JSONValue) -> Bool {
    switch value {
    case .array(let values):
      return values.contains { containsReference(reference, in: $0) }
    case .object(let object):
      return object["$ref"]?.stringValue == reference
        || object.values.contains { containsReference(reference, in: $0) }
    default:
      return false
    }
  }
}

private struct TupleValue: Equatable {
  let path: String
  let method: String
  let operationID: String

  init(_ value: (String, String, String)) {
    path = value.0
    method = value.1
    operationID = value.2
  }
}
