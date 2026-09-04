import Foundation
@testable import MarkdownUtilitiesCore
import Testing

@Suite("fm-var YAML projection")
struct FMVarYAMLProjectorTests {
  @Test
  func `language-neutral Core Schema fixtures retain scalar content`() throws {
    let fixtureURL = try #require(
      Bundle.module.url(forResource: "FMVar", withExtension: nil)?
        .appendingPathComponent("yaml-projection-cases.json")
    )
    let fixture = try JSONDecoder().decode(
      YAMLProjectionFixture.self,
      from: Data(contentsOf: fixtureURL)
    )
    #expect(fixture.version == "1.0.0")

    for testCase in fixture.cases {
      let result = FMVarYAMLProjector().project(yaml: testCase.yaml)
      let root = try #require(result.argument?.root, Comment(rawValue: testCase.name))
      #expect(kind(of: root.value) == testCase.kind, Comment(rawValue: testCase.name))
      #expect(root.sourceScalar?.content == testCase.source, Comment(rawValue: testCase.name))
    }
  }

  @Test
  func `Core Schema excludes legacy timestamp Boolean merge and numeric behavior`() throws {
    let projection = FMVarYAMLProjector().project(yaml: """
      date: 2001-12-15
      yes: yes
      no: NO
      on: On
      off: off
      trueValue: TRUE
      falseValue: false
      <<: ordinary
      octal: 0o17
      leadingZero: 012
      sexagesimal: 12:34:56
      """)
    let members = try objectMembers(from: projection)

    #expect(members["date"]?.value == .string("2001-12-15"))
    #expect(members["yes"]?.value == .string("yes"))
    #expect(members["no"]?.value == .string("NO"))
    #expect(members["on"]?.value == .string("On"))
    #expect(members["off"]?.value == .string("off"))
    #expect(members["trueValue"]?.value == .boolean(true))
    #expect(members["falseValue"]?.value == .boolean(false))
    #expect(members["<<"]?.value == .string("ordinary"))
    #expect(members["octal"]?.value == .integer(15))
    #expect(members["leadingZero"]?.value == .integer(12))
    #expect(members["sexagesimal"]?.value == .string("12:34:56"))
  }

  @Test
  func `standalone YAML accepts every portable root shape`() throws {
    let scalar = FMVarYAMLProjector().project(yaml: "hello")
    let sequence = FMVarYAMLProjector().project(yaml: "[null, false, 3]")
    let mapping = FMVarYAMLProjector().project(yaml: "{name: value}")
    let null = FMVarYAMLProjector().project(yaml: "null")

    #expect(scalar.argument?.root.value == .string("hello"))
    #expect(kind(of: try #require(sequence.argument?.root.value)) == "array")
    #expect(kind(of: try #require(mapping.argument?.root.value)) == "object")
    #expect(null.argument?.root.value == .null)
  }

  @Test
  func `Markdown projection requires a mapping root`() {
    let result = FMVarYAMLProjector().project(yaml: "[one, two]", rootRequirement: .mapping)
    #expect(result.status == .invalid)
    #expect(result.failure?.reason == .markdownRootNotMapping)
    #expect(result.failure?.nodeID?.rawValue == "$")
    #expect(result.failure?.position?.line == 1)
  }

  @Test
  func `projected IDs are deterministic JSON locations and evaluator preserves duplicates`() throws {
    let result = FMVarYAMLProjector().project(yaml: """
      unusual.key:
        - &item 1.2300
        - *item
      """)
    let argument = try #require(result.argument)
    let selection = FMVarJSONPathEvaluator().evaluate(
      query: "$['unusual.key'][1,0,1]",
      argument: argument
    )
    let nodes = try #require(selection.nodelist?.nodes)

    #expect(nodes.map(\.id.rawValue) == [
      "$['unusual.key'][1]", "$['unusual.key'][0]", "$['unusual.key'][1]",
    ])
    #expect(nodes.map(\.sourceScalar?.content) == ["1.2300", "1.2300", "1.2300"])
  }

  @Test
  func `inclusive numeric limits and explicit Core tags are accepted`() throws {
    let projection = FMVarYAMLProjector().project(yaml: """
      minimum: !!int -9007199254740991
      maximum: !!int 9007199254740991
      decimal: !!float 1e+03
      text: !!str true
      """)
    let members = try objectMembers(from: projection)

    #expect(members["minimum"]?.value == .integer(-9_007_199_254_740_991))
    #expect(members["maximum"]?.value == .integer(9_007_199_254_740_991))
    #expect(members["decimal"]?.value == .number(1_000))
    #expect(members["decimal"]?.sourceScalar?.content == "1e+03")
    #expect(members["text"]?.value == .string("true"))
  }

  @Test
  func `nested failures carry JSON location and Yams source position`() throws {
    let result = FMVarYAMLProjector().project(yaml: "outer:\n  value: !!int 1_2")
    let failure = try #require(result.failure)

    #expect(failure.reason == .invalidScalar)
    #expect(failure.nodeID?.rawValue == "$['outer']['value']")
    #expect(failure.position?.line == 2)
    #expect(failure.position?.column == 10)
  }

  @Test(arguments: [
    ("duplicate", "a: 1\na: 2", FMVarQueryArgumentFailureReason.duplicateMappingKey),
    ("non-string key", "1: value", .nonStringMappingKey),
    ("custom tag", "!custom value", .unsupportedTag),
    ("invalid explicit integer", "!!int 1_2", .invalidScalar),
    ("invalid explicit float", "!!float 1_2.3", .invalidScalar),
    ("undefined alias", "value: *missing", .invalidAlias),
    ("self-referential alias", "value: &value [*value]", .invalidAlias),
    ("non-finite infinity", ".inf", .nonFiniteFloat),
    ("non-finite NaN", ".NaN", .nonFiniteFloat),
    ("large positive integer", "9007199254740992", .integerOutOfRange),
    ("large negative integer", "-9007199254740992", .integerOutOfRange),
    ("float overflow", "1e9999", .floatingPointOverflow),
    ("multi-document stream", "one\n---\ntwo", .malformedYAML),
    ("malformed syntax", "[one", .malformedYAML),
  ])
  func `invalid YAML and nonportable values have structured failures`(
    name: String,
    yaml: String,
    expected: FMVarQueryArgumentFailureReason
  ) {
    let result = FMVarYAMLProjector().project(yaml: yaml)
    #expect(result.status == .invalid, Comment(rawValue: name))
    #expect(result.failure?.reason == expected, Comment(rawValue: name))
    #expect(result.failure?.diagnosticCode == diagnosticCode(for: expected), Comment(rawValue: name))
  }

  @Test
  func `empty standalone stream is rejected`() {
    let result = FMVarYAMLProjector().project(yaml: "")
    #expect(result.failure?.reason == .emptyDocument)
  }

  private func objectMembers(from projection: FMVarYAMLProjection) throws -> [String: FMVarQueryNode] {
    let root = try #require(projection.argument?.root)
    guard case .object(let members) = root.value else {
      Issue.record("Expected a projected object")
      return [:]
    }
    return Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0.node) })
  }

  private func kind(of value: FMVarQueryValue) -> String {
    switch value {
    case .null: "null"
    case .boolean: "boolean"
    case .integer: "integer"
    case .number: "number"
    case .string: "string"
    case .array: "array"
    case .object: "object"
    }
  }

  private func diagnosticCode(
    for reason: FMVarQueryArgumentFailureReason
  ) -> FMVarDiagnosticCode {
    switch reason {
    case .malformedYAML: .malformedYAML
    case .emptyDocument: .emptyYAMLDocument
    case .duplicateMappingKey: .duplicateYAMLKey
    case .nonStringMappingKey: .nonStringYAMLKey
    case .invalidAlias: .invalidYAMLAlias
    case .unsupportedTag: .unsupportedYAMLTag
    case .invalidScalar: .invalidYAMLScalar
    case .nonFiniteFloat: .nonFiniteYAMLFloat
    case .integerOutOfRange: .yamlIntegerOutOfRange
    case .floatingPointOverflow: .yamlFloatOverflow
    case .markdownRootNotMapping: .invalidYAMLFrontmatterRoot
    }
  }
}

private struct YAMLProjectionFixture: Decodable {
  let version: String
  let cases: [YAMLProjectionCase]
}

private struct YAMLProjectionCase: Decodable {
  let name: String
  let yaml: String
  let kind: String
  let source: String
}
