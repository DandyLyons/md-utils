import ArgumentParser
import MarkdownUtilitiesServer

extension ServerEntry {
  /// Prints the canonical server configuration JSON Schema.
  struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema",
      abstract: "Print the server.yaml JSON Schema"
    )

    mutating func run() async throws {
      print(try MarkdownServerConfigurationSchema.content(), terminator: "")
    }
  }
}
