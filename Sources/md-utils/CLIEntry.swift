//
//  CLIEntry.swift
//  md-utils
//

import ArgumentParser
import Foundation

/// The main entry point for the md-utils CLI application.
@main
public struct CLIEntry: AsyncParsableCommand {
  /// Creates a configured instance.
  ///
  /// See <doc:md-utils> for workflow details.
  public init() {}

  public static let configuration = CommandConfiguration(
    commandName: "md-utils",
    abstract: "A utility for working with Markdown files.",
    version: "0.1.0-alpha",
    subcommands: [
      AgentCommands.self,
      Body.self,
      ConfigCommands.self,
      ConvertCommands.self,
      Explore.self,
      ExtractSection.self,
      FileMetadataCommands.self,
      FormatCommand.self,
      FrontMatterCommands.self,
      GenerateTOC.self,
      HeadingCommands.self,
      LinkCommands.self,
      Lines.self,
      OKFCommands.self,
      RulesCommands.self,
      SectionCommands.self,
      TypesCommands.self,
    ],
    helpNames: [.long, .short]
  )

  /// The main entry point for the CLI application.
  ///
  /// To call this CLI in the terminal for debugging, use: `swift run md-utils` from the package root.
  public mutating func run() async throws {
    print(Self.helpMessage())
  }
}
