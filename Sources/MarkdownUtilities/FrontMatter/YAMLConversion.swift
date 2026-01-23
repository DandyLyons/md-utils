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
  case invalidYAML
  /// The root object of the YAML string is not a mapping (dictionary).
  case notAMapping
  /// Failed to convert to JSON format
  case jsonConversionFailed
  /// Failed to convert to PropertyList format
  case plistConversionFailed
}

/// Utilities for converting between raw YAML strings and `Yams.Node.Mapping`.
public enum YAMLConversion {
  /// Convert a raw YAML string to a `Yams.Node.Mapping`.
  ///
  /// - Parameter yamlString: The YAML content to parse
  /// - Returns: A `Yams.Node.Mapping` representing the parsed YAML
  /// - Throws: `YAMLConversionError.invalidYAML` if the YAML syntax is invalid,
  ///           or `YAMLConversionError.notAMapping` if the root is not a mapping
  public static func parse(_ yamlString: String) throws -> Yams.Node.Mapping {
    // Handle empty or whitespace-only input as valid empty frontmatter
    let trimmed = yamlString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return Yams.Node.Mapping()
    }

    // Parse YAML string to Node
    guard let node = try? Yams.compose(yaml: yamlString) else {
      throw YAMLConversionError.invalidYAML
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
