//
//  OutputFormat.swift
//  md-utils
//
//  Output format options and helper functions for CLI commands.
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import Yams

extension FrontMatterFormat: ExpressibleByArgument {}

/// Output format options for CLI commands
enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
  case json
  case yaml
  case toml
  case raw
  case plist

  var defaultValueDescription: String {
    switch self {
      case .json: return "json (default)"
      case .yaml: return "yaml"
      case .toml: return "toml"
      case .raw: return "raw"
      case .plist: return "plist"
    }
  }
}

/// Print a Yams Node in the specified format
func print(node: Yams.Node, format: OutputFormat) throws {
  switch format {
    case .json:
      let jsonString = try YAMLConversion.nodeToJSON(node, options: [.prettyPrinted, .sortedKeys])
      Swift.print(jsonString)
    case .yaml, .raw:
      let yamlString = try Yams.serialize(node: node)
      Swift.print(yamlString)
    case .plist:
      let plistString = try YAMLConversion.nodeToPlist(node)
      Swift.print(plistString)
    case .toml:
      let value = try YAMLConversion.safeNodeToSwiftValue(node)
      Swift.print(try FrontMatterConversion.serializeTOMLValue(value), terminator: "")
  }
}

/// Print any value in the specified format
func printAny(_ any: Any, format: OutputFormat) throws {
  switch format {
    case .json:
      let jsonString = try YAMLConversion.anyToJSON(any, options: [.prettyPrinted, .sortedKeys])
      Swift.print(jsonString)
    case .yaml, .raw:
      let yamlString = try YAMLConversion.anyToYAML(any)
      Swift.print(yamlString)
    case .plist:
      let plistString = try YAMLConversion.anyToPlist(any)
      Swift.print(plistString)
    case .toml:
      Swift.print(try FrontMatterConversion.serializeTOMLValue(any), terminator: "")
  }
}

/// Prints format-neutral frontmatter in the requested representation.
func print(
  frontMatter: FrontMatter,
  format: OutputFormat,
  sourceFormat: FrontMatterFormat? = nil
) throws {
  switch format {
  case .json:
    Swift.print(try YAMLConversion.anyToJSON(
      FrontMatterConversion.foundationValue(frontMatter),
      options: [.prettyPrinted, .sortedKeys]
    ))
  case .yaml:
    Swift.print(try FrontMatterConversion.serialize(frontMatter, format: .yaml), terminator: "")
  case .toml:
    Swift.print(try FrontMatterConversion.serialize(frontMatter, format: .toml), terminator: "")
  case .raw:
    Swift.print(
      try FrontMatterConversion.serialize(frontMatter, format: sourceFormat ?? .yaml),
      terminator: ""
    )
  case .plist:
    Swift.print(try YAMLConversion.anyToPlist(FrontMatterConversion.foundationValue(frontMatter)))
  }
}
