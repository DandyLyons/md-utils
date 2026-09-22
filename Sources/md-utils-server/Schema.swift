import ArgumentParser
import MarkdownUtilitiesServer

extension ServerEntry {
  /// Prints the canonical server configuration JSON Schema.
  struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema",
      abstract: "Print the server.yaml JSON Schema"
    )

    @Option(name: .long, help: "Server configuration schema version: 1 or 2.")
    var schemaVersion = "1"

    mutating func run() async throws {
      guard ["1", "2"].contains(schemaVersion) else { throw ValidationError("schema-version must be 1 or 2") }
      print(try MarkdownServerConfigurationSchema.content(version: schemaVersion), terminator: "")
    }
  }
}
