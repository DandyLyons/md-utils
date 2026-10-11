import Foundation
import JSONSchema
import MarkdownUtilitiesCore
import Parsing

/// Applies creation-only defaults as additive proposals, then validates the effective input.
/// Branches propose against the same input so conflicting defaults cannot win by ordering.
public enum TemplateInputDefaults {
  public static func prepare(_ input: JSONValue, schema: JSONValue?) throws -> JSONValue {
    guard input.objectValue != nil else {
      throw MarkdownTemplateError(stage: .input, message: "Expected a JSON object of Knap variables; place arrays or scalars under a named property.")
    }
    guard let schema else { return input }
    var engine = Expansion(root: schema)
    let unconditional = try engine.expand(input, schema: schema, path: "$", location: "#", depth: 0, conditional: false) ?? input
    let result = try engine.expand(unconditional, schema: schema, path: "$", location: "#", depth: 0) ?? unconditional
    let validation = try validate(result, schema: schema)
    guard validation.valid else {
      throw MarkdownTemplateError(stage: .schema, message: (validation.errors ?? []).map {
        "\($0.instanceLocation.path): \($0.description)"
      }.joined(separator: "\n"))
    }
    return result
  }

  static func validate(_ input: JSONValue, schema: JSONValue) throws -> ValidationResult {
    switch schema {
    case .object(var value):
      // Match mdtype schema compilation instead of the dependency's Draft 4 default;
      // conditionals, const, and prefixItems require a modern dialect.
      if value["$schema"] == nil { value["$schema"] = .string("https://json-schema.org/draft/2020-12/schema") }
      return try JSONSchema.validate(input.foundationValue, schema: value.mapValues(\.foundationValue))
    case .boolean(let value): return try JSONSchema.validate(input.foundationValue, schema: value)
    default: throw MarkdownTemplateError(stage: .schema, message: "Expected an object or boolean schema.")
    }
  }

  private struct Expansion {
    let root: JSONValue
    var work = 0

    mutating func expand(_ input: JSONValue?, schema: JSONValue, path: String, location: String, depth: Int,
      conditional: Bool = true,
    ) throws -> JSONValue? {
      try Task.checkCancellation()
      work += 1
      guard depth < 64, work < 100_000 else {
        throw failure(path, location, "Default expansion exceeded its recursion/work limit")
      }
      guard let object = schema.objectValue else { return input }
      var result = input ?? object["default"]
      if let ref = object["$ref"]?.stringValue {
        result = try merge(result, expand(input, schema: resolve(ref), path: path, location: ref, depth: depth + 1, conditional: conditional),
          path: path, locations: "\(location), \(ref)")
      }
      // An absent object remains absent unless its own schema supplies a default.
      if case .object(var values) = result, let properties = object["properties"]?.objectValue {
        for key in properties.keys.sorted() {
          guard let child = properties[key] else { continue }
          values[key] = try expand(values[key], schema: child, path: path + "." + key,
            location: location + "/properties/" + key, depth: depth + 1, conditional: conditional)
        }
        result = .object(values)
      }
      if case .array(var values) = result {
        let prefix: [JSONValue]
        if case .array(let schemas) = object["prefixItems"] { prefix = schemas } else { prefix = [] }
        for index in values.indices {
          if let child = index < prefix.count ? prefix[index] : object["items"] {
            values[index] = try expand(values[index], schema: child, path: "\(path)[\(index)]",
              location: location + "/items/\(index)", depth: depth + 1, conditional: conditional) ?? values[index]
          }
        }
        result = .array(values)
      }
      if case .array(let branches) = object["allOf"] {
        var proposed = result
        for (index, branch) in branches.enumerated() {
          let value = try expand(input, schema: branch, path: path,
            location: "\(location)/allOf/\(index)", depth: depth + 1, conditional: conditional)
          let locations = ([location] + (0...index).map { "\(location)/allOf/\($0)" }).joined(separator: ", ")
          proposed = try merge(proposed, value, path: path, locations: locations)
        }
        result = proposed
      }
      if conditional, let resultValue = result {
        if let condition = object["if"] {
          let key = try matches(resultValue, condition) ? "then" : "else"
          if let branch = object[key] {
            result = try expand(resultValue, schema: branch, path: path, location: location + "/" + key, depth: depth + 1)
          }
        }
        for key in ["oneOf", "anyOf"] {
          guard case .array(let branches) = object[key] else { continue }
          let applicable = try branches.enumerated().filter { try matches(resultValue, $0.element) }
          var proposals: [JSONValue?] = []
          for branch in applicable {
            proposals.append(try expand(result, schema: branch.element, path: path,
              location: "\(location)/\(key)/\(branch.offset)", depth: depth + 1))
          }
          if let first = proposals.first {
            guard proposals.allSatisfy({ $0 == first }) else {
              throw failure(path, location + "/" + key, "Ambiguous alternatives for default insertion")
            }
            result = first
          }
        }
      }
      return result
    }

    func matches(_ value: JSONValue, _ schema: JSONValue) throws -> Bool {
      // Keep root definitions visible to references in branch schemas.
      var branch = schema.objectValue
      if branch != nil {
        if branch?["$schema"] == nil { branch?["$schema"] = root.objectValue?["$schema"] }
        if branch?["$defs"] == nil { branch?["$defs"] = root.objectValue?["$defs"] }
        if branch?["definitions"] == nil { branch?["definitions"] = root.objectValue?["definitions"] }
      }
      return try TemplateInputDefaults.validate(value, schema: branch.map(JSONValue.object) ?? schema).valid
    }

    func resolve(_ reference: String) throws -> JSONValue {
      if reference == "#" { return root }
      let parser = Parse(input: Substring.self) {
        "#/"
        Many { Prefix { $0 != "/" } } separator: { "/" }
        End()
      }
      guard let tokens = try? parser.parse(reference[...]) else {
        throw failure("$", reference, "Default expansion requires a local JSON Pointer reference")
      }
      var value = root
      for token in tokens {
        let key = String(token).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        if let next = value.objectValue?[key] { value = next }
        else if case .array(let values) = value,
          let index = try? Int.parser().parse(key), values.indices.contains(index) { value = values[index] }
        else { throw failure("$", reference, "Unresolved schema reference") }
      }
      return value
    }

    func merge(_ left: JSONValue?, _ right: JSONValue?, path: String, locations: String) throws -> JSONValue? {
      guard let left else { return right }
      guard let right else { return left }
      if left == right { return left }
      if case .object(var values) = left, case .object(let others) = right {
        for key in others.keys.sorted() {
          values[key] = try merge(values[key], others[key], path: path + "." + key, locations: locations)
        }
        return .object(values)
      }
      if case .array(let values) = left, case .array(let others) = right, values.count == others.count {
        return .array(try values.indices.map { index in
          try merge(values[index], others[index], path: "\(path)[\(index)]", locations: locations) ?? values[index]
        })
      }
      throw failure(path, locations, "Conflicting defaults")
    }

    func failure(_ path: String, _ location: String, _ message: String) -> MarkdownTemplateError {
      MarkdownTemplateError(stage: .schema, message: "\(path) [\(location)]: \(message)")
    }
  }
}
