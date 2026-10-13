import Foundation

/// Specializes format assertions to the finite set of strings in this assessment.
/// An enum at the original schema node is equivalent to the format predicate for
/// every value the engine can visit (including propertyNames). The engine retains
/// ownership of references, applicators, and branch success; this is not a
/// post-validation property walk. Neither stored values nor exported schemas change.
enum SemanticSchemaAdapter {
  static let maps: Set<String> = ["properties", "patternProperties", "$defs", "definitions", "dependentSchemas"]
  static let singles: Set<String> = ["items", "additionalProperties", "propertyNames", "contains", "not", "if", "then", "else"]
  static let arrays: Set<String> = ["allOf", "anyOf", "oneOf"]

  static func check(_ schema: JSONValue) throws {
    _ = try transform(schema) { object, path in
      if let dialect = object["$schema"]?.stringValue,
        dialect != "https://json-schema.org/draft/2020-12/schema" {
        throw configuration("capability", path + "/$schema", "Only Draft 2020-12 is supported by the v2 adapter")
      }
      for keyword in ["$dynamicRef", "$recursiveRef", "unevaluatedProperties", "unevaluatedItems", "prefixItems", "minContains", "maxContains", "dependencies", "additionalItems"] where object[keyword] != nil {
        throw configuration("capability", path + "/" + escape(keyword), "Unsupported schema keyword \(keyword)")
      }
      func isSchema(_ value: JSONValue) -> Bool {
        if case .boolean = value { return true }
        return value.objectValue != nil
      }
      for (key, value) in object {
        if singles.contains(key), isSchema(value) == false {
          throw configuration("declaration", path + "/" + key, "Expected an object or boolean schema")
        }
        if maps.contains(key) {
          guard let children = value.objectValue, children.values.allSatisfy(isSchema) else {
            throw configuration("declaration", path + "/" + key, "Expected a map of schemas")
          }
        }
        if arrays.contains(key) {
          guard case .array(let children) = value, children.isEmpty == false, children.allSatisfy(isSchema) else {
            throw configuration("declaration", path + "/" + key, "Expected a nonempty array of schemas")
          }
        }
      }
      if let declaration = object["format"] {
        guard let name = declaration.stringValue else {
          throw configuration("declaration", path + "/format", "format must be a string")
        }
        if isSemantic(name) {
          guard object["type"] == .string("string") else {
            throw configuration("declaration", path + "/format", "Semantic formats require sibling type: string")
          }
          let parts = name.split(separator: "/", omittingEmptySubsequences: false)
          guard let subject = parts.first.map(String.init), let raw = MarkdownSemanticScalar.formats[subject],
            parts.count == 1 || (parts.count == 2 && parts[1] == raw)
          else { throw configuration("unsupported", path + "/format", "Unsupported semantic format \(name)") }
        }
      }
      return object
    }
  }

  static func specialize(_ schema: JSONValue, instance: JSONValue) throws -> JSONValue {
    var strings: Set<String> = []
    func collect(_ value: JSONValue) {
      switch value {
      case .string(let text): strings.insert(text)
      case .array(let values): values.forEach(collect)
      case .object(let values):
        strings.formUnion(values.keys)
        values.values.forEach(collect)
      default: break
      }
    }
    collect(instance)
    var accepted: [String: [JSONValue]] = [:]
    return try transform(schema) { original, _ in
      var object = original
      if let format = object["format"]?.stringValue, isSemantic(format) {
        if accepted[format] == nil {
          accepted[format] = strings.sorted().filter { (try? MarkdownSemanticScalar.parse($0, format: format)) != nil }.map(JSONValue.string)
        }
        var values = accepted[format] ?? []
        if case .array(let existing)? = object["enum"] { values = values.filter(existing.contains) }
        object["enum"] = .array(values)
        object.removeValue(forKey: "format")
      }
      return object
    }
  }

  static func isSemantic(_ name: String) -> Bool {
    name.contains("/") || name.utf8.first.map { (65...90).contains($0) } == true
  }

  static func escape(_ key: String) -> String {
    key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
  }

  private static func configuration(_ code: String, _ path: String, _ message: String) -> MarkdownTypeDefinitionError {
    .invalidField("type.format.\(code) at \(path): \(message)")
  }

  static func transform(
    _ schema: JSONValue,
    path: String = "#",
    visit: ([String: JSONValue], String) throws -> [String: JSONValue],
  ) throws -> JSONValue {
    guard case .object(var object) = schema else { return schema }
    for (key, value) in object {
      let childPath = path + "/" + escape(key)
      if maps.contains(key), case .object(let children) = value {
        var result: [String: JSONValue] = [:]
        for (name, child) in children {
          result[name] = try transform(child, path: childPath + "/" + escape(name), visit: visit)
        }
        object[key] = .object(result)
      } else if singles.contains(key) {
        object[key] = try transform(value, path: childPath, visit: visit)
      } else if arrays.contains(key), case .array(let children) = value {
        object[key] = .array(try children.enumerated().map {
          try transform($0.element, path: childPath + "/\($0.offset)", visit: visit)
        })
      }
    }
    return .object(try visit(object, path))
  }
}
