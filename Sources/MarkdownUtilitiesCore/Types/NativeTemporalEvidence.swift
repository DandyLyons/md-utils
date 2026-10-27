import Foundation
import Yams

/// Retains native kinds before the legacy JSON projection converts them to text.
enum NativeTemporalEvidence {
  static func paths(_ value: FrontMatter, source: String, format: FrontMatterFormat) throws -> Set<String> {
    Set(try kinds(value, source: source, format: format).keys)
  }

  static func kinds(_ value: FrontMatter, source: String, format: FrontMatterFormat) throws -> [String: String] {
    var kinds: [String: String] = [:]
    func walk(_ value: FrontMatterValue, path: String) {
      switch value {
      case .offsetDateTime: kinds[path] = "offset-date-time"
      case .localDateTime: kinds[path] = "local-date-time"
      case .localDate: kinds[path] = "local-date"
      case .localTime: kinds[path] = "local-time"
      case .object(let object):
        for (key, child) in object { walk(child, path: path + "/" + SemanticSchemaAdapter.escape(key)) }
      case .array(let values):
        for (index, child) in values.enumerated() { walk(child, path: path + "/\(index)") }
      default: break
      }
    }
    walk(.object(value), path: "")
    // Legacy YAML decoding keeps timestamp scalars as strings. Read tags without
    // changing that behavior for v1 or any other consumer of frontmatter.
    func walkYAML(_ node: Yams.Node, path: String) {
      if let mapping = node.mapping {
        for (key, child) in mapping {
          if let key = key.string { walkYAML(child, path: path + "/" + SemanticSchemaAdapter.escape(key)) }
        }
      } else if let sequence = node.sequence {
        for (index, child) in sequence.enumerated() { walkYAML(child, path: path + "/\(index)") }
      } else if node.tag == Tag(.timestamp) { kinds[path] = "yaml-timestamp" }
    }
    if format == .yaml, let node = try Yams.compose(yaml: source) { walkYAML(node, path: "") }
    return kinds
  }

  static func instance(_ value: JSONValue, paths: Set<String>, path: String = "") -> Any {
    // Foundation Date remains a native non-string value to the schema engine.
    // Its instant is immaterial: semantic string branches reject its kind.
    if paths.contains(path) { return Date(timeIntervalSince1970: 0) }
    switch value {
    case .object(let object):
      return object.mapValuesWithKeys { key, child in
        instance(child, paths: paths, path: path + "/" + SemanticSchemaAdapter.escape(key))
      }
    case .array(let values):
      return values.enumerated().map { instance($0.element, paths: paths, path: path + "/\($0.offset)") }
    default: return value.foundationValue
    }
  }
}

private extension Dictionary where Key == String, Value == JSONValue {
  func mapValuesWithKeys(_ transform: (String, JSONValue) -> Any) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, value) in self { result[key] = transform(key, value) }
    return result
  }
}
