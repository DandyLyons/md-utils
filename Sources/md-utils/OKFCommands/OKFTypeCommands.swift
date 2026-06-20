//
//  OKFTypeCommands.swift
//  md-utils
//

import ArgumentParser
import PathKit

extension CLIEntry.OKFCommands {
  /// Groups OKF type helper commands.
  struct TypeCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "type",
      abstract: "EXPERIMENTAL: Manage OKF concept type frontmatter values",
      subcommands: [SetType.self]
    )
  }
}

extension CLIEntry.OKFCommands.TypeCommands {
  /// Sets a user-provided OKF type on matching concept documents.
  struct SetType: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "set",
      abstract: "EXPERIMENTAL: Set OKF type on matching concept documents",
      discussion: """
        EXPERIMENTAL: OKF type tooling is likely to change as the OKF spec changes.

        Sets the OKF frontmatter type field to an explicit user-provided value.
        The command never guesses types. If --dir is omitted, the current directory is scanned recursively.

        Examples:
          md-utils okf type set --type=Book
          md-utils okf type set --type=Book --array-key=tags --array-contains=Books
          md-utils okf type set --type=BigQueryTable --dir=./knowledge/tables/
        """
    )

    @Option(name: .long, help: "Type value to write")
    var type: String

    @Option(name: .long, help: "Directory to scan recursively; defaults to the current directory", completion: .directory, transform: { Path($0) })
    var dir: Path?

    @Option(name: .long, help: "Frontmatter array key used to filter files, for example tags")
    var arrayKey: String?

    @Option(name: .long, help: "Required string value in the frontmatter array filter")
    var arrayContains: String?

    mutating func run() async throws {
      let timer = CommandTimer()
      let options = OKFTypeSetOptions(
        directory: dir ?? .current,
        type: type,
        arrayKey: arrayKey,
        arrayContains: arrayContains
      )
      let summary = try OKFTypeSetter.setType(options: options)
      print(OKFTypeSetFormatter.render(summary))
      timer.writeStatus("Updated \(summary.updatedFiles.count) OKF concept document(s)")
    }
  }
}
