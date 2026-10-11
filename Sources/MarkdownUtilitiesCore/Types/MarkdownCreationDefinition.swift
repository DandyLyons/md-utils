import Foundation

/// Whether Knap owns the complete document or only its body.
public enum MarkdownTemplateMode: String, Codable, Sendable {
  case document, body
}

/// Portable declaration; native hosts resolve files and execute Knap.
public struct MarkdownCreationTemplate: Equatable, Sendable {
  public let inline: String?
  public let reference: String?
  public let mode: MarkdownTemplateMode
  public let inputSchema: MarkdownJSONSchemaSource?

  public var jsonValue: JSONValue {
    var object: [String: JSONValue] = ["mode": .string(mode.rawValue)]
    if let inline { object["inline"] = .string(inline) }
    if let reference { object["ref"] = .string(reference) }
    if let inputSchema {
      switch inputSchema {
      case .inline(let value): object["inputSchema"] = .object(["inline": value])
      case .reference(let value): object["inputSchema"] = .object(["ref": .string(value)])
      }
    }
    return .object(["template": .object(object)])
  }

  public static func decode(_ value: JSONValue) throws -> Self {
    func invalid(_ message: String) -> MarkdownTypeDefinitionError {
      .invalidField("creation.template: " + message)
    }
    guard let creation = value.objectValue, Set(creation.keys) == ["template"],
      let object = creation["template"]?.objectValue,
      Set(object.keys).subtracting(["inline", "ref", "mode", "inputSchema"]).isEmpty,
      (object["inline"] != nil) != (object["ref"] != nil) else {
      throw invalid("Expected exactly one inline or ref source and optional mode/inputSchema")
    }
    if let inline = object["inline"], inline.stringValue == nil { throw invalid("inline must be a string") }
    if let ref = object["ref"], ref.stringValue?.isEmpty != false { throw invalid("ref must be a nonempty string") }
    let mode: MarkdownTemplateMode
    if let raw = object["mode"] {
      guard let string = raw.stringValue, let parsed = MarkdownTemplateMode(rawValue: string) else {
        throw invalid("mode must be document or body")
      }
      mode = parsed
    } else { mode = .document }
    var schema: MarkdownJSONSchemaSource?
    if let raw = object["inputSchema"] {
      guard let source = raw.objectValue, source.count == 1 else { throw invalid("inputSchema requires inline or ref") }
      if let ref = source["ref"]?.stringValue, !ref.isEmpty { schema = .reference(ref) }
      else if let inline = source["inline"], inline.objectValue != nil || inline == .boolean(true) || inline == .boolean(false) {
        schema = .inline(inline)
      } else { throw invalid("inputSchema requires a schema in inline or a nonempty ref") }
    }
    return Self(inline: object["inline"]?.stringValue, reference: object["ref"]?.stringValue,
      mode: mode, inputSchema: schema)
  }
}

/// Explicit allocation directory and optional disambiguating type name for a rule.
public struct MarkdownRuleCreation: Equatable, Sendable {
  public let directory: String
  public let type: String?

  public static func decode(_ value: JSONValue, source: String) throws -> Self {
    guard let object = value.objectValue,
      Set(object.keys).subtracting(["directory", "type"]).isEmpty,
      let directory = object["directory"]?.stringValue, !directory.isEmpty,
      object["type"] == nil || object["type"]?.stringValue?.isEmpty == false else {
      throw MarkdownRuleFileError(source: source, location: "creation",
        message: "Expected a nonempty directory and optional type name")
    }
    return Self(directory: directory, type: object["type"]?.stringValue)
  }

  public var jsonValue: JSONValue {
    var object: [String: JSONValue] = ["directory": .string(directory)]
    if let type { object["type"] = .string(type) }
    return .object(object)
  }
}
