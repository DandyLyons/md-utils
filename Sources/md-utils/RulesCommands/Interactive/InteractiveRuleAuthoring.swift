import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit

extension InteractiveAuthoring {
  func authorRule(original: MarkdownRuleFile?, session: inout InteractiveDraftSession) throws {
    var object = original.map { file -> [String: Any] in
      var result: [String: Any] = ["name": file.name, "types": file.types.jsonValue.foundationValue]
      if let match = file.match { result["match"] = match.foundationValue }
      if let schema = file.schemaReference { result["$schema"] = schema }
      return result
    } ?? [:]
    object["name"] = try prompts.required("Rule name", default: original?.name)
    let path = try original.map { Path($0.source) } ?? session.resourcePath(
      prompts.required("Rule filename relative to rules/ (include .mdrule.json)"), types: false)
    if original == nil { object["types"] = try typeExpression(session: &session).foundationValue }
    while true {
      let action = try prompts.choose("Rule definition", ["Done", "Rename", "Type expression", "Matcher expression"])
      switch action {
      case "Done":
        var proposed = session
        try proposed.stage(path: path, content: InteractiveDraftSession.json(object), creating: original == nil)
        do {
          try proposed.validate()
          session = proposed
          return
        } catch { prompts.output(CLIStyle.error(error.localizedDescription)) }
      case "Rename": object["name"] = try prompts.required("Rule name", default: object["name"] as? String)
      case "Type expression": object["types"] = try typeExpression(session: &session).foundationValue
      default:
        if let match = object["match"] { prompts.output(try InteractiveDraftSession.json(match)) }
        let mode = try prompts.choose("Selection", ["Keep existing", "Match every candidate", "Build expression", "Enter JSON expression"])
        if mode == "Match every candidate" { object.removeValue(forKey: "match") }
        if mode == "Build expression" { object["match"] = try matchExpression().foundationValue }
        if mode == "Enter JSON expression" {
          object["match"] = try prompts.json("Matcher JSON (allOf, anyOf, oneOf, not, or a matcher leaf)",
            default: try object["match"].map { try JSONValue(any: $0) }).foundationValue
        }
      }
    }
  }

  private func typeExpression(session: inout InteractiveDraftSession) throws -> JSONValue {
    let mode = try prompts.choose("Type expression", ["Existing type", "Create new type", "allOf", "anyOf", "oneOf", "not", "Enter JSON expression"])
    if mode == "Existing type" {
      let references = try session.typeDefinitions().compactMap { definition -> String? in
        guard let source = definition.source else { return nil }
        return String(source.dropFirst((session.root.string + "/.md-utils/types/").count))
      }.sorted()
      guard references.isEmpty == false else {
        prompts.output(CLIStyle.muted("No types available. Create a type to continue."))
        return .string(try authorType(original: nil, session: &session))
      }
      return .string(try prompts.choose("Type resource relative to types/", references))
    }
    if mode == "Create new type" { return .string(try authorType(original: nil, session: &session)) }
    if mode == "Enter JSON expression" { return try prompts.json("Type expression JSON (filename string or composition object)") }
    if mode == "not" { return .object([mode: try typeExpression(session: &session)]) }
    var children = [try typeExpression(session: &session)]
    while try prompts.choose("Composition children", ["Done", "Add child"]) == "Add child" {
      children.append(try typeExpression(session: &session))
    }
    return .object([mode: .array(children)])
  }

  private func matchExpression() throws -> JSONValue {
    let mode = try prompts.choose("Match expression", ["Matcher leaf", "allOf", "anyOf", "oneOf", "not"])
    if mode == "Matcher leaf" { return try matchLeaf() }
    if mode == "not" { return .object([mode: try matchExpression()]) }
    var children = [try matchExpression()]
    while try prompts.choose("Composition children", ["Done", "Add child"]) == "Add child" {
      children.append(try matchExpression())
    }
    return .object([mode: .array(children)])
  }

  private func matchLeaf() throws -> JSONValue {
    var object: [String: JSONValue] = [:]
    while true {
      let field = try prompts.choose("Matcher fields (combined with AND)",
        ["Done", "paths", "excludePaths", "file", "frontmatter", "frontmatterQuery", "document", "Remove field"])
      if field == "Done" { return .object(object) }
      if field == "Remove field" {
        if object.isEmpty == false { object.removeValue(forKey: try prompts.choose("Remove field", object.keys.sorted())) }
        continue
      }
      switch field {
      case "paths", "excludePaths":
        var paths: [JSONValue] = []
        repeat {
          paths.append(.string(try prompts.required("Project-relative glob (one pattern)")))
        } while try prompts.choose("Path patterns", ["Done", "Add pattern"]) == "Add pattern"
        object[field] = .array(paths)
      case "frontmatterQuery":
        object[field] = .object(["jmespath": .string(try prompts.required("JMESPath expression"))])
      case "file":
        object[field] = try fields("File matcher", names: ["pathRegex", "filenameEquals", "extensionIn", "modifiedAfter", "modifiedBefore"],
          help: "Use JSON strings; extensionIn uses a string array. Dates use YYYY-MM-DD or RFC 3339.")
      case "document":
        object[field] = try fields("Document matcher", names: ["hasHeading", "headingRegex", "hasHeadingAtLevel", "hasSection", "bodyContains", "bodyRegex", "hasWikilink", "lineCount", "wordCount"],
          help: "Use JSON strings; hasHeadingAtLevel uses {\"heading\":\"Title\",\"level\":1}; counts use {\"min\":0,\"max\":100}; hasWikilink accepts true or a target string.")
      default:
        let key = try prompts.required("Frontmatter key")
        let predicate = try prompts.json("Predicate JSON, e.g. {\"equals\":\"published\"}, {\"exists\":true}, or {\"includes\":\"tag\"}")
        var frontmatter = object[field]?.objectValue ?? [:]
        frontmatter[key] = predicate
        object[field] = .object(frontmatter)
      }
    }
  }

  private func fields(_ label: String, names: [String], help: String) throws -> JSONValue {
    prompts.output(CLIStyle.muted(help))
    var result: [String: JSONValue] = [:]
    while true {
      let field = try prompts.choose(label, ["Done"] + names)
      if field == "Done" { return .object(result) }
      result[field] = try prompts.json(field + " JSON value", default: result[field])
    }
  }
}
