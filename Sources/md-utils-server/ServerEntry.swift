import ArgumentParser

/// Native HTTP service and offline contract tooling for configured Markdown resources.
@main
struct ServerEntry: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "md-utils-server",
    abstract: "Serve configured Markdown resources or manage their server contract.",
    version: "0.1.0-alpha",
    subcommands: [Serve.self, Init.self, Schema.self, OpenAPIExport.self],
    defaultSubcommand: Serve.self
  )
}
