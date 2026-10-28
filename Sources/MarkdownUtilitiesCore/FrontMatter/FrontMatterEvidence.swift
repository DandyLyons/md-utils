import CTomlPlusPlus
import Foundation
import TOML
import Yams

/// Lossless scalar evidence travels with the JSON projection, including authored temporal fields.
package struct FrontMatterEvidence: Codable, Sendable {
  package var kind: String
  package var source: String? = nil
  package var special: String? = nil
}

/// Parse once, preserving information that the legacy Foundation projection erases.
package struct ParsedFrontMatter {
  package var mapping: FrontMatter
  package var metadata: [String: FrontMatterEvidence]

  package static func parse(_ source: String, format: FrontMatterFormat) throws -> Self {
    var metadata: [String: FrontMatterEvidence] = [:]
    let mapping: FrontMatter
    if format == .yaml {
      let node = try YAMLConversion.parse(source)
      mapping = try FrontMatterConversion.fromYAMLMapping(node)
      func walk(_ node: Yams.Node, _ pointer: String) {
        if let object = node.mapping {
          for (key, child) in object { if let key = key.string { walk(child, pointer + "/" + MarkdownSurveyObservation.escape(key)) } }
        } else if let array = node.sequence {
          for (index, child) in array.enumerated() { walk(child, pointer + "/\(index)") }
        } else if node.tag == Tag(.timestamp) { metadata[pointer] = .init(kind: "yaml-timestamp", source: node.scalar?.string) }
      }
      walk(.mapping(node), "")
    } else {
      // swift-toml's C parser retains components/offset before its Date bridge.
      // Consume the same parsed tree directly to avoid a second TOML parse.
      var parsed = source.withCString { ctoml_parse($0, source.utf8.count) }
      defer { ctoml_free_result(&parsed) }
      guard parsed.success else { throw FrontMatterConversionError.invalidTOML(parsed.error_message.map { String(cString: $0) } ?? "Parse failed") }
      func string(_ value: CTomlString) -> String {
        guard let data = value.data else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: data, count: value.length), as: UTF8.self)
      }
      func convert(_ node: CTomlNode, _ pointer: String, _ depth: Int) throws -> FrontMatterValue {
        guard depth < 128 else { throw FrontMatterConversionError.invalidTOML("Maximum nesting depth exceeded") }
        switch node.type {
        case CTOML_STRING: return .string(string(node.data.string_value))
        case CTOML_INTEGER: return .integer(node.data.integer_value)
        case CTOML_FLOAT: return .number(node.data.float_value)
        case CTOML_BOOLEAN: return .boolean(node.data.boolean_value)
        case CTOML_DATE:
          let d = node.data.date_value
          return .localDate(.init(year: Int(d.year), month: Int(d.month), day: Int(d.day)))
        case CTOML_TIME:
          let t = node.data.time_value
          return .localTime(.init(hour: Int(t.hour), minute: Int(t.minute), second: Int(t.second), nanosecond: Int(t.nanosecond)))
        case CTOML_DATETIME:
          let dt = node.data.datetime_value
          let date = String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%09d", dt.date.year, dt.date.month, dt.date.day, dt.time.hour, dt.time.minute, dt.time.second, dt.time.nanosecond)
          if dt.has_offset {
            let minutes = Int(dt.offset_minutes)
            let text = date + String(format: "%@%02d:%02d", minutes < 0 ? "-" : "+", abs(minutes) / 60, abs(minutes) % 60)
            let scalar = try MarkdownSemanticScalar.parse(text, format: "DateTime")
            guard case .dateTime(let instant, _, _, _) = scalar.value else { throw FrontMatterConversionError.invalidTOML("Invalid timestamp") }
            metadata[pointer] = .init(kind: "offset-date-time", source: text)
            return .offsetDateTime(instant)
          }
          return .localDateTime(.init(year: Int(dt.date.year), month: Int(dt.date.month), day: Int(dt.date.day), hour: Int(dt.time.hour), minute: Int(dt.time.minute), second: Int(dt.time.second), nanosecond: Int(dt.time.nanosecond)))
        case CTOML_ARRAY:
          guard node.data.array_value.count <= 1_000_000 else { throw FrontMatterConversionError.invalidTOML("Array budget exceeded") }
          var values: [FrontMatterValue] = []
          if let elements = node.data.array_value.elements {
            for index in 0..<node.data.array_value.count { values.append(try convert(elements[index], pointer + "/\(index)", depth + 1)) }
          }
          return .array(values)
        case CTOML_TABLE:
          guard node.data.table_value.count <= 1_000_000 else { throw FrontMatterConversionError.invalidTOML("Table budget exceeded") }
          var values = FrontMatter()
          if let keys = node.data.table_value.keys, let children = node.data.table_value.values {
            for index in 0..<node.data.table_value.count {
              let key = string(keys[index])
              values[key] = try convert(children[index], pointer + "/" + MarkdownSurveyObservation.escape(key), depth + 1)
            }
          }
          return .object(values)
        default: throw FrontMatterConversionError.invalidTOML("Unsupported node")
        }
      }
      guard case .object(let object) = try convert(parsed.root, "", 0) else { throw FrontMatterConversionError.invalidTOML("Expected table") }
      mapping = object
    }
    func walk(_ value: FrontMatterValue, _ pointer: String) {
      switch value {
      case .integer: metadata[pointer] = .init(kind: "integer")
      case .number(let number): metadata[pointer] = .init(kind: "number", special: number.isFinite ? nil : number.isNaN ? "nan" : number > 0 ? "positive-infinity" : "negative-infinity")
      case .localDate: metadata[pointer] = .init(kind: "local-date", source: FrontMatterConversion.foundationValue(value) as? String)
      case .localTime: metadata[pointer] = .init(kind: "local-time", source: FrontMatterConversion.foundationValue(value) as? String)
      case .localDateTime: metadata[pointer] = .init(kind: "local-date-time", source: FrontMatterConversion.foundationValue(value) as? String)
      case .array(let array): for (index, child) in array.enumerated() { walk(child, pointer + "/\(index)") }
      case .object(let object): for (key, child) in object { walk(child, pointer + "/" + MarkdownSurveyObservation.escape(key)) }
      default: break
      }
    }
    walk(.object(mapping), "")
    return Self(mapping: mapping, metadata: metadata)
  }

  /// Typed projection for assessment; special numbers remain numeric in the runtime.
  package static func project(_ value: FrontMatterValue) -> JSONValue {
    switch value {
    case .null: return .null
    case .boolean(let b): return .boolean(b)
    case .integer(let n): return .integer(Int(n))
    case .number(let n): return .number(n)
    case .string(let s): return .string(s)
    case .array(let array): return .array(array.map(project))
    case .object(let object): return .object(object.dictionary.mapValues(project))
    default: return .string(FrontMatterConversion.foundationValue(value) as? String ?? "")
    }
  }

  /// Reports use valid JSON while preserving special-number identity in metadata.
  package static func jsonSafe(_ value: JSONValue) -> JSONValue {
    switch value {
    case .number(let n) where !n.isFinite: return .string(n.isNaN ? "NaN" : n > 0 ? "Infinity" : "-Infinity")
    case .object(let object): return .object(object.mapValues(jsonSafe))
    case .array(let array): return .array(array.map(jsonSafe))
    default: return value
    }
  }
}
