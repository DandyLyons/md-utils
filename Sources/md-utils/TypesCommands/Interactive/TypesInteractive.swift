import ArgumentParser

extension CLIEntry.TypesCommands {
  struct Interactive: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "interactive",
      abstract: "Create, edit, or remove a 0.3.0 Markdown type interactively")
    @Option(name: .long, help: "Exact declared type name to edit or remove") var name: String?
    @OptionGroup var project: RuleProjectOptions

    mutating func run() async throws {
      guard let standalone = try project.load().standaloneProject else {
        throw ValidationError("types interactive requires configVersion 0.3.0")
      }
      try InteractiveAuthoring(prompts: .terminal()).run(types: true, selectedName: name, root: standalone.projectRoot)
    }
  }
}
