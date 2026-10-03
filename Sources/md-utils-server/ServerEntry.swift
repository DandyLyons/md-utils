import ArgumentParser
import Foundation

/// Native HTTP service and offline contract tooling for configured Markdown resources.
@main
struct ServerEntry: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "md-utils-server",
    abstract: "Serve configured Markdown resources or manage their server contract.",
    version: buildVersion,
    subcommands: [Serve.self, Init.self, Schema.self, OpenAPIExport.self],
    defaultSubcommand: Serve.self,
  )

  /// Artifact version, independent of server configuration schema versions.
  static let buildVersion: String = {
    guard let url = Bundle.module.url(forResource: "BuildVersion", withExtension: "txt"),
      let value = try? String(contentsOf: url, encoding: .utf8)
    else { return "development" }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }()
}
