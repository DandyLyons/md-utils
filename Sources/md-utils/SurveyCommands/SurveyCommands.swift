import ArgumentParser
import Foundation
import MarkdownUtilitiesCore

extension CLIEntry {
  struct Survey: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "survey", abstract: SurveyHelp.introduction,
      discussion: SurveyHelp.discussion(for: "overview", isGroup: true),
      subcommands: [
        SurveyCommand<SurveyOverview>.self, SurveyCommand<SurveyCoverage>.self,
        SurveyCommand<SurveyMalformed>.self, SurveyCommand<SurveyKeys>.self,
        SurveyCommand<SurveyKey>.self, SurveyCommand<SurveyValues>.self,
        SurveyCommand<SurveyRules>.self, SurveyCommand<SurveyTypes>.self,
        SurveyCommand<SurveyStandards>.self, SurveyCommand<SurveyUncovered>.self,
        SurveyCommand<SurveyOverlaps>.self, SurveyCommand<SurveyTypeMatches>.self,
        SurveyCommand<SurveyRelationships>.self,
      ],
      defaultSubcommand: SurveyCommand<SurveyOverview>.self,
    )
  }
}

protocol SurveyMetric { static var name: String { get } }
enum SurveyOverview: SurveyMetric { static let name = "overview" }
enum SurveyCoverage: SurveyMetric { static let name = "coverage" }
enum SurveyMalformed: SurveyMetric { static let name = "malformed-fm" }
enum SurveyKeys: SurveyMetric { static let name = "keys" }
enum SurveyKey: SurveyMetric { static let name = "key" }
enum SurveyValues: SurveyMetric { static let name = "values" }
enum SurveyRules: SurveyMetric { static let name = "rules" }
enum SurveyTypes: SurveyMetric { static let name = "types" }
enum SurveyStandards: SurveyMetric { static let name = "standards" }
enum SurveyUncovered: SurveyMetric { static let name = "uncovered" }
enum SurveyOverlaps: SurveyMetric { static let name = "overlaps" }
enum SurveyTypeMatches: SurveyMetric { static let name = "type-matches" }
enum SurveyRelationships: SurveyMetric { static let name = "relationships" }

struct SurveyCommand<Metric: SurveyMetric>: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: Metric.name,
      abstract: SurveyHelp.details(for: Metric.name).abstract,
      usage: "md-utils survey \(Metric.name) \(["key", "values"].contains(Metric.name) ? "<key> " : "")[<paths> ...] [<options>]",
      discussion: SurveyHelp.discussion(for: Metric.name),
    )
  }
  @Argument(help: ArgumentHelp(
    ["key", "values"].contains(Metric.name)
      ? "Property key, followed by files or directories. Keys are literal unless --pointer is set."
      : "Files or directories to survey; defaults to the current directory when no file list is supplied.",
  )) var arguments: [String] = []
  @OptionGroup var options: SurveyOptions
  mutating func validate() throws { try options.validateRequest(metric: Metric.name, arguments: arguments) }
  mutating func run() async throws {
    let progress = options.noProgress ? nil : SurveyProgress()
    let report = try await withThrowingTaskGroup(of: Void.self) { group in
      if let progress { group.addTask { await progress.watch() } }
      defer { group.cancelAll() }
      let report = try await SurveyRunner.run(metric: Metric.name, arguments: arguments, options: options, progress: progress)
      await progress?.finish()
      return report
    }
    switch options.format {
    case .text: print(report.coloredText(overview: Metric.name == "overview"))
    case .json, .jsonPretty:
      print(try JSONReportOutput.encode(report, pretty: options.format == .jsonPretty))
    }
    if !report.complete { throw ExitCode.failure }
  }
}

/// Keep purpose, examples, and boundaries beside the generated option reference.
/// Each leaf describes its own task; the default overview also introduces the group.
enum SurveyHelp {
  static let introduction = "Understand a folder's metadata conventions, rules, and data quality before working in it."

  static func details(for name: String) -> (abstract: String, description: String, examples: String) {
    switch name {
    case "overview":
      return (introduction,
        "Get oriented in an unfamiliar collection before editing or validating it. The overview reports file coverage, relevant rules and types, common frontmatter keys, and malformed frontmatter. Observed conventions are information, not new requirements. Paths choose what to scan; --metrics chooses what to measure.",
        "md-utils survey ./notes/\nmd-utils survey overview ./notes/ --format json\nmd-utils survey ./notes/ --metrics coverage,keys\nmd-utils survey values status ./notes/")
    case "coverage":
      return ("See which files can contribute to a survey and which could not be read.",
        "Check the input population before interpreting statistics. Compare Markdown and other text files with parsed, malformed, or absent frontmatter, and see skipped non-text files and unreadable inputs.",
        "md-utils survey coverage ./notes/\nmd-utils survey coverage ./notes/ --markdown-only --format json")
    case "malformed-fm":
      return ("Find files whose frontmatter cannot be parsed so you can investigate syntax errors.",
        "List malformed YAML or TOML frontmatter with diagnostic evidence. Missing frontmatter is not malformed. Finding malformed files is a successful query; survey does not repair them. Use --fm-format to restrict the syntax and --limit 0 to show all findings.",
        "md-utils survey malformed-fm ./notes/\nmd-utils survey malformed-fm ./notes/ --fm-format yaml --limit 0")
    case "keys":
      return ("Discover common frontmatter keys and the value kinds used for them.",
        "Rank literal top-level keys by the number of documents containing each key. Start here to learn a collection's metadata conventions. The default shows ten keys; --top 0 shows all. --min-files filters uncommon keys. Use the key subcommand to investigate one property.",
        "md-utils survey keys ./notes/\nmd-utils survey keys ./notes/ --top 20 --min-files 5")
    case "key":
      return ("Inspect one property's presence and value kinds to find inconsistent metadata.",
        "Supply a property key before the paths. Missing keys and explicit null values are distinct. Keys such as author.name are literal; --pointer selects nested properties with JSON Pointer. --outliers lists minority kinds when at least 20 files contain the key and one kind accounts for at least 95%; adjust --min-files and --min-share as needed.",
        "md-utils survey key status ./notes/\nmd-utils survey key tags ./notes/ --outliers\nmd-utils survey key /author/name ./notes/ --pointer")
    case "values":
      return ("Explore a property's frequent values to learn vocabularies and distributions.",
        "Supply a property key before the paths. Values retain their kinds: a number and a quoted numeric string are distinct. Arrays count as whole values by default. --elements counts each distinct array element once per document; add --count occurrences to count repetitions. --top limits displayed values, not the scanned files. Use --pointer for nested properties.",
        "md-utils survey values status ./notes/\nmd-utils survey values tags ./notes/ --elements\nmd-utils survey values tags ./notes/ --elements --count occurrences")
    case "rules":
      return ("Find relevant rules and their referenced types before validating a folder.",
        "Inspect rule selection without running full conformance validation. Unknown applicability stays separate from confirmed matches. --rule limits the inventory. Follow the rules describe, matching, and files-matching hints to investigate. Use rules validate for conformance checks; a named rule may select files outside the surveyed folder. Snapshot-only rule inventory is not yet available.",
        "md-utils survey rules ./notes/\nmd-utils survey rules ./notes/ --rule Articles --format json")
    case "types":
      return ("Inventory type definitions to discover the structures available in a collection.",
        "List configured and locally discovered mdtypes, including definitions not referenced by rules. A definition's presence does not establish document conformance or intended usage. For an opt-in conformance assessment, use the type-matches subcommand; it can require more work. Snapshot-only type inventory is not yet available.",
        "md-utils survey types ./notes/\nmd-utils survey types ./notes/ --type Article\nmd-utils survey type-matches ./notes/ --type Article")
    case "standards":
      return ("Discover standards used by a collection (upcoming feature).",
        "This upcoming feature currently prints a short notice and exits with status 1 without scanning source files. Use rules and types to explore the contracts available today. Implementation is tracked at https://github.com/DandyLyons/md-utils/issues/202.",
        "md-utils survey standards ./notes/\nmd-utils survey rules ./notes/\nmd-utils survey types ./notes/")
    case "uncovered":
      return ("Find files no configured rule selects to understand gaps in rule coverage.",
        "Report confirmed non-selection separately from files whose applicability cannot be determined. Uncovered files are not necessarily errors: they may intentionally have no rule. This examines selection, not document conformance. Snapshot-only rule coverage is not yet available.",
        "md-utils survey uncovered ./notes/\nmd-utils survey uncovered ./notes/ --limit 0 --format json")
    case "overlaps":
      return ("Find files selected by multiple rules to understand overlapping requirements.",
        "Show overlapping rule selections without assuming they conflict. Overlap can be intentional, and selection does not prove conformance. Unknown applicability is reported separately. Snapshot-only rule coverage is not yet available.",
        "md-utils survey overlaps ./notes/\nmd-utils survey overlaps ./notes/ --limit 0 --format json")
    case "type-matches":
      return ("Assess documents against discovered types to explore possible structural matches.",
        "Opt into conformance assessment, including types that rules do not reference. A match does not declare intended usage. This can cost more than the types inventory; use --type to narrow the assessment. Unavailable evidence is distinct from nonconformance. Snapshot-only type matching is not yet available.",
        "md-utils survey type-matches ./notes/ --type Article\nmd-utils survey type-matches ./notes/ --format json")
    case "relationships":
      return ("Summarize outgoing links and named relationships to understand how documents connect.",
        "Inspect ordinary links, named relationship groups, resolution outcomes, self-links, and destinations inside or outside the selected files. Sources are Markdown only; resolution uses the full project namespace. Custom --config relationship queries are currently unavailable. For directional details, use md-utils relationships outgoing --help.",
        "md-utils survey relationships ./notes/\nmd-utils survey relationships ./notes/ --type Article --format json")
    default:
      preconditionFailure("Missing survey help for \(name)")
    }
  }

  static func discussion(for name: String, isGroup: Bool = false) -> String {
    let detail = details(for: name)
    let subcommands = name == "overview" && !isGroup ? """

    SUBCOMMANDS
      Run md-utils survey <subcommand> --help for options and examples.
      overview       General orientation (also the default without a subcommand)
      coverage       Input file counts and reading limitations
      malformed-fm   Frontmatter syntax failures
      keys           Common property keys and value kinds
      key            Presence, kinds, and outliers for one property
      values         Frequent values for one property
      rules          Relevant rules and referenced types
      types          Available type definitions
      standards      Reserved; currently unsupported
      uncovered      Files no configured rule selects
      overlaps       Files selected by multiple rules
      type-matches   Opt-in assessment against discovered types
      relationships  Outgoing links and named relationships
    """ : ""
    return """
    DESCRIPTION
      \(detail.description)

    QUICK START
      \(name == "overview" ? "md-utils survey [<paths> ...] [<options>]\n  md-utils survey <subcommand> [<arguments> ...] [<options>]" : "md-utils survey \(name) \(["key", "values"].contains(name) ? "<key> " : "")[<paths> ...] [<options>]")

    EXAMPLES
      \(detail.examples.replacingOccurrences(of: "\n", with: "\n  "))
    \(subcommands)

    SCOPE AND CONFIGURATION
      Defaults to the current directory, recursively including Markdown and
      supported UTF-8 text. Hidden entries and symlinks are skipped.
      Run examples from your project root; --project-root sets its boundary.
      --config overrides <project-root>/.md-utils/md-utils.json.
      \(["rules", "types", "type-matches", "relationships"].contains(name) ? "Replace example type/rule names with definitions from your project." : "No configured types or rules are needed for frontmatter statistics.")

    OUTPUT AND CACHE
      --format text (default), json (compact), or json-pretty selects output.
      Results go to stdout; diagnostics go to stderr. Both JSON forms contain
      identical data and no terminal colors.
      Slow work shows delayed phase/count feedback on stderr; --no-progress
      suppresses it. The text overview is a short summary; use focused
      subcommands for details. Investigation hints are limited to three.
      Source files are not edited. Recursive directory surveys refresh an
      existing cache; no index is created. --no-index bypasses it.
      --index-only reads stored evidence without refresh or source fallback.

    EXIT STATUS
      0  Analysis completed, including findings such as malformed frontmatter.
         Rule-selection uncertainty is a finding; inspect its file/reason details.
      1  Analysis incomplete or unsupported; inspect the reported limitations.
      64 Invalid command usage.

    LEARN MORE
      md-utils help survey
      md-utils survey <subcommand> --help
      Workflow guide: https://github.com/DandyLyons/md-utils/blob/main/skill/markdown-utilities/skills/markdown-utilities/references/survey.md
    """
  }
}

struct SurveyOptions: ParsableArguments {
  @Option(help: "Project boundary; defaults to working directory") var projectRoot: String?
  @Option(help: "Project configuration; defaults to <root>/.md-utils/md-utils.json") var config: String?
  @Flag(inversion: .prefixedNo, help: "Recurse into directories") var recursive = true
  @Flag(help: "Survey Markdown files only") var markdownOnly = false
  @Option(help: "Project-relative path/glob to exclude; repeatable") var exclude: [String] = []
  @Option(help: "UTF-8 LF-delimited project-relative files; - reads stdin") var filesFrom: [String] = []
  @Option(name: .customLong("files-from0"), help: "UTF-8 NUL-delimited project-relative files") var filesFrom0: [String] = []
  @Option(help: "Overview only: comma-separated coverage, malformed-fm, keys, rules, types, standards, uncovered, overlaps, type-matches, or relationships; repeatable; replaces defaults") var metrics: [String] = []
  @Option(help: "Output format: text, json (compact), or json-pretty") var format: ReportOutputFormat = .text
  @Option(help: "Ranked keys/values to display; 0 means all") var top = 10
  @Option(help: "Detailed rows to display; 0 means all") var limit = 20
  @Option(help: "Minimum files: keys default 1, outliers default 20") var minFiles: Int?
  @Option(help: "Dominant-kind share for outliers, greater than 0.5 through 1") var minShare = 0.95
  @Flag(help: "key only: show minority-kind outlier file paths") var outliers = false
  @Flag(help: "key/values only: interpret the key as JSON Pointer") var pointer = false
  @Flag(help: "values only: count immediate array elements instead of whole values") var elements = false
  @Option(help: "documents or occurrences; occurrences requires --elements") var count = "documents"
  @Option(help: "malformed-fm only: filter by yaml or toml") var fmFormat: String?
  @Option(help: "overview/types/type-matches/relationships: limit types by name; repeatable") var type: [String] = []
  @Option(help: "overview/rules: limit rule inventory by name; repeatable") var rule: [String] = []
  @Flag(help: "Suppress investigation hints") var noHints = false
  @Flag(help: "Suppress delayed analysis progress on stderr") var noProgress = false
  @Flag(help: "Bypass the project index") var noIndex = false
  @Flag(name: [.long, .customLong("indexed-only")], help: "Published SQLite evidence only; no source reads or fallback") var indexOnly = false
  @Flag(help: "Detect stat-preserving edits during indexed refresh") var verifyHashes = false
  @Option(help: "Maximum selected text files; exhaustion is incomplete") var maxFiles = DocumentReadBudgets.files

  func validateRequest(metric: String, arguments: [String]) throws {
    guard top >= 0, limit >= 0, maxFiles > 0, (minFiles ?? 1) > 0,
      minShare.isFinite, minShare > 0.5, minShare <= 1 else { throw ValidationError("Invalid survey limit or threshold") }
    guard !indexOnly || (!noIndex && !verifyHashes) else { throw ValidationError("--index-only rejects --no-index and --verify-hashes") }
    guard ["documents", "occurrences"].contains(count), count != "occurrences" || elements else {
      throw ValidationError("--count occurrences requires --elements")
    }
    guard fmFormat == nil || ["yaml", "toml"].contains(fmFormat ?? "") else { throw ValidationError("--fm-format must be yaml or toml") }
    guard !["key", "values"].contains(metric) || !arguments.isEmpty else { throw ValidationError("\(metric) requires a property key") }
    guard metrics.isEmpty || metric == "overview" else { throw ValidationError("--metrics is only valid on the overview") }
    guard metrics.flatMap({ $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }).allSatisfy(SurveyRunner.available.contains) else {
      throw ValidationError("Unknown survey metric")
    }
    guard !elements || metric == "values", !outliers || metric == "key",
      !pointer || ["key", "values"].contains(metric), fmFormat == nil || metric == "malformed-fm",
      rule.isEmpty || metric == "rules" || metric == "overview",
      type.isEmpty || ["types", "type-matches", "relationships", "overview"].contains(metric) else {
      throw ValidationError("Option is not applicable to survey \(metric)")
    }
    guard (filesFrom + filesFrom0).filter({ $0 == "-" }).count <= 1 else { throw ValidationError("stdin may be read only once") }
    if pointer, let key = arguments.first { _ = try SurveyPointerParser.components(key) }
  }
}
