import Foundation
import JSONSchema

/// Explains failed assertions after the engine has determined branch validity.
/// Successful alternatives never leak their unsuccessful sibling diagnostics.
struct SemanticSchemaDiagnostics {
  let root: JSONValue
  let instance: JSONValue
  let nativePaths: Set<String>
  let severity: MarkdownDiagnosticSeverity
  let constraint: String
  let source: String?

  func explain() throws -> [MarkdownDiagnostic] {
    try explain(root, value: instance, path: "", schemaPath: (root.objectValue?["$id"]?.stringValue ?? "") + "#", depth: 0)
  }

  /// Checks reference capabilities before the engine can encounter a cycle.
  func checkReferences() throws {
    _ = try expanded(root, base: "", depth: 0)
  }

  func valid(_ schema: JSONValue, value: JSONValue, path: String, base: String = "") throws -> Bool {
    let expanded = try expanded(schema, base: base, depth: 0)
    guard case .object(var object) = try SemanticSchemaAdapter.specialize(expanded, instance: .array([instance, value])) else {
      return schema != .boolean(false)
    }
    object["$schema"] = .string("https://json-schema.org/draft/2020-12/schema")
    guard let foundation = JSONValue.object(object).foundationValue as? [String: Any] else { return false }
    return try JSONSchema.validate(NativeTemporalEvidence.instance(value, paths: nativePaths, path: path), schema: foundation).valid
  }

  private func explain(
    _ schema: JSONValue, value: JSONValue, path: String, schemaPath: String, depth: Int, includeShape: Bool = false,
  ) throws -> [MarkdownDiagnostic] {
    let base = String(schemaPath.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
    guard depth < 128, let object = schema.objectValue,
      try valid(schema, value: value, path: path, base: base) == false else { return [] }
    var result: [MarkdownDiagnostic] = []
    if let format = object["format"]?.stringValue, SemanticSchemaAdapter.isSemantic(format) {
      let reason: MarkdownSemanticScalarError?
      if nativePaths.contains(path) || value.stringValue == nil { reason = .nativeKind }
      else if let text = value.stringValue {
        do { _ = try MarkdownSemanticScalar.parse(text, format: format); reason = nil }
        catch let error as MarkdownSemanticScalarError { reason = error }
        catch { reason = .syntax }
      } else { reason = .nativeKind }
      if let reason {
        var diagnostic = MarkdownDiagnostic(
          code: "frontmatter.format.invalid", severity: severity, domain: .frontmatter,
          constraintID: constraint, location: path.isEmpty ? "/" : path,
          message: "Expected \(format): \(reason.localizedDescription)",
        )
        diagnostic.schemaLocation = schemaPath + "/format"
        diagnostic.definitionSource = source
        let subject = String(format.split(separator: "/").first ?? "")
        diagnostic.format = subject + "/" + (MarkdownSemanticScalar.formats[subject] ?? "")
        diagnostic.reason = reason.rawValue
        result.append(diagnostic)
      }
    }
    if let reference = object["$ref"]?.stringValue,
      let resolved = resolve(reference.hasPrefix("#") ? base + reference : reference) {
      result += try explain(resolved, value: value, path: path, schemaPath: reference.hasPrefix("#") ? base + reference : reference, depth: depth + 1)
    }
    if let declaration = object["wikilink"], let text = value.stringValue,
      let link = try? Wikilink.parse(text, context: .standard) {
      for failure in try WikilinkStylePolicy(declaration, path: schemaPath + "/wikilink").failures(link) {
        var diagnostic = MarkdownDiagnostic(
          code: "frontmatter.format.invalid", severity: severity, domain: .frontmatter,
          constraintID: constraint, location: path.isEmpty ? "/" : path, message: failure.message,
        )
        diagnostic.schemaLocation = schemaPath + "/wikilink/" + failure.field
        diagnostic.definitionSource = source
        diagnostic.format = "Wikilink/Obsidian"
        diagnostic.reason = failure.reason
        result.append(diagnostic)
      }
    }
    for keyword in ["allOf", "anyOf", "oneOf"] {
      guard case .array(let branches)? = object[keyword] else { continue }
      var causes: [MarkdownDiagnostic] = []
      for (index, branch) in branches.enumerated() {
        causes += try explain(branch, value: value, path: path, schemaPath: schemaPath + "/\(keyword)/\(index)", depth: depth + 1, includeShape: true)
      }
      if causes.isEmpty == false, try valid(.object([keyword: .array(branches)]), value: value, path: path, base: base) == false {
        var parent = MarkdownDiagnostic(
          code: "frontmatter.schema.invalid", severity: severity, domain: .frontmatter,
          constraintID: constraint, location: path.isEmpty ? "/" : path, message: "Failed \(keyword) schema branches",
        )
        parent.schemaLocation = schemaPath + "/" + keyword
        parent.definitionSource = source
        parent.causes = causes
        result.append(parent)
      }
    }
    if let condition = object["if"] {
      let branch = try valid(condition, value: value, path: path, base: base) ? "then" : "else"
      if let child = object[branch] {
        result += try explain(child, value: value, path: path, schemaPath: schemaPath + "/" + branch, depth: depth + 1)
      }
    }
    if case .object(let values) = value {
      let properties = object["properties"]?.objectValue ?? [:]
      let patterns = object["patternProperties"]?.objectValue ?? [:]
      for (key, child) in values.sorted(by: { $0.key < $1.key }) {
        let childPath = path + "/" + SemanticSchemaAdapter.escape(key)
        if let property = properties[key] {
          result += try explain(property, value: child, path: childPath, schemaPath: schemaPath + "/properties/" + SemanticSchemaAdapter.escape(key), depth: depth + 1)
        }
        var matched = false
        for (pattern, property) in patterns where key.range(of: pattern, options: .regularExpression) != nil {
          matched = true
          result += try explain(property, value: child, path: childPath, schemaPath: schemaPath + "/patternProperties/" + SemanticSchemaAdapter.escape(pattern), depth: depth + 1)
        }
        if properties[key] == nil, matched == false, let additional = object["additionalProperties"] {
          result += try explain(additional, value: child, path: childPath, schemaPath: schemaPath + "/additionalProperties", depth: depth + 1)
        }
        if let names = object["propertyNames"] {
          let namesContext = Self(root: root, instance: instance, nativePaths: [], severity: severity, constraint: constraint, source: source)
          result += try namesContext.explain(names, value: .string(key), path: childPath, schemaPath: schemaPath + "/propertyNames", depth: depth + 1)
        }
      }
      for (key, child) in object["dependentSchemas"]?.objectValue ?? [:] where values[key] != nil {
        result += try explain(child, value: value, path: path, schemaPath: schemaPath + "/dependentSchemas/" + SemanticSchemaAdapter.escape(key), depth: depth + 1)
      }
    }
    if case .array(let values) = value, let items = object["items"] {
      for (index, child) in values.enumerated() {
        result += try explain(items, value: child, path: path + "/\(index)", schemaPath: schemaPath + "/items", depth: depth + 1)
      }
    }
    if case .array(let values) = value, let contains = object["contains"],
      try valid(.object(["contains": contains]), value: value, path: path, base: base) == false {
      var parent = MarkdownDiagnostic(
        code: "frontmatter.schema.invalid", severity: severity, domain: .frontmatter,
        constraintID: constraint, location: path.isEmpty ? "/" : path, message: "No item satisfies contains",
      )
      parent.schemaLocation = schemaPath + "/contains"
      parent.definitionSource = source
      parent.causes = try values.enumerated().flatMap {
        try explain(contains, value: $0.element, path: path + "/\($0.offset)", schemaPath: schemaPath + "/contains", depth: depth + 1, includeShape: true)
      }
      result.append(parent)
    }
    if result.isEmpty, includeShape {
      var diagnostic = MarkdownDiagnostic(
        code: "frontmatter.schema.invalid", severity: severity, domain: .frontmatter,
        constraintID: constraint, location: path.isEmpty ? "/" : path, message: "Schema branch does not match the value",
      )
      diagnostic.schemaLocation = schemaPath
      diagnostic.definitionSource = source
      result.append(diagnostic)
    }
    return result
  }

  func expanded(_ schema: JSONValue, base: String, depth: Int) throws -> JSONValue {
    var remaining = 10_000
    return try expanded(schema, base: base, depth: depth, remaining: &remaining)
  }

  private func expanded(_ schema: JSONValue, base: String, depth: Int, remaining: inout Int) throws -> JSONValue {
    remaining -= 1
    guard depth < 128, remaining >= 0 else { throw MarkdownTypeDefinitionError.invalidField("type.format.capability: schema reference expansion exceeds 128 levels or 10,000 nodes (recursive schemas are unsupported)") }
    guard case .object(var object) = schema else { return schema }
    let base = object["$id"]?.stringValue ?? base
    object.removeValue(forKey: "$id")
    object.removeValue(forKey: "$defs")
    object.removeValue(forKey: "definitions")
    for (key, child) in object {
      if SemanticSchemaAdapter.maps.contains(key), case .object(let children) = child {
        object[key] = .object(try children.mapValues { try expanded($0, base: base, depth: depth + 1, remaining: &remaining) })
      } else if SemanticSchemaAdapter.singles.contains(key) {
        object[key] = try expanded(child, base: base, depth: depth + 1, remaining: &remaining)
      } else if SemanticSchemaAdapter.arrays.contains(key), case .array(let children) = child {
        object[key] = .array(try children.map { try expanded($0, base: base, depth: depth + 1, remaining: &remaining) })
      }
    }
    if let ref = object.removeValue(forKey: "$ref")?.stringValue {
      let absolute = ref.hasPrefix("#") ? base + ref : ref
      guard let target = resolve(absolute) else {
        throw MarkdownTypeDefinitionError.invalidField("type.format.capability: unresolved reference or reference outside supported schema locations: \(absolute)")
      }
      let targetBase = String(absolute.split(separator: "#", omittingEmptySubsequences: false).first ?? "")
      return .object(["allOf": .array([.object(object), try expanded(target, base: targetBase, depth: depth + 1, remaining: &remaining)])])
    }
    return .object(object)
  }

  func resolve(_ reference: String) -> JSONValue? {
    let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    var resource: JSONValue?
    if parts.first == "" { resource = root }
    else {
      _ = try? SemanticSchemaAdapter.transform(root) { object, _ in
        if object["$id"]?.stringValue == parts.first.map(String.init) { resource = .object(object) }
        return object
      }
    }
    guard var value = resource else { return nil }
    if parts.count == 1 || parts[1].isEmpty { return value }
    guard let fragment = String(parts[1]).removingPercentEncoding else { return nil }
    // A reference may legally point into an extension keyword or literal data,
    // but the current adapter only specializes standard schema locations. Reject
    // that capability at compilation rather than allowing an unasserted format.
    var knownLocations: Set<String> = []
    _ = try? SemanticSchemaAdapter.transform(value) { object, location in
      knownLocations.insert(location)
      return object
    }
    guard knownLocations.contains("#" + fragment) else { return nil }
    for component in fragment.split(separator: "/").map(String.init) {
      let key = component.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
      if let child = value.objectValue?[key] { value = child }
      else if case .array(let values) = value, let index = Int(key), values.indices.contains(index) { value = values[index] }
      else { return nil }
    }
    return value
  }
}
