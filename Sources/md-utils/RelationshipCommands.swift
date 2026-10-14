import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import PathKit
import Yams

extension CLIEntry {
  struct Relationships: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "relationships",
      abstract: "Query user-declared frontmatter assertions and structural contracts",
      subcommands: [Outgoing.self, Incoming.self, Both.self], aliases: ["rel"])

    struct Outgoing: AsyncParsableCommand {
      static let configuration = CommandConfiguration(commandName: "outgoing", abstract: "Query outgoing assertions", aliases: ["out"])
      @OptionGroup var options: RelationshipOptions
      mutating func run() async throws { try await options.run(.outgoing) }
    }
    struct Incoming: AsyncParsableCommand {
      static let configuration = CommandConfiguration(commandName: "incoming", abstract: "Query confirmed incoming assertions", aliases: ["in"])
      @OptionGroup var options: RelationshipOptions
      mutating func run() async throws { try await options.run(.incoming) }
    }
    struct Both: AsyncParsableCommand {
      static let configuration = CommandConfiguration(commandName: "both", abstract: "Query both directions with self-links in a separate section")
      @OptionGroup var options: RelationshipOptions
      mutating func run() async throws { try await options.run(.both) }
    }
  }
}

struct RelationshipOptions: ParsableArguments {
  @Argument(help: "Collection-relative document path") var file: String
  @Option(name: .long, help: "Declaring Markdown type name") var type: String
  @Option(name: .long, help: "Optional named relationship in the declaring type") var relation: String?
  @Option(name: .long, help: "Explicit collection/project root directory (for example ./vault/)") var root: String
  @Flag(name: .long, help: "Emit structured JSON evidence") var json = false
  @Flag(name: .long, help: "Emit structured YAML evidence") var yaml = false
  @Flag(name: .long, help: "Bypass the existing index") var noIndex = false
  @Flag(name: .long, help: "Refresh recorded candidates only; require registered index scopes; never discover or fall back") var indexedOnly = false
  @Flag(name: .long, help: "Hash known indexed files to detect stat-preserving changes") var verifyHashes = false
  @Option(name: .long, help: "Maximum records assessed (default 10000)") var maxRecords = 10_000
  @Option(name: .long, help: "Maximum selected occurrences (default 100000)") var maxOccurrences = 100_000

  mutating func validate() throws {
    guard !(json && yaml) else { throw ValidationError("--json and --yaml are mutually exclusive") }
    guard !(noIndex && indexedOnly) else { throw ValidationError("--no-index and --indexed-only are mutually exclusive") }
    guard maxRecords > 0, maxOccurrences > 0 else { throw ValidationError("Limits must be positive") }
    _ = try MarkdownRecordPath(file)
  }

  func run(_ direction: MarkdownRelationshipDirection) async throws {
    // Reject invalid contract selection before any automatic index refresh.
    let initialRegistry = try MarkdownTypeFileRegistryLoader.load(projectRoot: Path(root))
    guard let initialDefinition = initialRegistry.definition(named: type) else { throw ValidationError("Unknown declaring type: \(type)") }
    if let relation, initialDefinition.relationships[relation] == nil { throw ValidationError("Unknown relationship: \(type).\(relation)") }
    var limits = MarkdownRelationshipLimits()
    limits.records = maxRecords
    limits.occurrences = maxOccurrences
    let session = try await MarkdownRelationshipAssessmentSession.load(root: Path(root), noIndex: noIndex,
      indexedOnly: indexedOnly, verifyHashes: verifyHashes, limits: limits, includeRules: false,
      warning: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
    let collection = session.collection
    guard let definition = session.project.types.definition(named: type) else { throw ValidationError("Unknown declaring type: \(type)") }
    if let relation, definition.relationships[relation] == nil { throw ValidationError("Unknown relationship: \(type).\(relation)") }
    let path = try MarkdownRecordPath(file).rawValue
    guard collection.resolver.paths.contains(path) else { throw ValidationError("Document is outside available collection evidence: \(path)") }
    let sources = direction == .outgoing ? [path] : collection.records.keys.sorted()
    let roots = sources.filter { collection.records[$0] != nil }.map { ($0, definition.name) }
    guard direction != .outgoing || !roots.isEmpty else { throw ValidationError("Source record is unavailable: \(path)") }
    let evaluation = try await session.relationships(roots: roots).value
    let result = MarkdownRelationshipQuery(evaluation: evaluation, source: path, direction: direction, type: type,
      relationship: relation, identity: collection.records[path]?.identity)
    if yaml { print(try YAMLEncoder().encode(result)) }
    else if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      print(String(decoding: try encoder.encode(result), as: UTF8.self))
    } else {
      print("Stored assertions for \(path); domain meaning and truth remain user-defined.")
      for (name, occurrences) in [("Outgoing", result.outgoing), ("Incoming", result.incoming), ("Self-links", result.selfLinks)] {
        print("\(name): \(occurrences.count)")
        for occurrence in occurrences {
          print("  \(occurrence.source) \(occurrence.relationship) \(occurrence.propertyPath): \(occurrence.value) — \(occurrence.outcome.rawValue)")
        }
      }
      print("Source coverage: \(evaluation.sourcesComplete ? "complete" : "limited"); candidate coverage: \(evaluation.candidatesComplete ? "complete" : "limited")")
      for limitation in evaluation.limitations { print("  \(limitation)") }
      for assessment in evaluation.assessments {
        for diagnostic in assessment.diagnostics { print("  \(diagnostic.code): \(diagnostic.message)") }
      }
    }
  }
}
