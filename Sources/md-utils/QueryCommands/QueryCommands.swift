import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit

extension CLIEntry {
  struct Query: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "query", abstract: "Find documents matching metadata, type, or rule conditions.",
      discussion: QueryFilter.discussion,
      subcommands: [QueryFilter.self, Relationships.self], defaultSubcommand: QueryFilter.self,
    )
  }
}

struct QueryFilter: AsyncParsableCommand {
  static let discussion = """
    Find document paths; nested selectors still return whole document matches.
    String values match without regard to case by default; keys remain literal.

    EXAMPLES
      md-utils query notes/ --key Status --equals 'Read'
      md-utils query notes/ --json-path '$.authors[*].name' --equals 'Daniel'
      md-utils query notes/ --missing-key Status \\
        --output frontmatter --oformat json
      md-utils query notes/ --key Created --vformat DateTime \\
        --same-day '2026-10-28'

    SCOPE
      Files/folders form a deduplicated union; directories recurse by default.
      CLI paths use the working directory; file-list entries use --project-root.
      YAML/TOML and supported text hosts are included.
      Use --markdown-only to include just Markdown files.
      Hidden entries and symlinks are skipped. No source files are edited.
      Existing indexes may refresh; --no-index bypasses them. --index-only reads
      published evidence without source fallback; type/rule queries reject it.

    OUTPUT
      --output paths|frontmatter|count chooses content; --oformat chooses encoding.
      JSON contains results and execution context. Progress goes to stderr.
      --limit bounds display in path order, not date order or evaluation.
      For newest results, retrieve all candidates with --limit 0, then sort dates.
      Calendar comparisons default to the device timezone and Sunday weeks.

    SUBCOMMANDS
      filter (default)   Find documents using the options below.
      relationships, rel   Existing outgoing/out, incoming/in, and both queries.

    EXIT STATUS
      0  Completed, including no matches and display-limit truncation.
      1  Incomplete assessment; confirmed matches are retained.
      64 Invalid usage, rejected before scanning.

    LEARN MORE
      md-utils query rel --help
      https://github.com/DandyLyons/md-utils/blob/main/docs/query-design.md
    """
  static let configuration = CommandConfiguration(commandName: "filter", abstract: "Find matching documents.", discussion: discussion)
  @Argument(help: "Files/folders; defaults to current directory") var paths: [String] = []
  @Option(help: "Literal top-level property") var key: String?
  @Option(help: "JSONPath using members, indices, and wildcards") var jsonPath: String?
  @Option(help: "Equal to this value") var equals: String?
  @Option(help: "Present eligible value unequal to this value") var notEquals: String?
  @Option(help: "Array contains this value") var contains: String?
  @Option(help: "Conforms to the named mdtype's required contracts") var isType: String?
  @Option(help: "Selected by the named mdrule, independent of conformance") var inRule: String?
  @Flag(help: "At least one selected node exists") var exists = false
  @Flag(help: "No selected node exists") var missing = false
  @Flag(help: "Selected value is explicitly null") var isNull = false
  @Option(help: "Literal-key presence shorthand") var hasKey: String?
  @Option(help: "Literal-key absence shorthand") var missingKey: String?
  @Option(help: "Exclusive numeric or temporal lower bound") var greaterThan: String?
  @Option(help: "Inclusive numeric or temporal lower bound") var greaterThanOrEqual: String?
  @Option(help: "Exclusive numeric or temporal upper bound") var lessThan: String?
  @Option(help: "Inclusive numeric or temporal upper bound") var lessThanOrEqual: String?
  @Option(help: "Same calendar day as reference date") var sameDay: String?
  @Option(help: "Same calendar week as reference date") var sameWeek: String?
  @Option(help: "Same calendar month as reference date") var sameMonth: String?
  @Option(help: "Same calendar year as reference date") var sameYear: String?
  @Option(help: "Before a date or timestamp") var before: String?
  @Option(help: "After a date or timestamp") var after: String?
  @Option(help: "local (default), UTC, or named timezone") var timezone = "local"
  @Option(help: "timezone (default) or written calendar components") var dateMode = "timezone"
  @Option(help: "sunday (default) or monday") var weekStart = "sunday"
  @Option(name: [.long, .customLong("vtype")], help: "string, boolean, integer, number, null, array, object") var valueType = "string"
  @Option(name: [.long, .customLong("vformat")], help: "Date, LocalTime, DateTime, UUID, Wikilink or full format name") var valueFormat: String?
  @Option(help: "any (default) or all selected values; all requires a nonempty selection") var match: String?
  @Flag(help: "Compare text case-sensitively") var caseSensitive = false
  @Flag(help: "Compare text case-insensitively (default)") var caseInsensitive = false
  @Option(help: "paths, frontmatter, or count") var output = "paths"
  @Option(name: [.long, .customLong("oformat")], help: "text, json, or json-pretty") var outputFormat: ReportOutputFormat = .text
  @Flag(name: .customLong("print0"), help: "NUL-separated paths; requires text path output") var print0 = false
  @Option(help: "Result list limit; 0 means all") var limit = 20
  @Option(help: "Diagnostic entry limit; 0 means all; never stops evaluation") var diagnosticLimit = 100
  @OptionGroup var scope: QueryScope

  func compile() throws -> MarkdownQueryPredicate {
    guard !(caseSensitive && caseInsensitive), ["paths", "frontmatter", "count"].contains(output),
      !print0 || (output == "paths" && outputFormat == .text), limit >= 0, diagnosticLimit >= 0,
      match == nil || ["any", "all"].contains(match ?? "") else { throw ValidationError("Conflicting query options or invalid limits") }
    try scope.validate()
    guard ["timezone", "written"].contains(dateMode), ["sunday", "monday"].contains(weekStart),
      timezone == "local" || TimeZone(identifier: timezone) != nil else { throw ValidationError("Invalid timezone, date mode, or week start") }
    guard greaterThan == nil || greaterThanOrEqual == nil, lessThan == nil || lessThanOrEqual == nil else { throw ValidationError("Supply only one lower and one upper bound") }
    let lower = greaterThan.map { ($0, false) } ?? greaterThanOrEqual.map { ($0, true) }
    let upper = lessThan.map { ($0, false) } ?? lessThanOrEqual.map { ($0, true) }
    let operations: [(String, String?)] = [
      ("equals", equals), ("not-equals", notEquals), ("contains", contains),
      ("exists", exists || hasKey != nil ? "" : nil), ("missing", missing || missingKey != nil ? "" : nil),
      ("is-null", isNull ? "" : nil), ("range", lower != nil || upper != nil ? "" : nil),
      ("same-day", sameDay), ("same-week", sameWeek), ("same-month", sameMonth), ("same-year", sameYear),
      ("before", before), ("after", after),
      ("is-type", isType), ("in-rule", inRule),
    ].filter { $0.1 != nil }
    guard operations.count == 1, let operation = operations.first else { throw ValidationError("Supply exactly one query condition (or one lower/upper range)") }
    if isType != nil || inRule != nil {
      guard [key, jsonPath, hasKey, missingKey, match, valueFormat].allSatisfy({ $0 == nil }), valueType == "string", !scope.indexOnly else { throw ValidationError("Type/rule conditions are standalone and do not support --index-only in v1") }
      return try MarkdownQueryPredicate(key: "", jsonPath: nil, operation: "exists", operand: nil)
    }
    guard [key, jsonPath, hasKey, missingKey].compactMap({ $0 }).count == 1,
      !(hasKey != nil && exists), !(missingKey != nil && missing),
      match == nil || !["exists", "missing"].contains(operation.0) else { throw ValidationError("Conflicting selector or --match options") }
    do {
      return try MarkdownQueryPredicate(key: key ?? hasKey ?? missingKey, jsonPath: jsonPath,
        operation: operation.0, operand: ["exists", "missing", "is-null", "range"].contains(operation.0) ? nil : operation.1,
        domain: valueType, format: valueFormat, all: match == "all", caseSensitive: caseSensitive, lower: lower, upper: upper,
        timezone: timezone == "local" ? .current : TimeZone(identifier: timezone) ?? .current, written: dateMode == "written", monday: weekStart == "monday",
      )
    } catch { throw ValidationError(String(describing: error)) }
  }
  mutating func validate() throws { _ = try compile() }
  mutating func run() async throws {
    let predicate = try compile()
    let progress = scope.noProgress ? nil : AnalysisProgress()
    let report = try await withThrowingTaskGroup(of: Void.self) { group in
      if let progress { group.addTask { await progress.watch() } }
      defer { group.cancelAll() }
      let report = try await QueryRunner.run(self, predicate: predicate, progress: progress)
      await progress?.finish()
      return report
    }
    if outputFormat != .text { print(try JSONReportOutput.encode(report, pretty: outputFormat == .jsonPretty)) }
    else if output == "count" { print(CLIStyle.exploreLabel(String(report.summary.matched))) }
    else if output == "paths" {
      for path in report.returnedPaths {
        if print0 { FileHandle.standardOutput.write(Data((path + "\0").utf8)) }
        else { print(CLIStyle.path(Self.visible(path))) }
      }
    } else { print(try report.frontmatterText()) }
    if report.summary.omitted > 0 { Self.warn("\(report.summary.omitted) matching paths omitted; use --limit 0 for all") }
    if !report.complete {
      for diagnostic in report.diagnostics.prefix(3) { Self.warn(Self.visible(diagnostic.path) + ": " + Self.visible(diagnostic.message)) }
      Self.warn("Query incomplete; \(report.summary.unknown) files could not be assessed. Use --oformat json for full context.")
      throw ExitCode.failure
    }
  }
  static func warn(_ text: String) { CLIStyle.writeWarning(text) }
  static func visible(_ text: String) -> String {
    text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? $0.escaped(asASCII: true) : String($0) }.joined()
  }
}

struct QueryScope: ParsableArguments {
  @Option(help: "Project boundary; defaults to working directory") var projectRoot: String?
  @Option(help: "Project configuration") var config: String?
  @Flag(inversion: .prefixedNo, help: "Recurse into directories") var recursive = true
  @Flag(help: "Include Markdown files only") var markdownOnly = false
  @Option(help: "Project-relative path/glob exclusions; repeatable") var exclude: [String] = []
  @Option(help: "UTF-8 LF-delimited root-relative file list; - for stdin") var filesFrom: [String] = []
  @Option(name: .customLong("files-from0"), help: "UTF-8 NUL-delimited root-relative file list") var filesFrom0: [String] = []
  @Flag(help: "Suppress delayed progress") var noProgress = false
  @Flag(help: "Bypass the project index") var noIndex = false
  @Flag(name: [.long, .customLong("indexed-only")], help: "Published SQLite evidence only; no fallback") var indexOnly = false
  @Flag(help: "Verify source hashes when refreshing cache") var verifyHashes = false
  @Option(help: "Maximum selected text files") var maxFiles = DocumentReadBudgets.files
  func validate() throws {
    guard maxFiles > 0, !indexOnly || (!noIndex && !verifyHashes), (filesFrom + filesFrom0).filter({ $0 == "-" }).count <= 1 else { throw ValidationError("Invalid query scope options") }
  }
  func surveyOptions() throws -> SurveyOptions {
    var options = try SurveyOptions.parse([])
    options.projectRoot = projectRoot; options.config = config; options.recursive = recursive
    options.markdownOnly = markdownOnly; options.exclude = exclude; options.maxFiles = maxFiles
    return options
  }
}
