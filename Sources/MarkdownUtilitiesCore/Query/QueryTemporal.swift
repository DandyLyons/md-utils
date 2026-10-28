import Foundation
import Parsing

/// Calendar and instant comparisons share validated components, never a guessed midnight.
package struct QueryTemporal {
  enum Kind { case date, time, local, offset }
  let kind: Kind
  var components: DateComponents
  var offset: Int?

  static func parse(_ text: String, kind: String? = nil, format: String? = nil) throws -> Self {
    // Native YAML uses its codec's timestamp spelling, not the narrower string
    // format grammar. Normalize components, then reuse semantic validation.
    let text = kind == "yaml-timestamp" ? try YAMLTimestampComponents.canonical(text) : text
    let subject = format?.split(separator: "/").first.map(String.init)
    let scalar: MarkdownSemanticScalar
    if kind == "local-date-time" {
      scalar = try MarkdownSemanticScalar.parse(text + "Z", format: "DateTime")
      guard case .dateTime(_, let components, _, _) = scalar.value else { throw MarkdownSemanticScalarError.syntax }
      return Self(kind: .local, components: components)
    }
    if kind == "offset-date-time" { scalar = try MarkdownSemanticScalar.parse(text, format: "DateTime") }
    else if kind == "yaml-timestamp" || (kind == nil && subject == nil) {
      if let date = try? MarkdownSemanticScalar.parse(text, format: "Date") { scalar = date }
      else if let instant = try? MarkdownSemanticScalar.parse(text, format: "DateTime") { scalar = instant }
      else if kind == nil { return try parse(text, kind: "local-date-time") }
      else { throw MarkdownSemanticScalarError.syntax }
    } else if kind == "local-date" || subject == "Date" { scalar = try MarkdownSemanticScalar.parse(text, format: "Date") }
    else if kind == "local-time" || subject == "LocalTime" { scalar = try MarkdownSemanticScalar.parse(text, format: "LocalTime") }
    else { scalar = try MarkdownSemanticScalar.parse(text, format: subject ?? "DateTime") }
    switch scalar.value {
    case .date(let c): return Self(kind: .date, components: c)
    case .localTime(let c): return Self(kind: .time, components: c)
    case .dateTime(_, let c, let offset, _): return Self(kind: .offset, components: c, offset: offset)
    default: throw MarkdownSemanticScalarError.syntax
    }
  }

  func instant(zone: TimeZone) throws -> (Int64, Int) {
    guard kind == .local || kind == .offset else { throw MarkdownQueryPredicate.Failure.invalid("Value has no instant") }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = kind == .offset ? (TimeZone(secondsFromGMT: offset ?? 0) ?? zone) : zone
    var c = components
    c.nanosecond = 0
    guard let candidate = calendar.date(from: c) else { throw MarkdownQueryPredicate.Failure.invalid("Invalid local datetime") }
    if kind == .local {
      let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
      let actual = calendar.dateComponents(fields, from: candidate)
      guard fields.allSatisfy({ actual.value(for: $0) == c.value(for: $0) }) else { throw MarkdownQueryPredicate.Failure.invalid("Nonexistent local datetime in \(zone.identifier)") }
      // Check both offsets around a transition. Foundation's nextDate can collapse
      // repeated-time policies when matching a full date with nanoseconds.
      let offsets = Set(stride(from: -172_800, through: 172_800, by: 21_600).map {
        zone.secondsFromGMT(for: candidate.addingTimeInterval(Double($0)))
      })
      let wallSeconds = candidate.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: candidate))
      let possible = offsets.filter { offset in
        let instant = Date(timeIntervalSince1970: wallSeconds - Double(offset))
        let actual = calendar.dateComponents(fields, from: instant)
        return fields.allSatisfy { actual.value(for: $0) == c.value(for: $0) }
      }
      guard possible.count == 1 else { throw MarkdownQueryPredicate.Failure.invalid("Ambiguous local datetime in \(zone.identifier)") }
    }
    return (Int64(candidate.timeIntervalSince1970.rounded()), components.nanosecond ?? 0)
  }

  func calendarComponents(zone: TimeZone, written: Bool) throws -> DateComponents {
    guard kind != .time else { throw MarkdownSemanticScalarError.nativeKind }
    if kind != .offset || written { return components }
    let stamp = try instant(zone: zone)
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    return calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: Double(stamp.0)))
  }

  static func compare(_ lhs: Self, _ rhs: Self, zone: TimeZone, written: Bool) throws -> Int? {
    func order<T: Comparable>(_ a: T, _ b: T) -> Int { a == b ? 0 : a < b ? -1 : 1 }
    if rhs.kind == .date {
      guard lhs.kind != .time else { return nil }
      let c = try lhs.calendarComponents(zone: zone, written: written)
      return order([c.year ?? 0, c.month ?? 0, c.day ?? 0].lexicographicKey, [rhs.components.year ?? 0, rhs.components.month ?? 0, rhs.components.day ?? 0].lexicographicKey)
    }
    if lhs.kind == .time || rhs.kind == .time {
      guard lhs.kind == rhs.kind else { return nil }
    } else if lhs.kind == .date { return nil }
    if (lhs.kind == .local && rhs.kind == .local) || lhs.kind == .time {
      let fields: [Calendar.Component] = [.year, .month, .day, .hour, .minute, .second, .nanosecond]
      let a = fields.map { lhs.components.value(for: $0) ?? 0 }
      let b = fields.map { rhs.components.value(for: $0) ?? 0 }
      return a == b ? 0 : a.lexicographicallyPrecedes(b) ? -1 : 1
    }
    let a = try lhs.instant(zone: zone), b = try rhs.instant(zone: zone)
    return a.0 == b.0 ? order(a.1, b.1) : order(a.0, b.0)
  }

  static func samePeriod(_ lhs: Self, _ reference: Self, period: String, zone: TimeZone, written: Bool, monday: Bool) throws -> Bool {
    guard lhs.kind != .time else { return false }
    let a = try lhs.calendarComponents(zone: zone, written: written)
    let b = reference.components
    if period == "same-year" { return a.year == b.year }
    if period == "same-month" { return a.year == b.year && a.month == b.month }
    if period == "same-day" { return a.year == b.year && a.month == b.month && a.day == b.day }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? zone
    calendar.firstWeekday = monday ? 2 : 1
    guard let ad = calendar.date(from: DateComponents(year: a.year, month: a.month, day: a.day)),
      let bd = calendar.date(from: DateComponents(year: b.year, month: b.month, day: b.day)) else { return false }
    return calendar.dateInterval(of: .weekOfYear, for: ad)?.start == calendar.dateInterval(of: .weekOfYear, for: bd)?.start
  }
}

/// Adapts already-tagged YAML timestamp components to the existing precise
/// semantic parser. YAML's absent zone is UTC, as in Yams' Date constructor.
private struct YAMLTimestampComponents: Parser {
  static func canonical(_ source: String) throws -> String {
    var input = source[...]
    return try Self().parse(&input)
  }
  func parse(_ input: inout Substring) throws -> String {
    func digits(_ input: inout Substring, maximum: Int, width: Int) throws -> String {
      let text = try Prefix<Substring>(1...) { $0.isASCII && $0.isNumber }.parse(&input)
      guard text.count <= maximum else { throw MarkdownSemanticScalarError.syntax }
      return String(repeating: "0", count: max(0, width - text.count)) + text
    }
    let year = try digits(&input, maximum: 4, width: 4)
    try "-".parse(&input)
    let month = try digits(&input, maximum: 2, width: 2)
    try "-".parse(&input)
    let day = try digits(&input, maximum: 2, width: 2)
    let date = "\(year)-\(month)-\(day)"
    if input.isEmpty { return date }
    if input.first == "T" || input.first == "t" { input.removeFirst() }
    else { _ = try Prefix<Substring>(1...) { $0 == " " || $0 == "\t" }.parse(&input) }
    let hour = try digits(&input, maximum: 2, width: 2)
    try ":".parse(&input)
    let minute = try digits(&input, maximum: 2, width: 2)
    try ":".parse(&input)
    let second = try digits(&input, maximum: 2, width: 2)
    var fraction = ""
    if input.first == "." {
      input.removeFirst()
      let value = try Prefix<Substring> { $0.isASCII && $0.isNumber }.parse(&input)
      if !value.isEmpty { fraction = "." + value }
    }
    _ = try Prefix<Substring> { $0 == " " || $0 == "\t" }.parse(&input)
    var zone = "Z"
    if input.first == "Z" { input.removeFirst() }
    else if let sign = input.first, sign == "+" || sign == "-" {
      input.removeFirst()
      let hours = try digits(&input, maximum: 2, width: 2)
      var minutes = "00"
      if input.first == ":" { input.removeFirst(); minutes = try digits(&input, maximum: 2, width: 2) }
      zone = "\(sign)\(hours):\(minutes)"
    }
    guard input.isEmpty else { throw MarkdownSemanticScalarError.trailingInput }
    return "\(date)T\(hour):\(minute):\(second)\(fraction)\(zone)"
  }
}

private extension Array where Element == Int {
  var lexicographicKey: Int { reduce(0) { $0 * 100 + $1 } }
}
