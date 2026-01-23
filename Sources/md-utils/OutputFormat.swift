//
//  OutputFormat.swift
//  md-utils
//
//  Output format options and helper functions for CLI commands.
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import Yams

/// Output format options for CLI commands
enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
  case json
  case yaml
  case raw
  case plist

  var defaultValueDescription: String {
    switch self {
      case .json: return "json (default)"
      case .yaml: return "yaml"
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
  }
}
