//
//  FileMetadataCommands.swift
//  md-utils
//

import ArgumentParser

extension CLIEntry {
  /// File metadata commands
  struct FileMetadataCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "meta",
      abstract: "Read file metadata",
      discussion: """
        Read file metadata including standard attributes (size, dates, permissions) \
        and extended attributes (xattr).

        Available commands:
        - read: Read metadata from files

        By default, processes directories recursively and includes extended attributes.
        """,
      subcommands: [
        ReadMetadata.self
      ]
    )
  }
}
