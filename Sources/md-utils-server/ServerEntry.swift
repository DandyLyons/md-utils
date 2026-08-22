import ArgumentParser

/// Native read-only HTTP distribution for explicitly configured Markdown resources.
@main
struct ServerEntry: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "md-utils-server",
    abstract: "Serve configured Markdown resources through a read-only HTTP API.",
    version: "0.1.0-alpha",
    subcommands: [Serve.self, Init.self, Schema.self],
    defaultSubcommand: Serve.self
  )
}
