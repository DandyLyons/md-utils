import Foundation
import Parsing

/// Calendar date components parsed from an RFC 3339 `full-date`.
public struct FMVarDateValue: Codable, Equatable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }
}

/// Local time components parsed from an RFC 3339 `partial-time`.
public struct FMVarTimeValue: Codable, Equatable, Sendable {
  public let hour: Int
  public let minute: Int
  public let second: Int
  /// Fractional-second digits without the leading decimal point.
  public let fractionalSecondDigits: String?

  public init(
    hour: Int,
    minute: Int,
    second: Int,
    fractionalSecondDigits: String? = nil
  ) {
    self.hour = hour
    self.minute = minute
    self.second = second
    self.fractionalSecondDigits = fractionalSecondDigits
  }

  private enum CodingKeys: String, CodingKey {
    case hour
    case minute
    case second
    case fractionalSecondDigits = "fractional-second-digits"
  }
}

/// Sign of an RFC 3339 numeric UTC offset.
public enum FMVarUTCOffsetSign: String, Codable, Equatable, Sendable {
  case plus = "+"
  case minus = "-"
}

/// UTC designation retained from an RFC 3339 timestamp.
public enum FMVarUTCOffset: Codable, Equatable, Sendable {
  /// The timestamp used the `Z` UTC designator.
  case utc
  /// The timestamp used a signed numeric offset, including `+00:00` or RFC 3339's `-00:00`.
  case numeric(sign: FMVarUTCOffsetSign, hour: Int, minute: Int)

  private enum CodingKeys: String, CodingKey {
    case kind
    case sign
    case hour
    case minute
  }

  private enum Kind: String, Codable {
    case utc
    case numeric
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .utc:
      self = .utc
    case .numeric:
      self = .numeric(
        sign: try container.decode(FMVarUTCOffsetSign.self, forKey: .sign),
        hour: try container.decode(Int.self, forKey: .hour),
        minute: try container.decode(Int.self, forKey: .minute)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .utc:
      try container.encode(Kind.utc, forKey: .kind)
    case .numeric(let sign, let hour, let minute):
      try container.encode(Kind.numeric, forKey: .kind)
      try container.encode(sign, forKey: .sign)
      try container.encode(hour, forKey: .hour)
      try container.encode(minute, forKey: .minute)
    }
  }
}

/// An RFC 3339 local date-time without a UTC offset.
public struct FMVarDateTimeValue: Codable, Equatable, Sendable {
  public let date: FMVarDateValue
  public let time: FMVarTimeValue

  public init(date: FMVarDateValue, time: FMVarTimeValue) {
    self.date = date
    self.time = time
  }
}

/// An RFC 3339 date-time with a UTC designation or numeric offset.
public struct FMVarTimestampValue: Codable, Equatable, Sendable {
  public let date: FMVarDateValue
  public let time: FMVarTimeValue
  public let offset: FMVarUTCOffset

  public init(date: FMVarDateValue, time: FMVarTimeValue, offset: FMVarUTCOffset) {
    self.date = date
    self.time = time
    self.offset = offset
  }
}

/// A scalar interpreted according to an fm-var `type` or `item-type` declaration.
public enum FMVarScalarValue: Codable, Equatable, Sendable {
  case string(String)
  case boolean(Bool)
  case integer(Int64)
  case number(Double)
  case date(FMVarDateValue)
  case datetime(FMVarDateTimeValue)
  case timestamp(FMVarTimestampValue)

  private enum CodingKeys: String, CodingKey {
    case kind
    case value
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(FMVarValueType.self, forKey: .kind) {
    case .string: self = .string(try container.decode(String.self, forKey: .value))
    case .boolean: self = .boolean(try container.decode(Bool.self, forKey: .value))
    case .integer: self = .integer(try container.decode(Int64.self, forKey: .value))
    case .number: self = .number(try container.decode(Double.self, forKey: .value))
    case .date: self = .date(try container.decode(FMVarDateValue.self, forKey: .value))
    case .datetime:
      self = .datetime(try container.decode(FMVarDateTimeValue.self, forKey: .value))
    case .timestamp:
      self = .timestamp(try container.decode(FMVarTimestampValue.self, forKey: .value))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .string(let value):
      try container.encode(FMVarValueType.string, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .boolean(let value):
      try container.encode(FMVarValueType.boolean, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .integer(let value):
      try container.encode(FMVarValueType.integer, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .number(let value):
      try container.encode(FMVarValueType.number, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .date(let value):
      try container.encode(FMVarValueType.date, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .datetime(let value):
      try container.encode(FMVarValueType.datetime, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .timestamp(let value):
      try container.encode(FMVarValueType.timestamp, forKey: .kind)
      try container.encode(value, forKey: .value)
    }
  }
}

/// Successfully coerced scalar plus the source spelling used to produce its default output.
public struct FMVarCoercedScalar: Codable, Equatable, Sendable {
  public let value: FMVarScalarValue
  public let sourceContent: String
  public let defaultSerialization: String

  public init(value: FMVarScalarValue, sourceContent: String, defaultSerialization: String) {
    self.value = value
    self.sourceContent = sourceContent
    self.defaultSerialization = defaultSerialization
  }

  private enum CodingKeys: String, CodingKey {
    case value
    case sourceContent = "source-content"
    case defaultSerialization = "default-serialization"
  }
}

/// Stable reason that an identified query node could not be coerced.
public enum FMVarScalarCoercionFailureReason: String, Codable, Equatable, Sendable, CaseIterable {
  case missingSourceAssociation = "missing-source-association"
  case typeParsing = "type-parsing"
  case unsupportedValueShape = "unsupported-value-shape"
  case unsupportedCharacter = "unsupported-character"
}

/// Structured scalar-coercion failure suitable for later element-level diagnostics.
public struct FMVarScalarCoercionFailure: Codable, Equatable, Sendable {
  public let reason: FMVarScalarCoercionFailureReason
  public let nodeID: FMVarQueryNodeID
  public let requestedType: FMVarValueType
  public let message: String

  public init(
    reason: FMVarScalarCoercionFailureReason,
    nodeID: FMVarQueryNodeID,
    requestedType: FMVarValueType,
    message: String
  ) {
    self.reason = reason
    self.nodeID = nodeID
    self.requestedType = requestedType
    self.message = message
  }

  public var diagnosticCode: FMVarDiagnosticCode {
    switch reason {
    case .missingSourceAssociation: .missingScalarSourceAssociation
    case .typeParsing: .coercionFailed
    case .unsupportedValueShape: .wrongValueShape
    case .unsupportedCharacter: .unsupportedCharacter
    }
  }

  private enum CodingKeys: String, CodingKey {
    case reason
    case nodeID = "node-id"
    case requestedType = "requested-type"
    case message
  }
}

/// Outcome of coercing one selected query node.
public struct FMVarScalarCoercionResult: Codable, Equatable, Sendable {
  public let scalar: FMVarCoercedScalar?
  public let failure: FMVarScalarCoercionFailure?

  public init(
    scalar: FMVarCoercedScalar? = nil,
    failure: FMVarScalarCoercionFailure? = nil
  ) {
    self.scalar = scalar
    self.failure = failure
  }
}

/// Coerces selected YAML scalar content and produces its locale-independent default serialization.
public struct FMVarScalarCoercer: Sendable {
  public init() {}

  public func coerce(
    _ node: FMVarQueryNode,
    as requestedType: FMVarValueType
  ) -> FMVarScalarCoercionResult {
    guard node.value.shape == .scalar else {
      return failed(
        .unsupportedValueShape,
        node: node,
        type: requestedType,
        message: "The selected node is not a renderable scalar."
      )
    }
    guard let sourceContent = node.sourceScalar?.content else {
      return failed(
        .missingSourceAssociation,
        node: node,
        type: requestedType,
        message: "The selected scalar has no retained YAML source association."
      )
    }
    guard Self.isSupportedText(sourceContent) else {
      return failed(
        .unsupportedCharacter,
        node: node,
        type: requestedType,
        message: "The selected scalar contains a line break or character unsupported by XML 1.0."
      )
    }

    var input = sourceContent[...]
    do {
      let parsed = try FMVarScalarLexicalParser(type: requestedType).parse(&input)
      guard input.isEmpty else { throw FMVarScalarParsingError.invalidLexicalForm }
      return FMVarScalarCoercionResult(scalar: FMVarCoercedScalar(
        value: parsed.value,
        sourceContent: sourceContent,
        defaultSerialization: parsed.defaultSerialization
      ))
    } catch {
      return failed(
        .typeParsing,
        node: node,
        type: requestedType,
        message: "The selected scalar is not valid as \(requestedType.rawValue)."
      )
    }
  }

  private func failed(
    _ reason: FMVarScalarCoercionFailureReason,
    node: FMVarQueryNode,
    type: FMVarValueType,
    message: String
  ) -> FMVarScalarCoercionResult {
    FMVarScalarCoercionResult(failure: FMVarScalarCoercionFailure(
      reason: reason,
      nodeID: node.id,
      requestedType: type,
      message: message
    ))
  }

  private static func isSupportedText(_ value: String) -> Bool {
    value.unicodeScalars.allSatisfy { scalar in
      switch scalar.value {
      case 0x09: true
      case 0x20...0xD7FF: true
      case 0xE000...0xFFFD: true
      case 0x10000...0x10FFFF: true
      default: false
      }
    }
  }
}

private struct ParsedScalar {
  let value: FMVarScalarValue
  let defaultSerialization: String
}

private enum FMVarScalarParsingError: Error {
  case invalidLexicalForm
}

private struct FMVarScalarLexicalParser: Parsing.Parser {
  typealias Input = Substring
  typealias Output = ParsedScalar

  let type: FMVarValueType

  func parse(_ input: inout Substring) throws -> ParsedScalar {
    let source = String(input)
    let parsed: ParsedScalar
    switch type {
    case .string:
      parsed = ParsedScalar(value: .string(source), defaultSerialization: source)
    case .boolean:
      parsed = try parseBoolean(source)
    case .integer:
      parsed = try parseInteger(source)
    case .number:
      parsed = try parseNumber(source)
    case .date:
      let components = try parseTemporal(source, type: .date)
      parsed = ParsedScalar(value: .date(components.date), defaultSerialization: source)
    case .datetime:
      let components = try parseTemporal(source, type: .datetime)
      let value = FMVarDateTimeValue(date: components.date, time: components.time)
      parsed = ParsedScalar(value: .datetime(value), defaultSerialization: components.canonical)
    case .timestamp:
      let components = try parseTemporal(source, type: .timestamp)
      guard let offset = components.offset else { throw FMVarScalarParsingError.invalidLexicalForm }
      let value = FMVarTimestampValue(
        date: components.date,
        time: components.time,
        offset: offset
      )
      parsed = ParsedScalar(value: .timestamp(value), defaultSerialization: components.canonical)
    }
    input.removeAll()
    return parsed
  }

  private func parseBoolean(_ source: String) throws -> ParsedScalar {
    switch source.lowercased() {
    case "true": ParsedScalar(value: .boolean(true), defaultSerialization: "TRUE")
    case "false": ParsedScalar(value: .boolean(false), defaultSerialization: "FALSE")
    default: throw FMVarScalarParsingError.invalidLexicalForm
    }
  }

  private func parseInteger(_ source: String) throws -> ParsedScalar {
    guard matches(source, pattern: "^[+-]?[0-9]+$"),
      let value = Int64(source),
      value >= -maximumInteroperableInteger,
      value <= maximumInteroperableInteger
    else {
      throw FMVarScalarParsingError.invalidLexicalForm
    }
    return ParsedScalar(value: .integer(value), defaultSerialization: String(value))
  }

  private func parseNumber(_ source: String) throws -> ParsedScalar {
    let pattern = "^[-+]?(?:\\.[0-9]+|[0-9]+(?:\\.[0-9]*)?)(?:[eE][-+]?[0-9]+)?$"
    guard matches(source, pattern: pattern), let value = parseFiniteDouble(source) else {
      throw FMVarScalarParsingError.invalidLexicalForm
    }
    return ParsedScalar(value: .number(value), defaultSerialization: source)
  }

  private func parseFiniteDouble(_ source: String) -> Double? {
    var normalized = source
    if normalized.hasPrefix(".") {
      normalized = "0" + normalized
    } else if normalized.hasPrefix("+.") {
      normalized = "+0" + normalized.dropFirst()
    } else if normalized.hasPrefix("-.") {
      normalized = "-0" + normalized.dropFirst()
    }
    guard let value = Double(normalized), value.isFinite else { return nil }
    return value
  }

  private func parseTemporal(
    _ source: String,
    type: FMVarValueType
  ) throws -> ParsedTemporal {
    let pattern: String
    switch type {
    case .date:
      pattern = "^([0-9]{4})-([0-9]{2})-([0-9]{2})$"
    case .datetime:
      pattern = "^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.([0-9]+))?$"
    case .timestamp:
      pattern = "^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.([0-9]+))?(?:([Zz])|([+-])([0-9]{2}):([0-9]{2}))$"
    default:
      throw FMVarScalarParsingError.invalidLexicalForm
    }
    guard let captures = captures(source, pattern: pattern),
      let year = integer(captures, at: 1),
      let month = integer(captures, at: 2),
      let day = integer(captures, at: 3)
    else {
      throw FMVarScalarParsingError.invalidLexicalForm
    }
    let date = FMVarDateValue(year: year, month: month, day: day)
    guard isValid(date: date) else { throw FMVarScalarParsingError.invalidLexicalForm }
    if type == .date {
      return ParsedTemporal(
        date: date,
        time: FMVarTimeValue(hour: 0, minute: 0, second: 0),
        offset: nil,
        canonical: source
      )
    }
    guard let hour = integer(captures, at: 4),
      let minute = integer(captures, at: 5),
      let second = integer(captures, at: 6),
      hour <= 23,
      minute <= 59,
      second <= 60
    else {
      throw FMVarScalarParsingError.invalidLexicalForm
    }
    let fraction = captures[safe: 7] ?? nil
    let time = FMVarTimeValue(
      hour: hour,
      minute: minute,
      second: second,
      fractionalSecondDigits: fraction
    )
    let canonicalTime = "\(two(hour)):\(two(minute)):\(two(second))" +
      (fraction.map { ".\($0)" } ?? "")
    if type == .datetime {
      return ParsedTemporal(
        date: date,
        time: time,
        offset: nil,
        canonical: "\(dateText(date))T\(canonicalTime)"
      )
    }
    let offset: FMVarUTCOffset
    let offsetText: String
    if captures[safe: 8] ?? nil != nil {
      offset = .utc
      offsetText = "Z"
    } else {
      guard let signText = captures[safe: 9] ?? nil,
        let sign = FMVarUTCOffsetSign(rawValue: signText),
        let offsetHour = integer(captures, at: 10),
        let offsetMinute = integer(captures, at: 11),
        offsetHour <= 23,
        offsetMinute <= 59
      else {
        throw FMVarScalarParsingError.invalidLexicalForm
      }
      offset = .numeric(sign: sign, hour: offsetHour, minute: offsetMinute)
      offsetText = "\(sign.rawValue)\(two(offsetHour)):\(two(offsetMinute))"
    }
    return ParsedTemporal(
      date: date,
      time: time,
      offset: offset,
      canonical: "\(dateText(date))T\(canonicalTime)\(offsetText)"
    )
  }

  private func captures(_ source: String, pattern: String) -> [String?]? {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
    guard let match = expression.firstMatch(in: source, range: sourceRange),
      match.range == sourceRange
    else {
      return nil
    }
    return (0..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound, let swiftRange = Range(range, in: source) else { return nil }
      return String(source[swiftRange])
    }
  }

  private func integer(_ captures: [String?], at index: Int) -> Int? {
    guard let value = captures[safe: index] ?? nil else { return nil }
    return Int(value)
  }

  private func isValid(date: FMVarDateValue) -> Bool {
    guard (1...12).contains(date.month), date.day >= 1 else { return false }
    let leap = date.year.isMultiple(of: 4) &&
      (!date.year.isMultiple(of: 100) || date.year.isMultiple(of: 400))
    let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return date.day <= days[date.month - 1]
  }

  private func matches(_ source: String, pattern: String) -> Bool {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return expression.firstMatch(in: source, range: range)?.range == range
  }

  private func two(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }

  private func dateText(_ date: FMVarDateValue) -> String {
    let year = String(date.year)
    return String(repeating: "0", count: max(0, 4 - year.count)) + year +
      "-\(two(date.month))-\(two(date.day))"
  }
}

private struct ParsedTemporal {
  let date: FMVarDateValue
  let time: FMVarTimeValue
  let offset: FMVarUTCOffset?
  let canonical: String
}

private let maximumInteroperableInteger: Int64 = 9_007_199_254_740_991

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
