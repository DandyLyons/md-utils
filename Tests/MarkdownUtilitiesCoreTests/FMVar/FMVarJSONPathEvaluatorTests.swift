import Foundation
@testable import MarkdownUtilitiesCore
import Testing

@Suite("fm-var JSONPath evaluation")
struct FMVarJSONPathEvaluatorTests {
  @Test
  func `language-neutral selector fixtures preserve result order and duplicates`() throws {
    let fixtureURL = try #require(
      Bundle.module.url(forResource: "FMVar", withExtension: nil)?
        .appendingPathComponent("jsonpath-cases.json")
    )
    let fixture = try JSONDecoder().decode(
      JSONPathFixture.self,
      from: Data(contentsOf: fixtureURL)
    )
    #expect(fixture.version == "1.0.0")

    let argument = bookstoreArgument()
    for testCase in fixture.cases {
      let result = FMVarJSONPathEvaluator().evaluate(query: testCase.query, argument: argument)
      #expect(result.status == .selected, Comment(rawValue: testCase.name))
      #expect(
        result.nodelist?.nodes.map(\.id.rawValue) == testCase.expectedNodeIDs,
        Comment(rawValue: testCase.name)
      )
      #expect(result.failure == nil, Comment(rawValue: testCase.name))
    }
  }

  @Test
  func `selected nodes retain source scalar associations`() throws {
    let result = FMVarJSONPathEvaluator().evaluate(
      query: "$.store.book[2,0,2].title",
      argument: bookstoreArgument()
    )
    let nodes = try #require(result.nodelist?.nodes)

    #expect(nodes.map(\.id.rawValue) == [
      "$['store']['book'][2]['title']",
      "$['store']['book'][0]['title']",
      "$['store']['book'][2]['title']",
    ])
    #expect(nodes.map(\.sourceScalar?.content) == [
      "\"Moby Dick\"",
      "\"Sayings of the Century\"",
      "\"Moby Dick\"",
    ])
  }

  @Test(arguments: [
    ("length", "$[?length(@.name) == 5].name", ["$[0]['name']"]),
    ("count", "$[?count(@.tags[*]) == 2].name", ["$[0]['name']"]),
    ("match", "$[?match(@.name, 'Alpha')].name", ["$[0]['name']"]),
    ("search", "$[?search(@.name, 'ph')].name", ["$[0]['name']"]),
    ("value", "$[?value(@.score) == 2].name", ["$[1]['name']"]),
  ])
  func `standard function extensions use DynamicJSON behavior`(
    name: String,
    query: String,
    expectedNodeIDs: [String]
  ) {
    let result = evaluatorWithGenerousRegexBudget().evaluate(
      query: query,
      argument: functionArgument()
    )

    #expect(result.status == .selected, Comment(rawValue: name))
    #expect(result.nodelist?.nodes.map(\.id.rawValue) == expectedNodeIDs)
  }

  @Test
  func `function expression type behavior follows DynamicJSON`() {
    let count = FMVarJSONPathEvaluator().evaluate(
      query: "$[?count(1) == 1]",
      argument: functionArgument()
    )
    let length = FMVarJSONPathEvaluator().evaluate(
      query: "$[?length(@.tags[*]) == 2]",
      argument: functionArgument()
    )
    let value = FMVarJSONPathEvaluator().evaluate(
      query: "$[?value(1) == 1]",
      argument: functionArgument()
    )

    #expect(count.status == .invalidQuery)
    #expect(count.failure?.reason == .invalidSemantics)
    #expect(length.status == .invalidQuery)
    #expect([.invalidSyntax, .invalidSemantics].contains(length.failure?.reason))
    #expect(value.status == .selected)
    #expect(value.nodelist?.cardinality == .zero)
  }

  @Test
  func `runtime JSON type mismatches and invalid regex follow DynamicJSON`() {
    let matchTypeMismatch = evaluatorWithGenerousRegexBudget().evaluate(
      query: "$[?match(@.score, '2')].name",
      argument: functionArgument()
    )
    let searchTypeMismatch = evaluatorWithGenerousRegexBudget().evaluate(
      query: "$[?search(@.name, 2)].name",
      argument: functionArgument()
    )
    let invalidRegex = evaluatorWithGenerousRegexBudget().evaluate(
      query: "$[?search(@.name, '[')].name",
      argument: functionArgument()
    )

    #expect(matchTypeMismatch.status == .selected)
    #expect(matchTypeMismatch.nodelist?.cardinality == .zero)
    #expect(searchTypeMismatch.status == .selected)
    #expect(searchTypeMismatch.nodelist?.cardinality == .zero)
    #expect(invalidRegex.status == .invalidQuery)
    #expect(invalidRegex.failure?.reason == .invalidSemantics)
  }

  @Test
  func `DynamicJSON strict-mode behavior is not locally reinterpreted`() {
    let arithmetic = FMVarJSONPathEvaluator().evaluate(
      query: "$[?@.score + 1 == 2].name",
      argument: functionArgument()
    )
    let dependencyVariable = FMVarJSONPathEvaluator().evaluate(
      query: "$[?@.score < pi].name",
      argument: functionArgument()
    )

    #expect(arithmetic.status == .selected)
    #expect(arithmetic.nodelist?.nodes.map(\.id.rawValue) == ["$[0]['name']"])
    #expect(dependencyVariable.status == .selected)
    #expect(dependencyVariable.nodelist?.nodes.map(\.id.rawValue) == [
      "$[0]['name']", "$[1]['name']",
    ])
  }

  @Test
  func `unknown and configured unavailable functions are unsupported capabilities`() {
    let unknown = FMVarJSONPathEvaluator().evaluate(
      query: "$[?custom(@.name)]",
      argument: functionArgument()
    )
    let unavailable = FMVarJSONPathEvaluator(
      availableFunctions: [.count, .match, .search, .value]
    ).evaluate(
      query: "$[?length(@.name) == 5]",
      argument: functionArgument()
    )

    #expect(unknown.status == .unsupportedCapability)
    #expect(unknown.failure?.reason == .unsupportedFunction)
    #expect(unknown.failure?.functionName == "custom")
    #expect(unavailable.status == .unsupportedCapability)
    #expect(unavailable.failure?.functionName == "length")
  }

  @Test
  func `root and DynamicJSON parse failures have typed UTF-8 ranges`() {
    let invalidRoot = FMVarJSONPathEvaluator().evaluate(
      query: "é.title",
      argument: bookstoreArgument()
    )
    let empty = FMVarJSONPathEvaluator().evaluate(
      query: "",
      argument: bookstoreArgument()
    )
    let malformedQuery = "$['métadata'"
    let malformed = FMVarJSONPathEvaluator().evaluate(
      query: malformedQuery,
      argument: bookstoreArgument()
    )

    #expect(invalidRoot.status == .invalidQuery)
    #expect(invalidRoot.failure?.reason == .invalidRoot)
    #expect(invalidRoot.failure?.queryRange.start.utf8Offset == 0)
    #expect(invalidRoot.failure?.queryRange.end.utf8Offset == 2)
    #expect(empty.failure?.reason == .invalidRoot)
    #expect(empty.failure?.queryRange.start.utf8Offset == 0)
    #expect(empty.failure?.queryRange.end.utf8Offset == 0)
    #expect(malformed.status == .invalidQuery)
    #expect(malformed.failure?.reason == .invalidSyntax)
    #expect(malformed.failure?.queryRange.end.utf8Offset == malformedQuery.utf8.count)
  }

  @Test
  func `query length nesting work result and regex limits remain distinct`() {
    let argument = functionArgument()
    let queryLength = FMVarJSONPathEvaluator(
      limits: limits(maximumQueryLength: 0)
    ).evaluate(query: "$", argument: argument)
    let queryNesting = FMVarJSONPathEvaluator(
      limits: limits(maximumNestingDepth: 0)
    ).evaluate(query: "$.name", argument: argument)
    let executionWork = FMVarJSONPathEvaluator(
      limits: limits(maximumExecutionWork: 0)
    ).evaluate(query: "$", argument: argument)
    let resultCount = FMVarJSONPathEvaluator(
      limits: limits(maximumResultCount: 0)
    ).evaluate(query: "$", argument: argument)
    let regexWork = FMVarJSONPathEvaluator(
      limits: limits(maximumRegularExpressionWork: 0)
    ).evaluate(query: "$[?search(@.name, 'a')]", argument: argument)

    #expect(queryLength.failure?.reason == .queryLengthLimit)
    #expect(queryNesting.failure?.reason == .nestingLimit)
    #expect(executionWork.failure?.reason == .executionWorkLimit)
    #expect(resultCount.failure?.reason == .resultCountLimit)
    #expect(regexWork.failure?.reason == .regularExpressionWorkLimit)
    #expect([
      queryLength.status, queryNesting.status, executionWork.status,
      resultCount.status, regexWork.status,
    ].allSatisfy { $0 == .resourceLimited })
  }

  @Test
  func `query argument depth is bounded independently of query depth`() {
    let leaf = scalarNode("$[0]", .string("value"))
    let nested = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$"),
      value: .array([leaf])
    )
    let result = FMVarJSONPathEvaluator(
      limits: limits(maximumNestingDepth: 0)
    ).evaluate(query: "$", argument: FMVarQueryArgument(root: nested))

    #expect(result.status == .resourceLimited)
    #expect(result.failure?.reason == .nestingLimit)
    #expect(result.failure?.observed == 1)
  }

  @Test
  func `all portable value kinds convert through DynamicJSON`() throws {
    let root = objectNode("$", [
      ("null", scalarNode("$['null']", .null)),
      ("boolean", scalarNode("$['boolean']", .boolean(true))),
      ("integer", scalarNode("$['integer']", .integer(42))),
      ("number", scalarNode("$['number']", .number(4.25))),
      ("string", scalarNode("$['string']", .string("text"))),
      ("array", arrayNode("$['array']", [scalarNode("$['array'][0]", .integer(1))])),
      ("object", objectNode("$['object']", [
        ("member", scalarNode("$['object']['member']", .string("value")))
      ])),
    ])
    let result = FMVarJSONPathEvaluator().evaluate(
      query: "$['null','boolean','integer','number','string','array','object']",
      argument: FMVarQueryArgument(root: root)
    )
    let nodes = try #require(result.nodelist?.nodes)

    #expect(nodes.map(\.value.shape) == [
      .null, .scalar, .scalar, .scalar, .scalar, .sequence, .mapping,
    ])
  }

  @Test
  func `evaluation results and limits have stable Codable shapes`() throws {
    let result = FMVarJSONPathEvaluator().evaluate(query: "$.missing", argument: bookstoreArgument())
    let encoded = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(FMVarJSONPathEvaluation.self, from: encoded)
    let limits = FMVarJSONPathLimits()
    let limitsObject = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(limits)) as? [String: Any]
    )

    #expect(decoded == result)
    #expect(decoded.status == .selected)
    #expect(decoded.nodelist?.cardinality == .zero)
    #expect(limitsObject["maximum-query-length"] as? Int == 4_096)
    #expect(FMVarJSONPathFailureReason.allCases.count == 9)
  }

  private func limits(
    maximumQueryLength: UInt = 4_096,
    maximumNestingDepth: UInt = 128,
    maximumExecutionWork: UInt = 1_000_000,
    maximumResultCount: UInt = 10_000,
    maximumRegularExpressionWork: UInt = 1_000_000
  ) -> FMVarJSONPathLimits {
    FMVarJSONPathLimits(
      maximumQueryLength: maximumQueryLength,
      maximumNestingDepth: maximumNestingDepth,
      maximumExecutionWork: maximumExecutionWork,
      maximumResultCount: maximumResultCount,
      maximumRegularExpressionWork: maximumRegularExpressionWork
    )
  }

  private func evaluatorWithGenerousRegexBudget() -> FMVarJSONPathEvaluator {
    FMVarJSONPathEvaluator(limits: limits(maximumRegularExpressionWork: 100_000_000))
  }

  private func functionArgument() -> FMVarQueryArgument {
    let first = objectNode("$[0]", [
      ("name", scalarNode("$[0]['name']", .string("Alpha"))),
      ("score", scalarNode("$[0]['score']", .integer(1))),
      ("tags", arrayNode("$[0]['tags']", [
        scalarNode("$[0]['tags'][0]", .string("one")),
        scalarNode("$[0]['tags'][1]", .string("two")),
      ])),
    ])
    let second = objectNode("$[1]", [
      ("name", scalarNode("$[1]['name']", .string("Beta"))),
      ("score", scalarNode("$[1]['score']", .integer(2))),
      ("tags", arrayNode("$[1]['tags']", [
        scalarNode("$[1]['tags'][0]", .string("one"))
      ])),
    ])
    return FMVarQueryArgument(root: arrayNode("$", [first, second]))
  }

  private func bookstoreArgument() -> FMVarQueryArgument {
    let books = [
      bookNode(index: 0, title: "Sayings of the Century", author: "Nigel Rees", price: 8.95),
      bookNode(index: 1, title: "Sword of Honour", author: "Evelyn Waugh", price: 12.99),
      bookNode(index: 2, title: "Moby Dick", author: "Herman Melville", price: 8.99),
    ]
    let store = objectNode("$['store']", [
      ("book", arrayNode("$['store']['book']", books))
    ])
    let metadata = objectNode("$['métadata']", [
      ("a.b[c]", scalarNode("$['métadata']['a.b[c]']", .string("quoted")))
    ])
    return FMVarQueryArgument(root: objectNode("$", [
      ("store", store),
      ("métadata", metadata),
    ]))
  }

  private func bookNode(
    index: Int,
    title: String,
    author: String,
    price: Double
  ) -> FMVarQueryNode {
    let base = "$['store']['book'][\(index)]"
    return objectNode(base, [
      ("title", scalarNode(
        "\(base)['title']",
        .string(title),
        source: "\"\(title)\""
      )),
      ("author", scalarNode("\(base)['author']", .string(author))),
      ("price", scalarNode("\(base)['price']", .number(price))),
    ])
  }

  private func scalarNode(
    _ id: String,
    _ value: FMVarQueryValue,
    source: String? = nil
  ) -> FMVarQueryNode {
    FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: id),
      value: value,
      sourceScalar: source.map(FMVarSourceScalar.init(content:))
    )
  }

  private func arrayNode(_ id: String, _ nodes: [FMVarQueryNode]) -> FMVarQueryNode {
    FMVarQueryNode(id: FMVarQueryNodeID(rawValue: id), value: .array(nodes))
  }

  private func objectNode(
    _ id: String,
    _ members: [(String, FMVarQueryNode)]
  ) -> FMVarQueryNode {
    FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: id),
      value: .object(members.map { FMVarQueryObjectMember(name: $0.0, node: $0.1) })
    )
  }
}

private struct JSONPathFixture: Decodable {
  let version: String
  let cases: [JSONPathFixtureCase]
}

private struct JSONPathFixtureCase: Decodable {
  let name: String
  let query: String
  let expectedNodeIDs: [String]

  private enum CodingKeys: String, CodingKey {
    case name
    case query
    case expectedNodeIDs = "expected-node-ids"
  }
}
