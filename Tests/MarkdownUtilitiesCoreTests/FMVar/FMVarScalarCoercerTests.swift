import Foundation
@testable import MarkdownUtilitiesCore
import Testing

@Suite("fm-var scalar coercion")
struct FMVarScalarCoercerTests {
  @Test
  func `language-neutral fixtures coerce projected and selected YAML scalars`() throws {
    let fixtureURL = try #require(
      Bundle.module.url(forResource: "FMVar", withExtension: nil)?
        .appendingPathComponent("scalar-coercion-cases.json")
    )
    let fixture = try JSONDecoder().decode(
      ScalarCoercionFixture.self,
      from: Data(contentsOf: fixtureURL)
    )
    #expect(fixture.version == "1.0.0")

    for testCase in fixture.cases {
      let projection = FMVarYAMLProjector().project(yaml: testCase.yaml)
      let argument = try #require(projection.argument, Comment(rawValue: testCase.name))
      let selection = FMVarJSONPathEvaluator().evaluate(
        query: testCase.query,
        argument: argument
      )
      let node = try #require(selection.nodelist?.nodes.first, Comment(rawValue: testCase.name))
      let result = FMVarScalarCoercer().coerce(node, as: testCase.type)

      #expect(result.failure == nil, Comment(rawValue: testCase.name))
      #expect(
        result.scalar?.defaultSerialization == testCase.output,
        Comment(rawValue: testCase.name)
      )
    }
  }

  @Test
  func `coercion uses retained content rather than projected YAML type`() {
    let booleanNode = scalarNode(content: "false", value: .string("false"))
    let integerNode = scalarNode(content: "+0012", value: .string("+0012"))
    let stringNode = scalarNode(content: "TRUE", value: .boolean(true))

    #expect(FMVarScalarCoercer().coerce(booleanNode, as: .boolean).scalar?.value == .boolean(false))
    #expect(FMVarScalarCoercer().coerce(integerNode, as: .integer).scalar?.value == .integer(12))
    #expect(FMVarScalarCoercer().coerce(stringNode, as: .string).scalar?.value == .string("TRUE"))
  }

  @Test
  func `Boolean coercion accepts only true and false without surrounding whitespace`() {
    for content in ["true", "TRUE", "TrUe", "false", "FALSE", "FaLsE"] {
      #expect(
        FMVarScalarCoercer().coerce(scalarNode(content: content), as: .boolean).scalar != nil,
        Comment(rawValue: content)
      )
    }
    for content in ["", "yes", "no", "1", "0", " true", "false "] {
      #expect(
        FMVarScalarCoercer().coerce(scalarNode(content: content), as: .boolean).failure?.reason == .typeParsing,
        Comment(rawValue: content)
      )
    }
  }

  @Test
  func `integer coercion enforces decimal grammar and interoperable range`() {
    let valid = ["-9007199254740991", "0", "+9007199254740991"]
    let invalid = ["", " 1", "1 ", "0x10", "0o10", "1_000", "9007199254740992", "-9007199254740992"]

    for content in valid {
      #expect(FMVarScalarCoercer().coerce(scalarNode(content: content), as: .integer).scalar != nil)
    }
    for content in invalid {
      let result = FMVarScalarCoercer().coerce(scalarNode(content: content), as: .integer)
      #expect(result.failure?.reason == .typeParsing, Comment(rawValue: content))
    }
  }

  @Test
  func `number coercion preserves decimal spelling and rejects unsupported forms`() {
    let valid = ["0", "-0", "+.5", "1.", "01.2300", "1e-9", "-1.2E+03"]
    let invalid = ["", ".", "1_000", "0x10", "0o10", ".inf", "-.Inf", ".nan", "1e9999"]

    for content in valid {
      let result = FMVarScalarCoercer().coerce(scalarNode(content: content), as: .number)
      #expect(result.scalar?.defaultSerialization == content, Comment(rawValue: content))
    }
    for content in invalid {
      let result = FMVarScalarCoercer().coerce(scalarNode(content: content), as: .number)
      #expect(result.failure?.reason == .typeParsing, Comment(rawValue: content))
    }
  }

  @Test
  func `temporal coercion validates RFC 3339 type boundaries and calendar dates`() {
    let invalidDates = ["2023-02-29", "2024-02-30", "2024-00-01", "2024-13-01", "2024-01-00"]
    for content in invalidDates {
      #expect(
        FMVarScalarCoercer().coerce(scalarNode(content: content), as: .date).failure?.reason == .typeParsing,
        Comment(rawValue: content)
      )
    }

    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2000-02-29"),
      as: .date
    ).scalar?.value == .date(FMVarDateValue(year: 2000, month: 2, day: 29)))
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "1900-02-29"),
      as: .date
    ).failure?.reason == .typeParsing)

    let invalidTimes = [
      "2024-01-01 01:02:03", "2024-01-01T24:00:00", "2024-01-01T23:60:00",
      "2024-01-01T23:59:61", "2024-01-01T01:02", "2024-01-01T01:02:03.",
    ]
    for content in invalidTimes {
      #expect(
        FMVarScalarCoercer().coerce(scalarNode(content: content), as: .datetime).failure?.reason == .typeParsing,
        Comment(rawValue: content)
      )
    }
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T23:59:60"),
      as: .datetime
    ).scalar != nil)
  }

  @Test
  func `timestamp requires and retains a valid RFC 3339 offset`() throws {
    let utc = try #require(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01t01:02:03z"),
      as: .timestamp
    ).scalar)
    let unknownOffset = try #require(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T01:02:03-00:00"),
      as: .timestamp
    ).scalar)

    #expect(utc.defaultSerialization == "2024-01-01T01:02:03Z")
    #expect(unknownOffset.defaultSerialization == "2024-01-01T01:02:03-00:00")
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T01:02:03"),
      as: .timestamp
    ).failure?.reason == .typeParsing)
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T01:02:03+24:00"),
      as: .timestamp
    ).failure?.reason == .typeParsing)
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T01:02:03+23:59"),
      as: .timestamp
    ).scalar != nil)
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T01:02:03+01:60"),
      as: .timestamp
    ).failure?.reason == .typeParsing)
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-01-01T01:02:03Z"),
      as: .datetime
    ).failure?.reason == .typeParsing)

    guard case .timestamp(let timestamp) = unknownOffset.value else {
      Issue.record("Expected a timestamp value")
      return
    }
    #expect(timestamp.offset == .numeric(sign: .minus, hour: 0, minute: 0))
  }

  @Test
  func `missing associations and non-scalar shapes have stable failures`() throws {
    let missing = FMVarQueryNode(id: FMVarQueryNodeID(rawValue: "$"), value: .string("value"))
    let sequence = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$"),
      value: .array([]),
      sourceScalar: FMVarSourceScalar(content: "[]")
    )
    let missingResult = FMVarScalarCoercer().coerce(missing, as: .string)
    let shapeResult = FMVarScalarCoercer().coerce(sequence, as: .string)

    #expect(missingResult.failure?.reason == .missingSourceAssociation)
    #expect(missingResult.failure?.diagnosticCode == .missingScalarSourceAssociation)
    #expect(shapeResult.failure?.reason == .unsupportedValueShape)
    #expect(shapeResult.failure?.diagnosticCode == .wrongValueShape)
    try expectRoundTrip(try #require(missingResult.failure))
    try expectRoundTrip(try #require(shapeResult.failure))
  }

  @Test
  func `unsupported XML characters and embedded line breaks fail before parsing`() {
    let invalid = ["line\nfeed", "carriage\rreturn", "null\u{0000}", "control\u{0008}", "noncharacter\u{FFFE}"]
    for content in invalid {
      let result = FMVarScalarCoercer().coerce(scalarNode(content: content), as: .string)
      #expect(result.failure?.reason == .unsupportedCharacter, Comment(rawValue: content))
      #expect(result.failure?.diagnosticCode == .unsupportedCharacter)
    }

    let valid = "tab\tCafé 😀"
    #expect(FMVarScalarCoercer().coerce(
      scalarNode(content: valid),
      as: .string
    ).scalar?.defaultSerialization == valid)
  }

  @Test
  func `aliases and duplicate JSONPath selections retain number spelling`() throws {
    let projection = FMVarYAMLProjector().project(yaml: "values: [&number 1.2300, *number]")
    let argument = try #require(projection.argument)
    let selection = FMVarJSONPathEvaluator().evaluate(
      query: "$.values[1,0,1]",
      argument: argument
    )
    let nodes = try #require(selection.nodelist?.nodes)

    #expect(nodes.count == 3)
    #expect(nodes.map { FMVarScalarCoercer().coerce($0, as: .number).scalar?.defaultSerialization } == [
      "1.2300", "1.2300", "1.2300",
    ])
  }

  @Test
  func `coercion values and results use stable tagged Codable shapes`() throws {
    let result = FMVarScalarCoercer().coerce(
      scalarNode(content: "2024-02-29T01:02:03.40+05:30"),
      as: .timestamp
    )
    let scalar = try #require(result.scalar)

    try expectRoundTrip(scalar.value)
    try expectRoundTrip(scalar)
    try expectRoundTrip(result)
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(scalar)) as? [String: Any]
    )
    #expect(object["source-content"] as? String == "2024-02-29T01:02:03.40+05:30")
    #expect(object["default-serialization"] as? String == "2024-02-29T01:02:03.40+05:30")
  }

  @Test
  func `every scalar value case round trips through Codable`() throws {
    let date = FMVarDateValue(year: 2024, month: 2, day: 29)
    let time = FMVarTimeValue(hour: 23, minute: 59, second: 60, fractionalSecondDigits: "1200")
    let values: [FMVarScalarValue] = [
      .string(""),
      .boolean(false),
      .integer(0),
      .number(-0.0),
      .date(date),
      .datetime(FMVarDateTimeValue(date: date, time: time)),
      .timestamp(FMVarTimestampValue(date: date, time: time, offset: .utc)),
      .timestamp(FMVarTimestampValue(
        date: date,
        time: time,
        offset: .numeric(sign: .minus, hour: 0, minute: 0)
      )),
    ]

    for value in values {
      try expectRoundTrip(value)
    }
  }

  private func scalarNode(
    content: String,
    value: FMVarQueryValue? = nil
  ) -> FMVarQueryNode {
    FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$['value']"),
      value: value ?? .string(content),
      sourceScalar: FMVarSourceScalar(content: content)
    )
  }

  private func expectRoundTrip<Value>(_ value: Value) throws
  where Value: Codable & Equatable {
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(Value.self, from: data) == value)
  }
}

private struct ScalarCoercionFixture: Decodable {
  let version: String
  let cases: [ScalarCoercionCase]
}

private struct ScalarCoercionCase: Decodable {
  let name: String
  let yaml: String
  let query: String
  let type: FMVarValueType
  let output: String
}
