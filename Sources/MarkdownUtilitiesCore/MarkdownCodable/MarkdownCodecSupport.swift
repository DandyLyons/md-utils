import Foundation

/// Selects the model property represented by a Markdown document's body.
///
/// The key path reads the body value from the model. `codingPath` names the
/// corresponding keys in the encoded frontmatter representation, including
/// any custom `CodingKeys` names.
public struct MarkdownBodyField<Root> {
  public let keyPath: KeyPath<Root, String>
  public let codingPath: [String]

  public init(_ keyPath: KeyPath<Root, String>, codingPath: [String]) {
    self.keyPath = keyPath
    self.codingPath = codingPath
  }
}

/// Controls whether the body field is also retained in frontmatter.
public enum MarkdownBodyFrontmatterStrategy: Sendable {
  /// Remove the selected field from frontmatter and represent it only as the body.
  case omit

  /// Retain the selected field in frontmatter and duplicate it as the body.
  case include
}

/// Errors specific to mapping Codable values to a Markdown document envelope.
public enum MarkdownCodecError: Error, Equatable, Sendable, LocalizedError {
  case emptyBodyCodingPath
  case emptyBodyCodingPathComponent(index: Int)
  case encodedRootIsNotMapping(format: FrontMatterFormat)
  case bodyFieldMissing(codingPath: [String])
  case bodyFieldIsNotString(codingPath: [String])
  case bodyFieldValueMismatch(codingPath: [String])
  case bodyFrontmatterValueMismatch(codingPath: [String])
  case decodedBodyValueMismatch(codingPath: [String])
  case bodyCodingPathBlocked(codingPath: [String], component: String)
  case frontMatterFormatMismatch(expected: FrontMatterFormat, actual: FrontMatterFormat?)
  case tomlNullNotRepresentable(codingPath: [String])
  case tomlIntegerOutOfRange(codingPath: [String])

  public var errorDescription: String? {
    switch self {
    case .emptyBodyCodingPath:
      return "The Markdown body coding path must contain at least one key."
    case .emptyBodyCodingPathComponent(let index):
      return "The Markdown body coding path contains an empty key at index \(index)."
    case .encodedRootIsNotMapping(let format):
      return "The encoded value must have a top-level \(format.rawValue.uppercased()) mapping."
    case .bodyFieldMissing(let codingPath):
      return "The encoded body field is missing at \(Self.display(codingPath))."
    case .bodyFieldIsNotString(let codingPath):
      return "The encoded body field at \(Self.display(codingPath)) is not a string."
    case .bodyFieldValueMismatch(let codingPath):
      return "The body key path and encoded coding path disagree at \(Self.display(codingPath))."
    case .bodyFrontmatterValueMismatch(let codingPath):
      return "The frontmatter body field at \(Self.display(codingPath)) disagrees with the Markdown body."
    case .decodedBodyValueMismatch(let codingPath):
      return "The decoded body value at \(Self.display(codingPath)) disagrees with the Markdown body."
    case .bodyCodingPathBlocked(let codingPath, let component):
      return "The body coding path \(Self.display(codingPath)) is blocked by a non-mapping value at \(component)."
    case .frontMatterFormatMismatch(let expected, let actual):
      let actualDescription = actual?.rawValue.uppercased() ?? "no"
      return "Expected \(expected.rawValue.uppercased()) frontmatter but found \(actualDescription) frontmatter."
    case .tomlNullNotRepresentable(let codingPath):
      return "TOML cannot represent the null value encoded at \(Self.display(codingPath))."
    case .tomlIntegerOutOfRange(let codingPath):
      return "TOML cannot represent the unsigned integer encoded at \(Self.display(codingPath))."
    }
  }

  private static func display(_ codingPath: [String]) -> String {
    codingPath.isEmpty ? "<root>" : codingPath.joined(separator: ".")
  }
}

enum MarkdownCodecSupport {
  static func validate<Root>(_ bodyField: MarkdownBodyField<Root>) throws {
    guard !bodyField.codingPath.isEmpty else {
      throw MarkdownCodecError.emptyBodyCodingPath
    }
    if let index = bodyField.codingPath.firstIndex(where: \String.isEmpty) {
      throw MarkdownCodecError.emptyBodyCodingPathComponent(index: index)
    }
  }

  static func verifyEncodedBody(
    in frontMatter: FrontMatter,
    codingPath: [String],
    expectedBody: String
  ) throws {
    let value = try value(in: frontMatter, at: codingPath)
    guard let value else {
      throw MarkdownCodecError.bodyFieldMissing(codingPath: codingPath)
    }
    guard case .string(let encodedBody) = value else {
      throw MarkdownCodecError.bodyFieldIsNotString(codingPath: codingPath)
    }
    guard encodedBody == expectedBody else {
      throw MarkdownCodecError.bodyFieldValueMismatch(codingPath: codingPath)
    }
  }

  static func removingBody(from frontMatter: FrontMatter, at codingPath: [String]) throws -> FrontMatter {
    try removingValue(from: frontMatter, remainingPath: ArraySlice(codingPath), fullPath: codingPath)
  }

  static func insertingBody(
    _ body: String,
    into frontMatter: FrontMatter,
    at codingPath: [String]
  ) throws -> FrontMatter {
    try insertingBody(
      body,
      into: frontMatter,
      remainingPath: ArraySlice(codingPath),
      fullPath: codingPath
    )
  }

  static func sortedRecursively(_ frontMatter: FrontMatter) -> FrontMatter {
    var sorted = FrontMatter(frontMatter.map { entry in
      let value: FrontMatterValue
      switch entry.value {
      case .object(let object):
        value = .object(sortedRecursively(object))
      case .array(let values):
        value = .array(values.map(sortedRecursively))
      default:
        value = entry.value
      }
      return (entry.key, value)
    })
    sorted.sort { $0.key < $1.key }
    return sorted
  }

  static func render(
    frontMatter: FrontMatter,
    body: String,
    format: FrontMatterFormat
  ) throws -> String {
    let serialized: String
    if frontMatter.isEmpty {
      serialized = ""
    } else {
      let value = try FrontMatterConversion.serialize(frontMatter, format: format)
      serialized = value.hasSuffix("\n") ? value : value + "\n"
    }
    return "\(format.delimiter)\n\(serialized)\(format.delimiter)\n\(body)"
  }

  private static func value(
    in frontMatter: FrontMatter,
    at codingPath: [String]
  ) throws -> FrontMatterValue? {
    var current = frontMatter
    for (index, component) in codingPath.enumerated() {
      guard let value = current[component] else { return nil }
      if index == codingPath.index(before: codingPath.endIndex) { return value }
      guard case .object(let nested) = value else {
        throw MarkdownCodecError.bodyCodingPathBlocked(
          codingPath: codingPath,
          component: codingPath[...index].joined(separator: ".")
        )
      }
      current = nested
    }
    return nil
  }

  private static func removingValue(
    from frontMatter: FrontMatter,
    remainingPath: ArraySlice<String>,
    fullPath: [String]
  ) throws -> FrontMatter {
    guard let component = remainingPath.first else { return frontMatter }
    var result = frontMatter
    let rest = remainingPath.dropFirst()
    if rest.isEmpty {
      result[component] = nil
      return result
    }
    guard let existing = result[component] else {
      throw MarkdownCodecError.bodyFieldMissing(codingPath: fullPath)
    }
    guard case .object(let nested) = existing else {
      let traversedCount = fullPath.count - remainingPath.count + 1
      throw MarkdownCodecError.bodyCodingPathBlocked(
        codingPath: fullPath,
        component: fullPath.prefix(traversedCount).joined(separator: ".")
      )
    }
    result[component] = .object(
      try removingValue(from: nested, remainingPath: rest, fullPath: fullPath)
    )
    return result
  }

  private static func insertingBody(
    _ body: String,
    into frontMatter: FrontMatter,
    remainingPath: ArraySlice<String>,
    fullPath: [String]
  ) throws -> FrontMatter {
    guard let component = remainingPath.first else { return frontMatter }
    var result = frontMatter
    let rest = remainingPath.dropFirst()
    if rest.isEmpty {
      if let existing = result[component] {
        guard case .string(let frontmatterBody) = existing else {
          throw MarkdownCodecError.bodyFieldIsNotString(codingPath: fullPath)
        }
        guard frontmatterBody == body else {
          throw MarkdownCodecError.bodyFrontmatterValueMismatch(codingPath: fullPath)
        }
      }
      result[component] = .string(body)
      return result
    }

    let nested: FrontMatter
    if let existing = result[component] {
      guard case .object(let object) = existing else {
        let traversedCount = fullPath.count - remainingPath.count + 1
        throw MarkdownCodecError.bodyCodingPathBlocked(
          codingPath: fullPath,
          component: fullPath.prefix(traversedCount).joined(separator: ".")
        )
      }
      nested = object
    } else {
      nested = FrontMatter()
    }
    result[component] = .object(
      try insertingBody(body, into: nested, remainingPath: rest, fullPath: fullPath)
    )
    return result
  }

  private static func sortedRecursively(_ value: FrontMatterValue) -> FrontMatterValue {
    switch value {
    case .object(let object): .object(sortedRecursively(object))
    case .array(let values): .array(values.map(sortedRecursively))
    default: value
    }
  }
}
