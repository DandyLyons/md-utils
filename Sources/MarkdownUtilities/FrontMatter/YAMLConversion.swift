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
}

/// Utilities for converting between raw YAML strings and `Yams.Node.Mapping`.
enum YAMLConversion {
  /// Convert a raw YAML string to a `Yams.Node.Mapping`.
  ///
  /// - Parameter yamlString: The YAML content to parse
  /// - Returns: A `Yams.Node.Mapping` representing the parsed YAML
  /// - Throws: `YAMLConversionError.invalidYAML` if the YAML syntax is invalid,
  ///           or `YAMLConversionError.notAMapping` if the root is not a mapping
  static func parse(_ yamlString: String) throws -> Yams.Node.Mapping {
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
  static func serialize(_ mapping: Yams.Node.Mapping) throws -> String {
    try Yams.serialize(node: .mapping(mapping))
  }
}
