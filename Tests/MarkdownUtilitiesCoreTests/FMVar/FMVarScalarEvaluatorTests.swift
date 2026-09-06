import Foundation
import MarkdownUtilitiesCore
import Testing

@Suite("fm-var scalar evaluation")
struct FMVarScalarEvaluatorTests {
  @Test
  func `language neutral fixtures evaluate atomic scalar caches`() throws {
    let url = try #require(Bundle.module.url(forResource: "FMVar", withExtension: nil)?
      .appendingPathComponent("scalar-evaluation-cases.json"))
    let fixture = try JSONDecoder().decode(ScalarEvaluationFixture.self, from: Data(contentsOf: url))
    #expect(fixture.version == "1.0.0")
    for item in fixture.cases {
      let snapshot = try FMVarParser().parse(item.markdown)
      let source = item.sourceFailure.map {
        FMVarSourceResolution(status: .failed, reference: nil, failure: $0)
      } ?? resolution(yaml: item.yaml)
      let evaluator = FMVarScalarEvaluator(
        queryEvaluator: FMVarJSONPathEvaluator(limits: item.limits ?? FMVarJSONPathLimits(),
          availableFunctions: Set(item.availableFunctions ?? FMVarJSONPathFunction.allCases)),
        formatter: item.failFormatter == true ? TestFormatter(output: nil) : FMVarDefaultScalarFormatter()
      )
      let result = evaluator.evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
      let context = Comment(rawValue: item.name)
      #expect(result.status == item.status, context)
      #expect(result.expectedCache?.utf8.map { $0 } == item.expected?.utf8.map { $0 }, context)
      #expect(result.selectedNodeCount == item.count, context)
      #expect(Set(item.codes).isSubset(of: Set(result.diagnostics.map { $0.code.rawValue })), context)
      #expect(result.diagnostics == result.diagnostics.sorted(), context)
      // Determinism is relative to the same ordered query result: RFC 9535 object
      // enumeration can legitimately differ between independent evaluations.
      #expect(result == evaluator.evaluate(snapshot, elementOrdinal: 0,
        sourceResolution: source, queryEvaluation: result.queryEvaluation), context)
      let encoded = try JSONEncoder().encode(result)
      #expect(try JSONDecoder().decode(FMVarScalarEvaluation.self, from: encoded) == result, context)
      if let expected = item.expected {
        let cache = try #require(result.cachedText, context)
        let fresh = cache.utf8.elementsEqual(expected.utf8)
        #expect(result.isFresh == fresh, context)
        #expect((result.edit == nil) == fresh, context)
        let updated = try snapshot.replacingCache(ofElementOrdinal: 0, with: expected)
        let reparsed = try FMVarParser().parse(updated)
        #expect(reparsed.isValid, context)
        let second = evaluator.evaluate(reparsed, elementOrdinal: 0, sourceResolution: source)
        #expect(second.isFresh == true, context)
        #expect(second.edit == nil, context)
      } else {
        #expect(result.edit == nil, context)
        #expect(result.isFresh == nil, context)
        #expect(result.diagnostics.contains { $0.severity == .error }, context)
      }
    }
  }

  @Test
  func `every source failure is retained and prevents injected query fallback`() throws {
    let snapshot = try FMVarParser().parse("<fm-var query=\"$.v\" default-zero=\"fallback\">old</fm-var>")
    for reason in FMVarSourceFailureReason.allCases {
      let failure = FMVarSourceFailure(reason: reason, code: .sourceNotFound, message: "Source failed")
      let source = FMVarSourceResolution(status: .failed, reference: nil, failure: failure)
      let result = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 0, sourceResolution: source,
        queryEvaluation: FMVarJSONPathEvaluation(status: .selected, nodelist: FMVarNodelist(nodes: [])))
      #expect(result.sourceResolution.failure == failure)
      #expect(result.queryEvaluation == nil)
      #expect(result.expectedCache == nil)
      #expect(result.edit == nil)
      #expect(result.diagnostics.contains { $0.code == failure.code })
    }
  }

  @Test
  func `query capability and resource failures cannot use fallbacks`() throws {
    let snapshot = try FMVarParser().parse("<fm-var query=\"$.v[?length(@) > 0]\" default-zero=\"fallback\">old</fm-var>")
    let source = resolution(yaml: "v: [text]")
    let unsupported = FMVarScalarEvaluator(queryEvaluator: FMVarJSONPathEvaluator(availableFunctions: []))
      .evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
    let limited = FMVarScalarEvaluator(queryEvaluator: FMVarJSONPathEvaluator(
      limits: FMVarJSONPathLimits(maximumQueryLength: 1)))
      .evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
    #expect(unsupported.status == .unsupportedQuery)
    #expect(limited.status == .queryResourceLimited)
    for result in [unsupported, limited] {
      #expect(result.edit == nil)
      #expect(result.expectedCache == nil)
      #expect(result.queryEvaluation?.failure != nil)
      let diagnostic = try #require(result.diagnostics.first)
      let range = try #require(diagnostic.range)
      #expect(try snapshot.text(in: range) == "$.v[?length(@) > 0]")
    }
  }

  @Test
  func `injected nodelist preserves identity duplicates and ignores later failures`() throws {
    let snapshot = try FMVarParser().parse("<fm-var query=\"$.v\">old</fm-var>")
    let node = FMVarQueryNode(id: .init(rawValue: "first"), value: .string("good"), sourceScalar: .init(content: "good"))
    let other = FMVarQueryNode(id: .init(rawValue: "second"), value: .object([]))
    let nodes = [node, other, node]
    let result = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 0,
      sourceResolution: resolution(yaml: "v: good"),
      queryEvaluation: FMVarJSONPathEvaluation(status: .selected, nodelist: .init(nodes: nodes), mayEnumerateObjectMembers: true))
    #expect(result.nodelist?.nodes == nodes)
    #expect(result.selectedNode == node)
    #expect(result.selectedCardinality == .multiple)
    #expect(result.expectedCache == "good")
    #expect(result.diagnostics.contains { $0.code == .objectEnumerationOrder })
  }

  @Test
  func `query ordering metadata is conservative and older results decode`() throws {
    let legacy = Data(#"{"status":"selected","nodelist":{"nodes":[]}}"#.utf8)
    let decoded = try JSONDecoder().decode(FMVarJSONPathEvaluation.self, from: legacy)
    #expect(decoded.mayEnumerateObjectMembers == nil)
    let argument = try #require(FMVarYAMLProjector().project(yaml: "[b, a]").argument)
    let ordered = FMVarJSONPathEvaluator().evaluate(query: "$[*]", argument: argument)
    #expect(ordered.mayEnumerateObjectMembers == false)
    #expect(ordered.nodelist?.nodes.map(\.sourceScalar?.content) == ["b", "a"])
  }

  @Test
  func `formatter output is escaped and formatter errors are atomic`() throws {
    let snapshot = try FMVarParser().parse("<fm-var query=\"$.v\" format=\"custom\" default-zero=\"fallback\">old</fm-var>")
    let source = resolution(yaml: "v: text")
    let escaped = FMVarScalarEvaluator(formatter: TestFormatter(output: "<b>*text*</b>"))
      .evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
    #expect(escaped.expectedCache == "&lt;b&gt;&#42;text&#42;&lt;/b&gt;")
    let security = FMVarScalarEvaluator(formatter: TestFormatter(output: "bad\ntext"))
      .evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
    let failure = FMVarScalarEvaluator(formatter: TestFormatter(output: nil))
      .evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
    #expect(security.diagnostics.contains { $0.code == .unsupportedCharacter })
    #expect(failure.diagnostics.contains { $0.code == .formattingFailed })
    for result in [security, failure] {
      #expect(result.edit == nil)
      #expect(result.expectedCache == nil)
    }
    let fallback = FMVarScalarEvaluator(formatter: TestFormatter(output: nil))
      .evaluate(snapshot, elementOrdinal: 0, sourceResolution: resolution(yaml: "other: 1"))
    #expect(fallback.expectedCache == "fallback")
  }

  @Test
  func `malformed elements and inconsistent inputs never produce edits`() throws {
    let source = resolution(yaml: "v: good")
    for markdown in ["<fm-var query=\"$.v\">", "<fm-var query=\"$.v\" type=\"bogus\">old</fm-var>",
      "<fm-var query=\"$.v\">*unsafe*</fm-var>"] {
      let snapshot = try FMVarParser().parse(markdown)
      let result = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 0, sourceResolution: source)
      #expect(result.status == .invalid)
      #expect(result.edit == nil)
    }
    let snapshot = try FMVarParser().parse("<fm-var query=\"$.v\">old</fm-var>")
    let badSource = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 0,
      sourceResolution: .init(status: .resolved, reference: nil))
    let badQuery = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 0,
      sourceResolution: source, queryEvaluation: .init(status: .selected))
    let unknown = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 100, sourceResolution: source)
    let missingAssociation = FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: 0,
      sourceResolution: source, queryEvaluation: .init(status: .selected,
        nodelist: .init(nodes: [.init(id: .init(rawValue: "$"), value: .string("text"))])))
    for result in [badSource, badQuery, unknown, missingAssociation] {
      #expect(result.status == .invalid)
      #expect(result.expectedCache == nil)
      #expect(result.edit == nil)
    }
    #expect(missingAssociation.diagnostics.contains { $0.code == .missingScalarSourceAssociation })
  }

  @Test(arguments: ["\n", "\r\n"])
  func `mixed references preserve unrelated bytes and isolate failures`(newline: String) throws {
    let markdown = "---\(newline)v: 'new'\(newline)---\(newline)Café  <fm-var query='$.v'>old</fm-var>  " +
      "<fm-var query='$.missing'>keep</fm-var> <fm-var query='$.v' type='bogus'>bad</fm-var>\(newline)"
    let snapshot = try FMVarParser().parse(markdown)
    let source = resolution(yaml: "v: new")
    let results = snapshot.elements.map {
      FMVarScalarEvaluator().evaluate(snapshot, elementOrdinal: $0.ordinal, sourceResolution: source)
    }
    #expect(results.map(\.status) == [.stale, .unresolvedZeroResult, .invalid])
    #expect(results.compactMap(\.edit).count == 1)
    let edit = try #require(results.first?.edit)
    let updated = try snapshot.replacingCache(ofElementOrdinal: edit.elementOrdinal, with: edit.replacement)
    #expect(Array(updated.utf8) == Array(markdown.replacingOccurrences(of: ">old<", with: ">new<").utf8))
  }

  private func resolution(yaml: String) -> FMVarSourceResolution {
    let projection = FMVarYAMLProjector().project(yaml: yaml)
    if let argument = projection.argument {
      return .init(status: .resolved, reference: nil, queryArgument: argument)
    }
    return .init(status: .failed, reference: nil, failure: .init(reason: .invalidQueryArgument,
      code: projection.failure?.diagnosticCode ?? .invalidQueryArgument,
      queryArgumentFailure: projection.failure, message: "Projection failed"))
  }
}

private struct ScalarEvaluationFixture: Decodable {
  let version: String
  let cases: [ScalarEvaluationCase]
}

private struct ScalarEvaluationCase: Decodable {
  let name: String
  let yaml: String
  let markdown: String
  let status: FMVarReferenceStatus
  let expected: String?
  let codes: [String]
  let count: Int?
  let sourceFailure: FMVarSourceFailure?
  let limits: FMVarJSONPathLimits?
  let availableFunctions: [FMVarJSONPathFunction]?
  let failFormatter: Bool?
}

private struct TestFormatter: FMVarScalarFormatter {
  let output: String?
  func format(_ scalar: FMVarCoercedScalar, declaration: FMVarScalarDeclaration)
    throws(FMVarScalarFormattingFailure) -> String {
    guard let output else { throw .init(message: "Formatter failed") }
    return output
  }
}
