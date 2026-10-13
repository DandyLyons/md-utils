import Foundation
import Parsing

/// Stable reasons for failure of a declared semantic string profile.
public enum MarkdownSemanticScalarError: String, Error, LocalizedError, Sendable {
  case nativeKind = "native-kind"
  case syntax
  case trailingInput = "trailing-input"
  case calendarRange = "calendar-range"
  case precision
  case uuidLayout = "uuid-layout"

  public var errorDescription: String? {
    switch self {
    case .nativeKind: "Expected a stored string; quote native temporal values"
    case .syntax: "Value does not match the complete declared textual profile"
    case .trailingInput: "Unexpected trailing input after the scalar"
    case .calendarRange: "Invalid calendar or time component; leap seconds and 24:00:00 are unsupported"
    case .precision: "Fractional seconds require 1–9 ASCII digits"
    case .uuidLayout: "Unsupported UUID version or variant bits"
    }
  }
}

/// A typed view of an authored scalar; parsing never replaces stored text.
public struct MarkdownSemanticScalar: Sendable {
  public enum Value: Sendable {
    case date(DateComponents)
    case localTime(DateComponents)
    case dateTime(Date, components: DateComponents, offsetSeconds: Int, unknownOffset: Bool)
    case uuid(UUID)
    case wikilink(Wikilink)
  }

  public let source: String
  public let format: String
  public let value: Value

  public static let formats = [
    "Date": "ISO8601",
    "LocalTime": "ISO8601",
    "DateTime": "RFC3339",
    "UUID": "RFC9562",
    "Wikilink": "Obsidian",
  ]

  /// Creates a v4 UUID explicitly, without allocating document identity.
  public static func generateUUID() -> UUID { UUID() }

  public static func parse(_ source: String, format: String) throws -> Self {
    let parts = format.split(separator: "/", omittingEmptySubsequences: false)
    guard let subject = parts.first.map(String.init), let raw = formats[subject],
      parts.count == 1 || (parts.count == 2 && parts[1] == raw)
    else { throw MarkdownSemanticScalarError.syntax }
    let value: Value
    switch subject {
    case "Wikilink": value = .wikilink(try Wikilink.parse(source, context: .standard))
    case "UUID":
      var input = source[...]
      do {
        for (index, length) in [8, 4, 4, 4, 12].enumerated() {
          if index > 0 { try "-".parse(&input) }
          _ = try Prefix<Substring>(length) { $0.isASCII && $0.isHexDigit }.parse(&input)
        }
      } catch { throw MarkdownSemanticScalarError.syntax }
      guard input.isEmpty else { throw MarkdownSemanticScalarError.trailingInput }
      guard let uuid = UUID(uuidString: source) else { throw MarkdownSemanticScalarError.syntax }
      let text = source.lowercased()
      let bytes = Array(text.utf8)
      let special = text == "00000000-0000-0000-0000-000000000000"
        || text == "ffffffff-ffff-ffff-ffff-ffffffffffff"
      guard special || (Array("1345678".utf8).contains(bytes[14])
        && Array("89ab".utf8).contains(bytes[19]))
      else { throw MarkdownSemanticScalarError.uuidLayout }
      value = .uuid(uuid)
    default:
      value = try parseTemporal(source, subject: subject)
    }
    return Self(source: source, format: "\(subject)/\(raw)", value: value)
  }

  private static func parseTemporal(_ source: String, subject: String) throws -> Value {
    var input = source[...]
    var components = DateComponents()
    do {
      if subject != "LocalTime" {
        components.year = try digits(4, input: &input)
        try "-".parse(&input)
        components.month = try digits(2, input: &input)
        try "-".parse(&input)
        components.day = try digits(2, input: &input)
        guard let year = components.year, let month = components.month, let day = components.day,
          (1...9999).contains(year), (1...12).contains(month)
        else { throw MarkdownSemanticScalarError.calendarRange }
        let leap = year.isMultiple(of: 4) && (year.isMultiple(of: 100) == false || year.isMultiple(of: 400))
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[month - 1]).contains(day) else { throw MarkdownSemanticScalarError.calendarRange }
      }
      if subject == "Date" {
        guard input.isEmpty else { throw MarkdownSemanticScalarError.trailingInput }
        _ = try Date.ISO8601FormatStyle().parse(source + "T00:00:00Z")
        return .date(components)
      }
      if subject == "DateTime" {
        _ = try Prefix<Substring>(1) { $0 == "T" || $0 == "t" }.parse(&input)
      }
      components.hour = try digits(2, input: &input)
      try ":".parse(&input)
      components.minute = try digits(2, input: &input)
      try ":".parse(&input)
      components.second = try digits(2, input: &input)
      guard let hour = components.hour, let minute = components.minute, let second = components.second,
        (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
      else { throw MarkdownSemanticScalarError.calendarRange }
      if input.first == "." {
        try ".".parse(&input)
        let fraction = try Prefix<Substring> { $0.isASCII && $0.isNumber }.parse(&input)
        guard (1...9).contains(fraction.count), let number = Int(fraction) else {
          throw MarkdownSemanticScalarError.precision
        }
        components.nanosecond = number * (0..<(9 - fraction.count)).reduce(1) { result, _ in result * 10 }
      }
      if subject == "LocalTime" {
        guard input.isEmpty else { throw MarkdownSemanticScalarError.trailingInput }
        _ = try Date.ISO8601FormatStyle(includingFractionalSeconds: components.nanosecond != nil)
          .parse("2000-01-01T" + source + "Z")
        return .localTime(components)
      }
      let offsetText = String(input)
      let offset: Int
      if input.first == "Z" || input.first == "z" {
        input.removeFirst()
        offset = 0
      } else {
        let sign = try Prefix<Substring>(1) { $0 == "+" || $0 == "-" }.parse(&input)
        let hours = try digits(2, input: &input)
        try ":".parse(&input)
        let minutes = try digits(2, input: &input)
        guard hours <= 23, minutes <= 59 else { throw MarkdownSemanticScalarError.calendarRange }
        offset = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
      }
      guard input.isEmpty else { throw MarkdownSemanticScalarError.trailingInput }
      // Foundation supplies the instant after exact profile checks. ISO parsing uses
      // a proleptic Gregorian calendar and avoids Calendar's historical cutover.
      let style = Date.ISO8601FormatStyle(includingFractionalSeconds: components.nanosecond != nil)
      let localUTC = String(source.dropLast(offsetText.count)).uppercased() + "Z"
      let instant = try style.parse(localUTC).addingTimeInterval(-Double(offset))
      return .dateTime(instant, components: components, offsetSeconds: offset, unknownOffset: offsetText == "-00:00")
    } catch let error as MarkdownSemanticScalarError {
      throw error
    } catch {
      throw MarkdownSemanticScalarError.syntax
    }
  }

  private static func digits(_ count: Int, input: inout Substring) throws -> Int {
    let text = try Prefix<Substring>(count) { $0.isASCII && $0.isNumber }.parse(&input)
    guard let value = Int(text) else { throw MarkdownSemanticScalarError.syntax }
    return value
  }
}
