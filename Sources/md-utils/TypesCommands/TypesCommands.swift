import ArgumentParser

extension CLIEntry {
  /// Create, inspect, assess, and fix Markdown types.
  struct TypesCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "types",
      abstract: "Work with structural Markdown record types",
      subcommands: [
        Init.self,
        Create.self,
        List.self,
        Describe.self,
        Doctor.self,
        Check.self,
        Verify.self,
        Identify.self,
        Find.self,
        Fix.self,
        Schema.self,
      ]
    )
  }
}
