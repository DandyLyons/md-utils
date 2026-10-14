import ArgumentParser

extension CLIEntry {
  /// Create, inspect, assess, and fix Markdown types.
  struct TypesCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "types",
      abstract: "Work with structural Markdown record types",
      discussion: "Explicit mdtype v2 definitions assert declared Date, LocalTime, DateTime, UUID, and Wikilink string formats. requires: [wikilink-constraints] enables wikilink styles (name, vault-path, relative-path, self-anchor) and independent markdownExtension policies. requires: [document-relationships] enables named frontmatter assertions and structural destination checks; use relationships (rel) for directional JSON/YAML queries with explicit --root ./vault/. Domain meaning remains user-defined. Validation never converts links. New definitions still default to v1. Quote temporal frontmatter values to store strings; recommendedSchemas produce advisories.",
      subcommands: [
        Add.self,
        Interactive.self,
        List.self,
        Describe.self,
        Doctor.self,
        Check.self,
        Verify.self,
        Identify.self,
        Find.self,
        Fix.self,
        Schema.self,
        New.self,
      ]
    )
  }
}
