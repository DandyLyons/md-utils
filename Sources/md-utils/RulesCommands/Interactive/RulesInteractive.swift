import ArgumentParser

extension CLIEntry.RulesCommands {
  struct Interactive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "interactive",
      abstract: "Create, edit, or remove a 0.3.0 rule interactively")
    @Option(name: .long, help: "Exact rule name to edit or remove") var edit: String?
    @OptionGroup var project: RuleProjectOptions

    mutating func run() async throws {
      guard let standalone = try project.load().standaloneProject else {
        throw ValidationError("rules interactive requires configVersion 0.3.0")
      }
      try InteractiveAuthoring(prompts: .terminal()).run(types: false, selectedName: edit, root: standalone.projectRoot)
    }
  }
}
