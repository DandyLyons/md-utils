import ArgumentParser

extension CLIEntry {
  /// Output format for the explore command.
  enum ExploreFormat: String, ExpressibleByArgument {
    case terminal
    case markdown
    case markdownNoStubs = "markdown-no-stubs"
  }
}
