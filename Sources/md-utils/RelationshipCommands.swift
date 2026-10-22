import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import PathKit
import Yams

extension CLIEntry {
  struct Relationships: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "relationships",
      abstract: "Query named relationships and ordinary links across selected Markdown files",
      discussion: RelationshipOptions.helpDiscussion,
      subcommands: [Outgoing.self, Incoming.self, Both.self], aliases: ["rel"])
    struct Outgoing: AsyncParsableCommand {
      static let configuration = CommandConfiguration(commandName: "outgoing", abstract: "Query outgoing relationships and links", discussion: RelationshipOptions.helpDiscussion, aliases: ["out"])
      @OptionGroup var options: RelationshipOptions
      mutating func run() async throws { try await options.run(.outgoing) }
    }
    struct Incoming: AsyncParsableCommand {
      static let configuration = CommandConfiguration(commandName: "incoming", abstract: "Find incoming sources throughout the root", discussion: RelationshipOptions.helpDiscussion, aliases: ["in"])
      @OptionGroup var options: RelationshipOptions
      mutating func run() async throws { try await options.run(.incoming) }
    }
    struct Both: AsyncParsableCommand {
      static let configuration = CommandConfiguration(commandName: "both", abstract: "Query both directions, with separate self-links", discussion: RelationshipOptions.helpDiscussion)
      @OptionGroup var options: RelationshipOptions
      mutating func run() async throws { try await options.run(.both) }
    }
  }
}

struct RelationshipOptions: ParsableArguments {
  /// Selection and snapshot semantics shared by every directional help page.
  static let helpDiscussion = """
    --root is required. Positional files and folder selectors are collection-relative.
    Supply at least one selector; --select-folder . selects the entire collection.
    Multiple selectors require --select-mode union|intersection. All positional
    paths and file lists together form one selector. Exclusions subtract afterward.
    --type overrides declaring contracts; --relation requires --type.

    Text is the default; --json and --yaml are mutually exclusive. --detail
    summary|explain|evidence affects presentation only. Complete queries exit 0
    even for broken/nonconforming assertions; incomplete queries exit 1 with
    available results. Incoming sources are searched throughout the root.

    Live outgoing queries read selected sources and dependencies without a whole-
    collection index refresh. Incoming/both refresh an existing compatible index;
    --no-index bypasses it. --index-only
    (alias --indexed-only) reads only the published SQLite snapshot, without
    source/configuration/schema reads, refresh, writes or fallback. It rejects
    --no-index and --verify-hashes; missing evidence remains unavailable.
    Snapshot JMESPath selection is unavailable without full-body envelope evidence.

    Example: md-utils rel out Note.md --root ./vault/ --json
    Example: md-utils rel in --select-folder notes/ --root ./vault/ --detail explain
    """

  @Argument(help: "Collection-relative Markdown paths forming one supplied file set") var files: [String] = []
  @Option(name: .long, help: "UTF-8 LF-delimited path list; - reads stdin once") var filesFrom: [String] = []
  @Option(name: .customLong("files-from0"), help: "UTF-8 NUL-delimited path list; - reads stdin once") var filesFrom0: [String] = []
  @Option(name: .long, help: "Recursive collection-relative folder (use . for the entire root)") var selectFolder: [String] = []
  @Option(name: .long, help: "Select structural type conformance") var selectType: [String] = []
  @Option(name: .long, help: "Select unconditional positive requirements from applicable rules, even when failing") var selectRequiredType: [String] = []
  @Option(name: .long, help: "Select rule applicability, including failed checks") var selectRule: [String] = []
  @Option(name: .long, help: "Select exact case-sensitive YAML tags array membership") var selectTag: [String] = []
  @Option(name: .long, help: "JMESPath over path, frontmatterFormat, frontmatter and body; skips TOML") var selectJmespath: [String] = []
  @Option(name: .long, help: "Required for multiple selectors: union or intersection") var selectMode: String?
  @Option(name: .long, help: "Subtract a collection-relative Markdown file") var excludeFile: [String] = []
  @Option(name: .long, help: "Subtract a recursive collection-relative folder") var excludeFolder: [String] = []
  @Option(name: .long, help: "Subtract structural type matches") var excludeType: [String] = []
  @Option(name: .long, help: "Subtract rule applicability matches") var excludeRule: [String] = []
  @Option(name: .long, help: "Subtract exact YAML tags") var excludeTag: [String] = []
  @Option(name: .long, help: "Explicit declaring-contract override; repeatable") var type: [String] = []
  @Option(name: .long, help: "Filter named relationships; requires --type; ordinary links remain visible") var relation: String?
  @Option(name: .long, help: "Explicit collection/project root directory, for example ./vault/") var root: String
  @Option(name: .long, help: "summary, explain, or evidence; applies to text, JSON and YAML") var detail = "summary"
  @Flag(name: .long, help: "Emit one JSON document at the selected detail level") var json = false
  @Flag(name: .long, help: "Emit one YAML document at the selected detail level") var yaml = false
  @Flag(name: .long, help: "Bypass the existing index") var noIndex = false
  @Flag(name: [.long, .customLong("index-only")], help: "Use only the published SQLite snapshot; no raw-file reads, refresh, or fallback") var indexedOnly = false
  @Flag(name: .long, help: "Hash known indexed files to detect stat-preserving changes") var verifyHashes = false
  @Option(name: .long, help: "Maximum records assessed") var maxRecords = 10_000
  @Option(name: .long, help: "Maximum link occurrences per extraction phase") var maxOccurrences = 100_000

  mutating func validate() throws {
    guard !(json && yaml) else { throw ValidationError("--json and --yaml are mutually exclusive") }
    guard !(noIndex && indexedOnly) else { throw ValidationError("--no-index and --indexed-only are mutually exclusive") }
    guard !(verifyHashes && indexedOnly) else { throw ValidationError("--index-only and --verify-hashes are mutually exclusive") }
    guard maxRecords > 0, maxOccurrences > 0 else { throw ValidationError("Limits must be positive") }
    guard MarkdownQueryDetail(rawValue: detail) != nil else { throw ValidationError("--detail requires summary, explain, or evidence") }
    guard selectMode == nil || MarkdownSelectionMode(rawValue: selectMode ?? "") != nil else { throw ValidationError("--select-mode requires union or intersection") }
    guard relation == nil || !type.isEmpty else { throw ValidationError("--relation requires explicit --type") }
    guard (filesFrom + filesFrom0).filter({ $0 == "-" }).count <= 1 else { throw ValidationError("stdin may be consumed only once") }
    let count = selectorCount
    guard count > 0 else { throw ValidationError("Select files or use --select-folder . to select the collection") }
    guard count == 1 || selectMode != nil else { throw ValidationError("Multiple selectors require --select-mode union|intersection") }
  }

  private var selectorCount: Int {
    (files.isEmpty && filesFrom.isEmpty && filesFrom0.isEmpty ? 0 : 1)
      + selectFolder.count + selectType.count + selectRequiredType.count + selectRule.count + selectTag.count + selectJmespath.count
  }

  func request(_ direction: MarkdownRelationshipDirection) throws -> MarkdownCollectionQueryRequest {
    var selectors: [MarkdownDocumentSelector] = []
    var paths = files
    var bytes = files.reduce(0) { $0 + $1.utf8.count }
    let maximumBytes = 8 * 1_024 * 1_024
    let maximumEntries = 100_000
    for (file, nul) in filesFrom.map({ ($0, false) }) + filesFrom0.map({ ($0, true) }) {
      let handle = file == "-" ? FileHandle.standardInput : try FileHandle(forReadingFrom: URL(fileURLWithPath: file))
      defer { if file != "-" { try? handle.close() } }
      var data = Data()
      while true {
        guard bytes <= maximumBytes else { throw ValidationError("File-set input exceeds 8 MiB") }
        let chunk = try handle.read(upToCount: min(65_536, maximumBytes - bytes + 1)) ?? Data()
        if chunk.isEmpty { break }
        data.append(chunk); bytes += chunk.count
      }
      guard let text = String(data: data, encoding: .utf8) else { throw ValidationError("File list \(file) is not valid UTF-8") }
      // No special BOM acceptance/rejection policy is introduced here; #189 owns it.
      var input = text[...]
      paths += try MarkdownQueryFileListParser(nulDelimited: nul).parse(&input)
      guard paths.count <= maximumEntries else { throw ValidationError("File-set input exceeds 100000 entries") }
    }
    guard bytes <= maximumBytes, paths.count <= maximumEntries else { throw ValidationError("File-set input limit exceeded") }
    func path(_ value: String) throws -> String {
      guard !value.contains("\0") else { throw ValidationError("Document paths cannot contain NUL") }
      let normalized = try MarkdownRecordPath(value).rawValue
      guard ["md", "markdown"].contains(Path(normalized).extension?.lowercased() ?? ""),
        indexedOnly || !(Path(root) + normalized).isDirectory else {
        throw ValidationError("Select Markdown files only; use --select-folder for directories: \(value)")
      }
      return normalized
    }
    func folder(_ value: String) throws -> String {
      if value == "." || value == "./" { return "" }
      let withoutSlash = value.hasSuffix("/") ? String(value.dropLast()) : value
      return try MarkdownRecordPath(withoutSlash).rawValue + "/"
    }
    if !files.isEmpty || !filesFrom.isEmpty || !filesFrom0.isEmpty { selectors.append(.files(Set(try paths.map(path)))) }
    selectors += try selectFolder.map { .folder(try folder($0)) }
    selectors += selectType.map(MarkdownDocumentSelector.type)
    selectors += selectRequiredType.map(MarkdownDocumentSelector.requiredType)
    selectors += selectRule.map(MarkdownDocumentSelector.rule)
    selectors += selectTag.map(MarkdownDocumentSelector.tag)
    selectors += selectJmespath.map(MarkdownDocumentSelector.jmespath)
    var exclusions: [MarkdownDocumentSelector] = []
    if !excludeFile.isEmpty { exclusions.append(.files(Set(try excludeFile.map(path)))) }
    exclusions += try excludeFolder.map { .folder(try folder($0)) }
    exclusions += excludeType.map(MarkdownDocumentSelector.type)
    exclusions += excludeRule.map(MarkdownDocumentSelector.rule)
    exclusions += excludeTag.map(MarkdownDocumentSelector.tag)
    return .init(direction: direction, selectors: selectors, exclusions: exclusions,
      mode: MarkdownSelectionMode(rawValue: selectMode ?? "union") ?? .union,
      types: Array(Set(type)).sorted(), relation: relation, detail: MarkdownQueryDetail(rawValue: detail) ?? .summary)
  }

  func run(_ direction: MarkdownRelationshipDirection) async throws {
    let request = try request(direction)
    var limits = MarkdownRelationshipLimits()
    limits.records = maxRecords; limits.occurrences = maxOccurrences
    let query = try await MarkdownCollectionQuerySession.run(request, root: Path(root), noIndex: noIndex,
      indexedOnly: indexedOnly, verifyHashes: verifyHashes, limits: limits, warning: CLIStyle.writeWarning)
    if yaml { print(try YAMLEncoder().encode(query.result)) }
    else if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      print(String(decoding: try encoder.encode(query.result), as: UTF8.self))
    } else { print(RelationshipQueryRenderer.render(query.result)) }
    if !query.complete { throw ExitCode.failure }
  }
}
