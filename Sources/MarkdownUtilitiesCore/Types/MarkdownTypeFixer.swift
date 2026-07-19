import Foundation
import Yams

/// Applies selected structured fix-its to an in-memory Markdown record.
public enum MarkdownTypeFixer {
  public static func apply(
    _ fixIts: [MarkdownFixIt],
    to record: MarkdownRecord,
    inputs: [String: JSONValue] = [:]
  ) throws -> MarkdownRecord {
    let original = try parse(record.content)
    var frontmatter = original.frontmatter
    var body = original.body
    var ensureFrontmatter = false
    var frontmatterEdits: [(path: [String], value: JSONValue)] = []

    for fixIt in fixIts {
      for edit in fixIt.edits {
        switch edit {
        case .ensureFrontmatter:
          ensureFrontmatter = true
        case .setFrontmatterValue(let path, let value):
          try set(value, at: path, in: &frontmatter)
          frontmatterEdits.append((path, value))
        case .requestFrontmatterValue(let path):
          let key = path.joined(separator: ".")
          guard let value = inputs[key] else {
            throw MarkdownTypeFixerError.missingInput(path: key)
          }
          try set(value, at: path, in: &frontmatter)
          frontmatterEdits.append((path, value))
        case .appendHeading(let text, let level):
          let prefix = String(repeating: "#", count: level)
          if body.isEmpty == false, body.hasSuffix("\n") == false {
            body += "\n"
          }
          if body.isEmpty == false, body.hasSuffix("\n\n") == false {
            body += "\n"
          }
          body += "\(prefix) \(text)\n"
        }
      }
    }

    let prefix: String
    if frontmatterEdits.isEmpty {
      prefix = ensureFrontmatter && original.hasFrontmatter == false
        ? "---\n---\n"
        : original.prefix
    } else if canAppendWithoutReformatting(frontmatterEdits, original: original) {
      prefix = try appending(frontmatterEdits, to: original.prefix)
    } else {
      prefix = try renderFrontmatter(frontmatter, preserveEmpty: ensureFrontmatter)
    }

    var updated = record
    updated.content = prefix + body
    return updated
  }

  private static func parse(_ content: String) throws -> ParsedRecordContent {
    let parser = FrontMatterParser()
    var input = Substring(content)
    let parts = try parser.parse(&input)
    let hasFrontmatter = content.starts(with: "---\n")
    guard hasFrontmatter else {
      return ParsedRecordContent(frontmatter: [:], prefix: "", body: parts.body, hasFrontmatter: false)
    }
    let mapping = try YAMLConversion.parse(parts.rawFrontMatter)
    let value = try JSONValue(any: YAMLConversion.safeNodeToSwiftValue(.mapping(mapping)))
    let prefix = parts.body.isEmpty
      ? content
      : String(content.dropLast(parts.body.count))
    return ParsedRecordContent(
      frontmatter: value.objectValue ?? [:],
      prefix: prefix,
      body: parts.body,
      hasFrontmatter: true
    )
  }

  private static func canAppendWithoutReformatting(
    _ edits: [(path: [String], value: JSONValue)],
    original: ParsedRecordContent
  ) -> Bool {
    guard original.hasFrontmatter else { return false }
    var seen = Set(original.frontmatter.keys)
    for edit in edits {
      guard edit.path.count == 1, let key = edit.path.first, seen.insert(key).inserted else {
        return false
      }
    }
    return true
  }

  private static func appending(
    _ edits: [(path: [String], value: JSONValue)],
    to prefix: String
  ) throws -> String {
    let closingLength: Int
    let closing: String
    if prefix.hasSuffix("---\n") {
      closingLength = 4
      closing = "---\n"
    } else if prefix.hasSuffix("---") {
      closingLength = 3
      closing = "---"
    } else {
      throw MarkdownTypeFixerError.invalidFrontmatterBoundary
    }

    var result = String(prefix.dropLast(closingLength))
    if result.hasSuffix("\n") == false { result += "\n" }
    for edit in edits {
      guard let key = edit.path.first else { throw MarkdownTypeFixerError.emptyPath }
      let yaml = try Yams.dump(
        object: [key: edit.value.foundationValue],
        sortKeys: false,
        sequenceStyle: .block,
        mappingStyle: .block,
        newLineScalarStyle: .plain
      ).trimmingCharacters(in: .newlines)
      result += yaml + "\n"
    }
    return result + closing
  }

  private static func set(
    _ value: JSONValue,
    at path: [String],
    in object: inout [String: JSONValue]
  ) throws {
    guard let first = path.first else {
      throw MarkdownTypeFixerError.emptyPath
    }
    if path.count == 1 {
      object[first] = value
      return
    }
    var child: [String: JSONValue]
    if case .object(let existing)? = object[first] {
      child = existing
    } else if object[first] == nil {
      child = [:]
    } else {
      throw MarkdownTypeFixerError.nonObjectPath(path: first)
    }
    try set(value, at: Array(path.dropFirst()), in: &child)
    object[first] = .object(child)
  }

  private static func renderFrontmatter(
    _ frontmatter: [String: JSONValue],
    preserveEmpty: Bool
  ) throws -> String {
    guard frontmatter.isEmpty == false else {
      return preserveEmpty ? "---\n---\n" : ""
    }
    let yaml = try Yams.dump(
      object: JSONValue.object(frontmatter).foundationValue,
      sortKeys: false,
      sequenceStyle: .block,
      mappingStyle: .block,
      newLineScalarStyle: .plain
    ).trimmingCharacters(in: .newlines)
    return "---\n\(yaml)\n---\n"
  }

  private struct ParsedRecordContent {
    var frontmatter: [String: JSONValue]
    var prefix: String
    var body: String
    var hasFrontmatter: Bool
  }
}

/// Errors produced while applying a selected fix-it.
public enum MarkdownTypeFixerError: Error, Equatable, LocalizedError {
  case missingInput(path: String)
  case emptyPath
  case nonObjectPath(path: String)
  case invalidFrontmatterBoundary

  public var errorDescription: String? {
    switch self {
    case .missingInput(let path):
      return "A value is required for \(path)"
    case .emptyPath:
      return "A frontmatter edit path cannot be empty"
    case .nonObjectPath(let path):
      return "Cannot set a nested value through non-object frontmatter property \(path)"
    case .invalidFrontmatterBoundary:
      return "Cannot preserve a malformed frontmatter boundary"
    }
  }
}
