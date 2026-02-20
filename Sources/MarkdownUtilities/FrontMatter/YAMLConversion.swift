//
//  YAMLConversion.swift
//  MarkdownUtilities
//
//  Utilities for converting raw YAML strings to Yams.Node.Mapping
//

import Foundation
import Yams

/// Error types for YAML conversion
public enum YAMLConversionError: Error {
  /// The YAML string could not be parsed into a valid Yams `Node`.
  case invalidYAML(underlyingError: Error)
  /// The root object of the YAML string is not a mapping (dictionary).
  case notAMapping
  /// Failed to convert to JSON format
  case jsonConversionFailed
  /// Failed to convert to PropertyList format
  case plistConversionFailed
  /// Failed to parse JSON input
  case jsonParsingFailed(underlyingError: Error)
  /// Failed to parse plist input
  case plistParsingFailed(underlyingError: Error)
}

extension YAMLConversionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidYAML(let underlyingError):
      let detail = (underlyingError as? CustomStringConvertible)?.description
        ?? underlyingError.localizedDescription
      return "Invalid YAML frontmatter: \(detail)"
    case .notAMapping:
      return "Frontmatter must be a YAML mapping (dictionary)"
    case .jsonConversionFailed:
      return "Failed to convert frontmatter to JSON"
    case .plistConversionFailed:
      return "Failed to convert frontmatter to PropertyList"
    case .jsonParsingFailed(let underlyingError):
      return "Failed to parse JSON input: \(underlyingError.localizedDescription)"
    case .plistParsingFailed(let underlyingError):
      return "Failed to parse plist input: \(underlyingError.localizedDescription)"
    }
  }
}

extension YAMLConversionError: Equatable {
  public static func == (lhs: YAMLConversionError, rhs: YAMLConversionError) -> Bool {
    switch (lhs, rhs) {
      case (.invalidYAML, .invalidYAML):
        return true  // underlying errors are not compared
      case (.notAMapping, .notAMapping):
        return true
      case (.jsonConversionFailed, .jsonConversionFailed):
        return true
      case (.plistConversionFailed, .plistConversionFailed):
        return true
      case (.jsonParsingFailed, .jsonParsingFailed):
        return true
      case (.plistParsingFailed, .plistParsingFailed):
        return true
      default:
        return false
    }
  }
}

/// Utilities for converting between raw YAML strings and `Yams.Node.Mapping`.
public enum YAMLConversion {
  /// Convert a raw YAML string to a `Yams.Node.Mapping`.
  ///
  /// - Parameter yamlString: The YAML content to parse
  /// - Returns: A `Yams.Node.Mapping` representing the parsed YAML
  /// - Throws: `YAMLConversionError.invalidYAML(underlyingError:)` if the YAML syntax is invalid,
  ///           or `YAMLConversionError.notAMapping` if the root is not a mapping
  public static func parse(_ yamlString: String) throws -> Yams.Node.Mapping {
    // Handle empty or whitespace-only input as valid empty frontmatter
    let trimmed = yamlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return Yams.Node.Mapping()
    }

    // Parse YAML string to Node
    let node: Yams.Node
    do {
      guard let parsed = try Yams.compose(yaml: yamlString) else {
        throw YAMLConversionError.notAMapping
      }
      node = parsed
    } catch let error as YAMLConversionError {
      throw error
    } catch {
      throw YAMLConversionError.invalidYAML(underlyingError: error)
    }

    // Verify the root is a mapping (dictionary)
    guard let mapping = node.mapping else {
      throw YAMLConversionError.notAMapping
    }

    return mapping
  }

  /// Serialize a `Yams.Node.Mapping` back to a YAML string.
  ///
  /// - Parameter mapping: The mapping to serialize
  /// - Returns: A YAML string representation
  /// - Throws: If serialization fails
  public static func serialize(_ mapping: Yams.Node.Mapping) throws -> String {
    try Yams.serialize(node: .mapping(mapping))
  }

  /// Convert a Yams Node to a JSON string.
  ///
  /// - Parameters:
  ///   - node: The YAML node to convert
  ///   - options: JSON serialization options
  /// - Returns: A JSON string representation
  /// - Throws: `YAMLConversionError.jsonConversionFailed` if conversion fails
  public static func nodeToJSON(_ node: Yams.Node, options: JSONSerialization.WritingOptions = []) throws -> String {
    let constructor = Yams.Constructor.default
    let value: Any = constructor.any(from: node)
    return try anyToJSON(value, options: options)
  }

  /// Convert any value to a JSON string.
  ///
  /// - Parameters:
  ///   - any: The value to convert
  ///   - options: JSON serialization options
  /// - Returns: A JSON string representation
  /// - Throws: `YAMLConversionError.jsonConversionFailed` if conversion fails
  public static func anyToJSON(_ any: Any, options: JSONSerialization.WritingOptions = []) throws -> String {
    // Recursively convert AnyHashable keys to Strings for JSON serialization
    func convertToJSONCompatible(_ value: Any) -> Any {
      if let dict = value as? [AnyHashable: Any] {
        return dict.reduce(into: [String: Any]()) { result, pair in
          result[String(describing: pair.key)] = convertToJSONCompatible(pair.value)
        }
      } else if let array = value as? [Any] {
        return array.map { convertToJSONCompatible($0) }
      } else if let date = value as? Date {
        // Convert Date to ISO8601 string for JSON
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
      } else {
        return value
      }
    }

    let convertedAny = convertToJSONCompatible(any)

    if JSONSerialization.isValidJSONObject(convertedAny) {
      let jsonData: Data = try JSONSerialization.data(
        withJSONObject: convertedAny,
        options: options
      )

      guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw YAMLConversionError.jsonConversionFailed
      }

      return jsonString
    } else {
      // Value is likely a primitive type
      switch convertedAny {
        case let string as String:
          return string
        case let stringConvertible as CustomStringConvertible:
          return stringConvertible.description
        default:
          return String(describing: convertedAny)
      }
    }
  }

  /// Convert any value to a YAML string.
  ///
  /// - Parameter any: The value to convert
  /// - Returns: A YAML string representation
  /// - Throws: If serialization fails
  public static func anyToYAML(_ any: Any) throws -> String {
    return try Yams.dump(
      object: any,
      sortKeys: true,
      sequenceStyle: .block,
      mappingStyle: .block,
      newLineScalarStyle: .plain
    )
  }

  /// Convert a Yams Node to a PropertyList XML string.
  ///
  /// - Parameter node: The YAML node to convert
  /// - Returns: A PropertyList XML string representation
  /// - Throws: `YAMLConversionError.plistConversionFailed` if conversion fails
  public static func nodeToPlist(_ node: Yams.Node) throws -> String {
    let constructor = Yams.Constructor.default
    let value: Any = constructor.any(from: node)
    return try anyToPlist(value)
  }

  /// Convert any value to a PropertyList XML string.
  ///
  /// - Parameter any: The value to convert
  /// - Returns: A PropertyList XML string representation
  /// - Throws: `YAMLConversionError.plistConversionFailed` if conversion fails
  public static func anyToPlist(_ any: Any) throws -> String {
    let plistData = try PropertyListSerialization.data(
      fromPropertyList: any,
      format: .xml,
      options: 0
    )

    guard let plistString = String(data: plistData, encoding: .utf8) else {
      throw YAMLConversionError.plistConversionFailed
    }
    return plistString
  }

  /// Parse a JSON string to a Yams.Node.Mapping.
  ///
  /// - Parameter jsonString: The JSON string to parse
  /// - Returns: A Yams.Node.Mapping representing the parsed JSON
  /// - Throws: `YAMLConversionError.jsonParsingFailed` if the JSON is invalid,
  ///           or `YAMLConversionError.notAMapping` if the root is not a dictionary
  public static func parseJSON(_ jsonString: String) throws -> Yams.Node.Mapping {
    guard let data = jsonString.data(using: .utf8) else {
      throw YAMLConversionError.jsonParsingFailed(
        underlyingError: NSError(
          domain: "MarkdownUtilities",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to UTF-8 data"]
        )
      )
    }

    let obj: Any
    do {
      obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    } catch {
      throw YAMLConversionError.jsonParsingFailed(underlyingError: error)
    }

    let node = nodeFromAny(obj)

    guard let mapping = node.mapping else {
      throw YAMLConversionError.notAMapping
    }

    return mapping
  }

  /// Parse a PropertyList XML string to a Yams.Node.Mapping.
  ///
  /// - Parameter plistString: The PropertyList XML string to parse
  /// - Returns: A Yams.Node.Mapping representing the parsed plist
  /// - Throws: `YAMLConversionError.plistParsingFailed` if the plist is invalid,
  ///           or `YAMLConversionError.notAMapping` if the root is not a dictionary
  public static func parsePlist(_ plistString: String) throws -> Yams.Node.Mapping {
    guard let data = plistString.data(using: .utf8) else {
      throw YAMLConversionError.plistParsingFailed(
        underlyingError: NSError(
          domain: "MarkdownUtilities",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to UTF-8 data"]
        )
      )
    }

    let obj: Any
    do {
      obj = try PropertyListSerialization.propertyList(from: data, format: nil)
    } catch {
      throw YAMLConversionError.plistParsingFailed(underlyingError: error)
    }

    let node = nodeFromAny(obj)

    guard let mapping = node.mapping else {
      throw YAMLConversionError.notAMapping
    }

    return mapping
  }

  /// Convert a Swift value to a Yams.Node.
  ///
  /// - Parameter any: The value to convert
  /// - Returns: A Yams.Node representation
  private static func nodeFromAny(_ any: Any) -> Yams.Node {
    if let dict = any as? [String: Any] {
      var pairs: [(Yams.Node, Yams.Node)] = []
      for (key, value) in dict {
        pairs.append((.scalar(.init(key)), nodeFromAny(value)))
      }
      return .mapping(.init(pairs))
    } else if let dict = any as? [AnyHashable: Any] {
      // Handle AnyHashable keys from PropertyListSerialization
      var pairs: [(Yams.Node, Yams.Node)] = []
      for (key, value) in dict {
        pairs.append((.scalar(.init(String(describing: key))), nodeFromAny(value)))
      }
      return .mapping(.init(pairs))
    } else if let array = any as? [Any] {
      return .sequence(.init(array.map(nodeFromAny)))
    } else if let string = any as? String {
      return .scalar(.init(string))
    } else if let number = any as? NSNumber {
      // Distinguish bool from number
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .scalar(.init(number.boolValue ? "true" : "false"))
      } else {
        return .scalar(.init(number.description))
      }
    } else if let date = any as? Date {
      let formatter = ISO8601DateFormatter()
      return .scalar(.init(formatter.string(from: date)))
    } else {
      return .scalar(.init(String(describing: any)))
    }
  }
}

// MARK: - Yams.Node Extensions

extension Yams.Node {
  /// Convert the Yams Node to a JSON string.
  ///
  /// - Parameter options: JSON serialization options
  /// - Returns: A JSON string representation
  /// - Throws: `YAMLConversionError.jsonConversionFailed` if conversion fails
  public func toJSON(options: JSONSerialization.WritingOptions = []) throws -> String {
    return try YAMLConversion.nodeToJSON(self, options: options)
  }

  /// Convert the Yams Node to a PropertyList XML string.
  ///
  /// - Returns: A PropertyList XML string representation
  /// - Throws: `YAMLConversionError.plistConversionFailed` if conversion fails
  public func toPlist() throws -> String {
    return try YAMLConversion.nodeToPlist(self)
  }
}
