import DynamicJSON
import Foundation

/// A validated document-selection plan. Compilation performs no source I/O.
package struct MarkdownQueryPredicate {
  package enum Failure: Error, CustomStringConvertible {
    case invalid(String)
    package var description: String { switch self { case .invalid(let text): text } }
  }
  package let key: String?
  private let path: JSONPath?
  package let operation: String
  package let domain: String
  package let format: String?
  package let all: Bool
  package let caseSensitive: Bool
  package let timezone: TimeZone
  package let written: Bool
  package let monday: Bool
  private let temporalOperand: QueryTemporal?
  private let operand: JSONValue?
  private let lower: (JSONValue, Bool)?
  private let upper: (JSONValue, Bool)?
  /// Whole top-level subtrees needed by a selector; nil means the root is required.
  package var selectedTopLevelKeys: Set<String>? {
    if let key { return [key] }
    if let first = path?.segments.first?.selectors.first, case .member(let key) = first { return [key] }
    return nil
  }

  package init(
    key: String?, jsonPath: String?, operation: String, operand: String?,
    domain: String = "string", format: String? = nil, all: Bool = false,
    caseSensitive: Bool = false, lower: (String, Bool)? = nil, upper: (String, Bool)? = nil,
    timezone: TimeZone = .current, written: Bool = false, monday: Bool = false,
  ) throws {
    guard (key == nil) != (jsonPath == nil) else { throw Failure.invalid("Supply exactly one of --key and --json-path") }
    guard ["string", "boolean", "integer", "number", "null", "array", "object"].contains(domain) else { throw Failure.invalid("Unknown value type: \(domain)") }
    if let format {
      guard domain == "string", let subject = format.split(separator: "/").first,
        let raw = MarkdownSemanticScalar.formats[String(subject)],
        format == String(subject) || format == "\(subject)/\(raw)" else { throw Failure.invalid("Incompatible value type/format") }
    }
    self.key = key
    if let jsonPath {
      guard jsonPath.utf8.count <= 4096 else { throw Failure.invalid("JSONPath exceeds length budget") }
      let parsed = try JSONPath(query: jsonPath, strict: true)
      guard !parsed.isRelative, parsed.segments.count <= 128,
        parsed.segments.allSatisfy({ segment in
          !segment.isDescendant && segment.selectors.count == 1 && segment.selectors.allSatisfy {
            switch $0 { case .member, .index, .wildcard: true; default: false }
          }
        }) else { throw Failure.invalid("Unsupported JSONPath feature; use members, indices, or wildcards") }
      path = parsed
    } else { path = nil }
    self.operation = operation
    self.domain = domain
    self.format = format
    self.all = all
    self.caseSensitive = caseSensitive
    self.timezone = timezone; self.written = written; self.monday = monday
    let temporalOperation = operation.hasPrefix("same-") || ["before", "after"].contains(operation)
    if temporalOperation {
      guard domain == "string", let operand else { throw Failure.invalid("Temporal comparison requires a date/time operand") }
      let reference = try QueryTemporal.parse(operand, format: operation.hasPrefix("same-") ? "Date" : format?.hasPrefix("LocalTime") == true ? "LocalTime" : nil)
      if reference.kind == .local { _ = try reference.instant(zone: timezone) }
      self.temporalOperand = reference
    } else { self.temporalOperand = nil }
    self.operand = try operand.map { try Self.decode($0, domain: domain) }
    self.lower = try lower.map { (try Self.decode($0.0, domain: domain), $0.1) }
    self.upper = try upper.map { (try Self.decode($0.0, domain: domain), $0.1) }
    if operation == "range" {
      let temporal = format.map { ["Date", "LocalTime", "DateTime"].contains(String($0.split(separator: "/")[0])) } ?? false
      guard domain == "integer" || domain == "number" || temporal else { throw Failure.invalid("Bounds require numeric or temporal values") }
      if temporal {
        let low = try lower.map { try QueryTemporal.parse($0.0, format: format) }
        let high = try upper.map { try QueryTemporal.parse($0.0, format: format) }
        if let low, let high {
          guard let order = try QueryTemporal.compare(low, high, zone: timezone, written: written), order < 0 || (order == 0 && lower?.1 == true && upper?.1 == true) else { throw Failure.invalid("Impossible temporal range") }
        }
      }
      if let lo = self.lower, let hi = self.upper {
        if !temporal {
          guard let order = Self.numericOrder(lo.0, hi.0), order < 0 || (order == 0 && lo.1 && hi.1) else { throw Failure.invalid("Impossible range") }
        }
        if domain == "integer", case .integer(let l) = lo.0, case .integer(let h) = hi.0 {
          let min = l.addingReportingOverflow(lo.1 ? 0 : 1)
          let max = h.subtractingReportingOverflow(hi.1 ? 0 : 1)
          guard !min.overflow, !max.overflow, min.partialValue <= max.partialValue else { throw Failure.invalid("Impossible integer range") }
        }
      }
      if domain == "integer" {
        if let lo = self.lower, !lo.1, lo.0 == .integer(Int.max) { throw Failure.invalid("Impossible integer range") }
        if let hi = self.upper, !hi.1, hi.0 == .integer(Int.min) { throw Failure.invalid("Impossible integer range") }
      }
    }
    if domain == "null", operation != "is-null" { throw Failure.invalid("Use --is-null for the null domain") }
    if let format, let operand, !temporalOperation { _ = try MarkdownSemanticScalar.parse(operand, format: format) }
  }

  private static func decode(_ text: String, domain: String) throws -> JSONValue {
    if domain == "string" { return .string(text) }
    if domain == "integer" {
      let digits = text.first == "+" || text.first == "-" ? text.dropFirst() : text[...]
      guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(text) else { throw Failure.invalid("Invalid signed 64-bit integer operand") }
      return .integer(number)
    }
    let value: JSONValue
    do { value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }
    catch { throw Failure.invalid("Invalid \(domain) operand") }
    if domain == "number", text.contains(".") || text.lowercased().contains("e") {
      guard case .integer = value else {
        if case .number(let number) = value, number.isFinite { return value }
        throw Failure.invalid("Invalid finite number operand")
      }
      guard let number = Double(text), number.isFinite else { throw Failure.invalid("Invalid finite number operand") }
      return .number(number)
    }
    switch (domain, value) {
    case ("boolean", .boolean), ("array", .array), ("object", .object): return value
    case ("number", .integer): return value
    case ("number", .number(let n)) where n.isFinite:
      if !text.contains(".") && !text.lowercased().contains("e") { throw Failure.invalid("Integer operand exceeds signed 64-bit range") }
      return value
    default: throw Failure.invalid("Invalid \(domain) operand")
    }
  }

  package func matches(_ observation: MarkdownSurveyObservation) throws -> Bool {
    let nodes: [(JSONValue, String)]
    if let key {
      nodes = observation.frontmatter?[key].map { [($0, "/" + MarkdownSurveyObservation.escape(key))] } ?? []
    } else if let path {
      var locations: [JSONLocation: (JSONValue, String)] = [:]
      func convert(_ value: JSONValue, location: JSONLocation, pointer: String) -> JSON {
        locations[location] = (value, pointer)
        switch value {
        case .null: return .null
        case .boolean(let b): return .boolean(b)
        case .integer(let n): return .integer(Int64(n))
        case .number(let n): return .float(n)
        case .string(let s): return .string(s)
        case .array(let a): return .array(a.enumerated().map { convert($0.element, location: location.select(index: $0.offset), pointer: pointer + "/\($0.offset)") })
        case .object(let o): return .object(o.mapValuesWithQueryKeys { k, v in convert(v, location: location.select(member: k), pointer: pointer + "/" + MarkdownSurveyObservation.escape(k)) })
        }
      }
      let json = convert(.object(observation.frontmatter ?? [:]), location: .root, pointer: "")
      guard locations.count <= 1_000_000 / max(1, path.segments.count + 1) else { throw Failure.invalid("JSONPath execution budget exhausted") }
      nodes = try JSONPathEvaluator(value: json, strict: true).query(path).compactMap { locations[$0.location] }
      guard nodes.count <= 10_000 else { throw Failure.invalid("JSONPath result-node budget exhausted") }
    } else { nodes = [] }
    if operation == "exists" { return !nodes.isEmpty }
    if operation == "missing" { return nodes.isEmpty }
    guard !nodes.isEmpty else { return false }
    var unknown: Error?
    for (value, pointer) in nodes {
      do {
        let match = try evaluate(value, pointer: pointer, observation: observation)
        if all && !match { return false }
        if !all && match { return true }
      } catch { unknown = error }
    }
    if let unknown { throw unknown }
    return all
  }

  private func evaluate(_ value: JSONValue, pointer: String, observation: MarkdownSurveyObservation, member: Bool = false) throws -> Bool {
    if operation == "is-null" { return value == .null }
    if operation == "contains", !member {
      guard case .array(let elements) = value else { return false }
      var unknown: Error?
      for (index, element) in elements.enumerated() {
        // Membership examines immediate elements, not recursively nested arrays.
        guard eligible(element, pointer: pointer + "/\(index)", observation: observation) || format != nil else { continue }
        do {
          if try evaluate(element, pointer: pointer + "/\(index)", observation: observation, member: true) { return true }
        } catch { unknown = error }
      }
      if let unknown { throw unknown }
      return false
    }
    let evidence = observation.valueMetadata?[pointer]
    if evidence?.special != nil { return false }
    if operation == "range", let format, domain == "string" {
      guard case .string(let text) = value,
        let temporal = try? QueryTemporal.parse(evidence?.source ?? text, kind: observation.nativeTemporalKinds[pointer], format: format) else { return false }
      for (bound, isLower) in [(lower, true), (upper, false)] {
        if let bound, case .string(let text) = bound.0 {
          let reference = try QueryTemporal.parse(text, format: format)
          guard let order = try QueryTemporal.compare(temporal, reference, zone: timezone, written: written),
            (isLower ? order > 0 : order < 0) || (order == 0 && bound.1) else { return false }
        }
      }
      return true
    }
    if let temporalOperand {
      guard case .string(let text) = value,
        let temporal = try? QueryTemporal.parse(evidence?.source ?? text, kind: observation.nativeTemporalKinds[pointer], format: format) else { return false }
      if operation.hasPrefix("same-") { return try QueryTemporal.samePeriod(temporal, temporalOperand, period: operation, zone: timezone, written: written, monday: monday) }
      guard let order = try QueryTemporal.compare(temporal, temporalOperand, zone: timezone, written: written) else { return false }
      return operation == "before" ? order < 0 : order > 0
    }
    if let format, case .string(let text) = value, case .string(let operandText) = operand,
      ["Date", "LocalTime", "DateTime"].contains(String(format.split(separator: "/")[0])) {
      guard let left = try? QueryTemporal.parse(evidence?.source ?? text, kind: observation.nativeTemporalKinds[pointer], format: format),
        let right = try? QueryTemporal.parse(operandText, format: format),
        let order = try QueryTemporal.compare(left, right, zone: timezone, written: written) else { return false }
      return operation == "not-equals" ? order != 0 : order == 0
    }
    guard eligible(value, pointer: pointer, observation: observation) else { return false }
    if operation == "range" {
      let lo = lower.map { bound in Self.numericOrder(value, bound.0).map { $0 > 0 || ($0 == 0 && bound.1) } ?? false } ?? true
      let hi = upper.map { bound in Self.numericOrder(value, bound.0).map { $0 < 0 || ($0 == 0 && bound.1) } ?? false } ?? true
      return lo && hi
    }
    guard let operand else { return false }
    let same = equal(value, operand, pointer: pointer, observation: observation)
    return operation == "not-equals" ? !same : same
  }

  private func eligible(_ value: JSONValue, pointer: String, observation: MarkdownSurveyObservation) -> Bool {
    guard observation.valueMetadata?[pointer]?.special == nil else { return false }
    guard observation.nativeTemporalKinds[pointer] == nil else { return false }
    if let format {
      guard case .string(let text) = value else { return false }
      return (try? MarkdownSemanticScalar.parse(text, format: format)) != nil
    }
    switch (domain, value) {
    case ("string", .string), ("boolean", .boolean), ("array", .array), ("object", .object): return true
    case ("integer", .integer), ("number", .integer): return true
    case ("integer", .number(let n)): return Int(exactly: n) != nil
    case ("number", .number(let n)): return n.isFinite
    default: return false
    }
  }

  private func equal(_ lhs: JSONValue, _ rhs: JSONValue, pointer: String = "", observation: MarkdownSurveyObservation? = nil) -> Bool {
    if observation?.nativeTemporalKinds[pointer] != nil || observation?.valueMetadata?[pointer]?.special != nil { return false }
    if let result = Self.numericOrder(lhs, rhs) { return result == 0 }
    switch (lhs, rhs) {
    case (.string(let a), .string(let b)):
      if format?.hasPrefix("UUID") == true { return UUID(uuidString: a) == UUID(uuidString: b) }
      return caseSensitive ? a == b : a.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")) == b.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    case (.array(let a), .array(let b)): return a.count == b.count && a.indices.allSatisfy { equal(a[$0], b[$0], pointer: pointer + "/\($0)", observation: observation) }
    case (.object(let a), .object(let b)): return a.count == b.count && a.allSatisfy { k, v in b[k].map { equal(v, $0, pointer: pointer + "/" + MarkdownSurveyObservation.escape(k), observation: observation) } ?? false }
    default: return lhs == rhs
    }
  }

  /// Mixed comparison never rounds an integer operand through binary64.
  package static func numericOrder(_ lhs: JSONValue, _ rhs: JSONValue) -> Int? {
    func compare(_ a: Int, _ b: Double) -> Int? {
      guard b.isFinite else { return nil }
      if let integer = Int(exactly: b) { return a == integer ? 0 : a < integer ? -1 : 1 }
      if b >= Double(Int.max) { return -1 }
      if b < Double(Int.min) { return 1 }
      let truncated = Int(b)
      if a == truncated { return b > 0 ? -1 : 1 }
      return a < truncated ? -1 : 1
    }
    switch (lhs, rhs) {
    case (.integer(let a), .integer(let b)): return a == b ? 0 : a < b ? -1 : 1
    case (.number(let a), .number(let b)) where a.isFinite && b.isFinite: return a == b ? 0 : a < b ? -1 : 1
    case (.integer(let a), .number(let b)): return compare(a, b)
    case (.number(let a), .integer(let b)): return compare(b, a).map { -$0 }
    default: return nil
    }
  }
}

private extension Dictionary where Key == String, Value == JSONValue {
  func mapValuesWithQueryKeys(_ transform: (String, JSONValue) -> JSON) -> [String: JSON] {
    Dictionary<String, JSON>(uniqueKeysWithValues: map { ($0.key, transform($0.key, $0.value)) })
  }
}
