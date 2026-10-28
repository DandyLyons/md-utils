import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilities
import MarkdownUtilitiesIndexNative
import PathKit

struct QueryReport: Encodable {
  struct Summary: Encodable {
    var matched = 0, nonmatched = 0, unknown = 0, skipped = 0, returned = 0, omitted = 0
    var diagnosticTotal = 0, diagnosticFiles = 0, diagnosticsOmitted = 0
  }
  struct Diagnostic: Encodable { var path: String; var code: String; var message: String }
  var schemaVersion = 1
  var query: [String: JSONValue]
  var scope: [String: JSONValue]
  var execution: [String: JSONValue] = [:]
  var complete = true
  var summary = Summary()
  var results: [String: JSONValue] = [:]
  var diagnostics: [Diagnostic] = []
  var returnedPaths: [String] = []
  enum CodingKeys: String, CodingKey { case schemaVersion, query, scope, execution, complete, summary, results, diagnostics }

  /// Human frontmatter output keeps each mapping attached to its source path.
  func frontmatterText() throws -> String {
    var lines: [String] = []
    if case .array(let entries) = results["frontMatter"] {
      for entry in entries {
        guard let fields = entry.objectValue else { continue }
        lines.append(CLIStyle.path(QueryFilter.visible(fields["path"]?.stringValue ?? "")))
        for (key, value) in (fields["frontmatter"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
          lines.append("  \(CLIStyle.schemaDescribeFieldName(QueryFilter.visible(key))): \(try JSONReportOutput.encode(value, pretty: false))")
        }
      }
    }
    for (category, label) in [("noFrontMatter", "no frontmatter"), ("emptyFrontMatter", "empty frontmatter"), ("unavailable", "frontmatter unavailable")] {
      if case .array(let entries) = results[category] {
        for entry in entries {
          let path = CLIStyle.path(QueryFilter.visible(entry.stringValue ?? entry.objectValue?["path"]?.stringValue ?? ""))
          let status = category == "unavailable" ? CLIStyle.warning(label) : CLIStyle.muted(label)
          lines.append(path + " (\(status))")
        }
      }
    }
    return lines.isEmpty ? CLIStyle.muted("No matching documents.") : lines.joined(separator: "\n")
  }
}

enum QueryRunner {
  static func run(
    _ command: QueryFilter, predicate: MarkdownQueryPredicate, progress: AnalysisProgress?,
    analyze: @Sendable (MarkdownRecord, MarkdownRecordAnalysisRequirements, MarkdownRecordContentKind) async -> AnalyzedMarkdownRecord = {
      await MarkdownRecordAnalyzer.analyze($0, requirements: $1, contentKind: $2)
    },
  ) async throws -> QueryReport {
    let start = Date()
    let root = Path(command.scope.projectRoot ?? Path.current.string).absolute().normalize()
    let options = try command.scope.surveyOptions()
    var paths = command.paths
    for (file, nul) in command.scope.filesFrom.map({ ($0, false) }) + command.scope.filesFrom0.map({ ($0, true) }) {
      let data = try CLIFileListInput.read(file)
      guard data.count <= DocumentReadBudgets.sourceBytes, let text = String(data: data, encoding: .utf8) else { throw ValidationError("File lists require bounded UTF-8 input") }
      var input = Substring(text)
      paths += try MarkdownQueryFileListParser(nulDelimited: nul).parse(&input).map { (root + $0).string }
    }
    if paths.isEmpty && command.scope.filesFrom.isEmpty && command.scope.filesFrom0.isEmpty { paths = [Path.current.string] }
    let selections = try paths.map { path in
      let absolute = Path(path).absolute().normalize().string
      guard absolute == root.string || absolute.hasPrefix(root.string + "/") else { throw ValidationError("Query input is outside --project-root: \(path)") }
      return absolute == root.string ? "" : String(absolute.dropFirst(root.string.count + 1))
    }
    let invocation = CLIInvocation(argv: CommandLine.arguments, workingDirectory: Path.current.string)
    var report = QueryReport(query: [
      "invocation": try json(invocation), "effective": .object([
        "key": predicate.key.map(JSONValue.string) ?? .null, "json-path": command.jsonPath.map(JSONValue.string) ?? .null,
        "condition": .string(predicate.operation), "value-type": .string(predicate.domain),
        "value-format": predicate.format.map(JSONValue.string) ?? .null,
        "case-sensitive": .boolean(predicate.caseSensitive), "match": .string(predicate.all ? "all" : "any"),
        "timezone": .string(predicate.timezone.identifier), "requested-timezone": .string(command.timezone),
        "date-mode": .string(command.dateMode), "week-start": .string(command.weekStart),
        "output": .string(command.output), "output-format": .string(command.outputFormat.rawValue),
      ]),
    ], scope: [
      "root": .string(root.string), "paths": .array(paths.map(JSONValue.string)),
      "recursive": .boolean(options.recursive), "markdown-only": .boolean(options.markdownOnly),
      "exclude": .array(options.exclude.map(JSONValue.string)),
      "files-from": .array(command.scope.filesFrom.map(JSONValue.string)), "files-from0": .array(command.scope.filesFrom0.map(JSONValue.string)),
      "notes": .array([.string("Hidden entries and symlinks are skipped.")]),
    ])
    var effective = report.query["effective"]?.objectValue ?? [:]
    let operands: [(String, String?)] = [
      ("equals", command.equals), ("not-equals", command.notEquals), ("contains", command.contains),
      ("greater-than", command.greaterThan), ("greater-than-or-equal", command.greaterThanOrEqual),
      ("less-than", command.lessThan), ("less-than-or-equal", command.lessThanOrEqual),
      ("same-day", command.sameDay), ("same-week", command.sameWeek), ("same-month", command.sameMonth), ("same-year", command.sameYear),
      ("before", command.before), ("after", command.after), ("is-type", command.isType), ("in-rule", command.inRule),
    ]
    for (name, value) in operands { if let value { effective[name] = .string(value) } }
    effective["limit"] = .integer(command.limit); effective["diagnostic-limit"] = .integer(command.diagnosticLimit)
    if command.isType != nil { effective["condition"] = .string("is-type"); effective["key"] = .null }
    if command.inRule != nil { effective["condition"] = .string("in-rule"); effective["key"] = .null }
    report.query["effective"] = .object(effective)
    report.scope["config"] = command.scope.config.map(JSONValue.string) ?? .null
    report.scope["max-files"] = .integer(options.maxFiles)
    var diagnosticPaths: Set<String> = []
    func issue(_ path: String, _ code: String, _ message: String) {
      report.complete = false
      report.summary.diagnosticTotal += 1
      diagnosticPaths.insert(path)
      if command.diagnosticLimit == 0 || report.diagnostics.count < command.diagnosticLimit {
        report.diagnostics.append(.init(path: path, code: code, message: message))
      }
    }
    var observations: [MarkdownSurveyObservation] = []
    var membership: [String: Bool] = [:]
    var membershipUnknown: Set<String> = []
    let project = command.isType != nil || command.inRule != nil ? try IndexProjectEvaluator(root: root, configPath: command.scope.config.map { Path($0) } ?? root + ".md-utils/md-utils.json") : nil
    let type = project?.types.definitions.first { $0.name.rawValue == command.isType }
    let rule = project?.rules?.definitions.first { $0.name == command.inRule }
    if command.isType != nil && type == nil { throw ValidationError("Unknown type: \(command.isType ?? "")") }
    if command.inRule != nil && rule == nil { throw ValidationError("Unknown rule: \(command.inRule ?? "")") }
    let collection = type?.relationships.isEmpty == false ? try await MarkdownRelationshipNativeCollection.load(root: root, noIndex: command.scope.noIndex, includeNonMarkdown: !options.markdownOnly, configPath: command.scope.config.map { Path($0) }) : nil
    let projection: FrontmatterIndexSnapshot.Projection = command.output == "frontmatter" ? .full : predicate.selectedTopLevelKeys.map(FrontmatterIndexSnapshot.Projection.selected) ?? .full
    var source = "direct"
    var snapshotGeneration: Int?
    var usedCache = false
    if command.scope.indexOnly {
      await progress?.update("Reading published query evidence…")
      source = "snapshot"
      do {
        let snapshot = try FrontmatterIndexSnapshot.read(root: root, selections: selections, includeNonMarkdown: !options.markdownOnly, maxFiles: options.maxFiles, projection: projection, requireQueryEvidence: true, acceptsPath: { SurveyRunner.accepted($0, selections: selections, options: options) })
        observations = snapshot.observations.filter { SurveyRunner.accepted($0.path, selections: selections, options: options) }
        snapshotGeneration = snapshot.generation
        for limitation in snapshot.limitations { issue(root.string, "query.snapshot.unavailable", limitation) }
      } catch is CancellationError { throw CancellationError() }
      catch { issue(root.string, "query.snapshot.unavailable", String(describing: error)) }
    } else if project == nil && !command.scope.noIndex && options.exclude.isEmpty && (root + ".md-utils/index.sqlite").exists && !paths.isEmpty && paths.allSatisfy({ Path($0).isDirectory }) && options.recursive {
      // Directory refresh cannot express arbitrary exclusions. Use direct,
      // exclusion-pruned discovery for those scopes instead of reading extra files.
      do {
        await progress?.update("Refreshing cached query evidence…")
        let snapshot = try await FrontmatterIndexSnapshot.refresh(root: root, config: command.scope.config.map { Path($0) } ?? root + ".md-utils/md-utils.json", directories: selections.map { $0.isEmpty || $0.hasSuffix("/") ? $0 : $0 + "/" }, includeNonMarkdown: !options.markdownOnly, verifyHashes: command.scope.verifyHashes, maxFiles: options.maxFiles, projection: projection, requireQueryEvidence: true, acceptsPath: { SurveyRunner.accepted($0, selections: selections, options: options) })
        observations = snapshot.observations.filter { SurveyRunner.accepted($0.path, selections: selections, options: options) }
        snapshotGeneration = snapshot.generation; source = "index"; usedCache = true
      } catch is CancellationError { throw CancellationError() }
      catch { QueryFilter.warn("Cache unavailable; reading sources directly: \(error)") }
    }
    if !command.scope.indexOnly && !usedCache {
      var discovery = SurveyReport(root: root.string, paths: paths, requestedMetrics: [])
      discovery.parameters["limit"] = .integer(0)
      let records = try SurveyRunner.discover(root: root, paths: paths, options: options, report: &discovery)
      report.summary.skipped = discovery.coverage.skippedBinary
      report.summary.unknown += discovery.coverage.unreadable
      for entry in discovery.fileIssues.rows {
        for reason in entry.reasons { issue(entry.path, reason.code, reason.message) }
      }
      if !discovery.complete && discovery.fileIssues.rows.isEmpty { issue(root.string, "query.budget", discovery.limitations.joined(separator: "; ")) }
      await progress?.update("Evaluating \(records.count) discovered files…")
      for record in records {
        try Task.checkCancellation()
        guard let path = record.context.path?.rawValue else { continue }
        var requirements: MarkdownRecordAnalysisRequirements = type == nil ? [] : .all
        if let rule, let registry = project?.rules, let compiled = registry.rule(named: rule.name) {
          requirements.formUnion(MarkdownRuleChecker(registry: registry).analysisRequirements(for: compiled))
        }
        let analyzed = await analyze(record, requirements, .rulesKind(forFileName: path))
        try Task.checkCancellation()
        observations.append(.fromAnalysis(analyzed, path: path))
        if let rule, let registry = project?.rules {
          let assessment = try MarkdownRuleChecker(registry: registry).assessApplicability(analyzed, rule: rule)
          if assessment.unavailable { membershipUnknown.insert(path) } else { membership[path] = assessment.matches }
        } else if let type, let project {
          let checker = MarkdownTypeChecker(registry: project.types)
          let outcome: MarkdownAssessmentOutcome
          if let collection {
            if let stored = try await collection.record(at: path), stored.content == record.content {
              outcome = try await checker.assess(stored, as: type.name, collection: collection).outcome
            } else { outcome = .unavailable }
          } else { outcome = try checker.assess(analyzed, as: type.name).outcome }
          if outcome == .unavailable { membershipUnknown.insert(path) } else { membership[path] = outcome == .pass }
        }
      }
    }
    var frontmatter: [JSONValue] = [], absent: [JSONValue] = [], empty: [JSONValue] = []
    var unavailable: [JSONValue] = []
    for observation in observations {
      try Task.checkCancellation()
      let path = (root + observation.path).string
      if membershipUnknown.contains(observation.path) {
        report.summary.unknown += 1; issue(path, "query.membership.unavailable", "Required contract evidence is unavailable"); continue
      }
      if membership[observation.path] == false { report.summary.nonmatched += 1; continue }
      guard observation.state == .parsed || observation.state == .absent || membership[observation.path] == true else {
        if observation.state == .binary { report.summary.skipped += 1; continue }
        report.summary.unknown += 1
        if observation.diagnostics.isEmpty { issue(path, "query.frontmatter.\(observation.state.rawValue)", "Frontmatter is unavailable") }
        else { for diagnostic in observation.diagnostics { issue(path, diagnostic.code, diagnostic.message) } }
        continue
      }
      let matched: Bool
      do { matched = try membership[observation.path] ?? predicate.matches(observation) }
      catch { report.summary.unknown += 1; issue(path, "query.evaluation", String(describing: error)); continue }
      guard matched else { report.summary.nonmatched += 1; continue }
      report.summary.matched += 1
      let outputUnavailable = command.output == "frontmatter" && observation.state != .parsed && observation.state != .absent
      if outputUnavailable { issue(path, "query.output.unavailable", "Confirmed match has unavailable frontmatter") }
      guard command.output != "count", command.limit == 0 || report.returnedPaths.count < command.limit else { continue }
      report.returnedPaths.append(path)
      if command.output == "frontmatter" {
        if observation.state != .parsed && observation.state != .absent {
          unavailable.append(.object(["path": .string(path), "reason": .string("frontmatter-unavailable")]))
        } else if observation.state == .absent { absent.append(.string(path)) }
        else if observation.frontmatter?.isEmpty != false { empty.append(.string(path)) }
        else { frontmatter.append(.object(["path": .string(path), "frontmatter": .object(observation.frontmatter ?? [:]), "valueMetadata": try json(observation.valueMetadata ?? [:])])) }
      }
    }
    report.summary.returned = command.output == "count" ? report.summary.matched : report.returnedPaths.count
    report.summary.omitted = report.summary.matched - report.summary.returned
    report.summary.diagnosticFiles = diagnosticPaths.count
    report.summary.diagnosticsOmitted = report.summary.diagnosticTotal - report.diagnostics.count
    switch command.output {
    case "frontmatter": report.results = ["frontMatter": .array(frontmatter), "noFrontMatter": .array(absent), "emptyFrontMatter": .array(empty), "unavailable": .array(unavailable)]
    case "count": report.results = ["count": .integer(report.summary.matched)]
    default: report.results = ["paths": .array(report.returnedPaths.map(JSONValue.string))]
    }
    let end = Date()
    report.execution = ["startedAt": .string(start.ISO8601Format()), "finishedAt": .string(end.ISO8601Format()), "durationSeconds": .number(end.timeIntervalSince(start)), "version": .string(CLIEntry.buildVersion), "source": .string(source), "snapshotGeneration": snapshotGeneration.map(JSONValue.integer) ?? .null, "complete": .boolean(report.complete)]
    if let project {
      report.execution["definitionFingerprint"] = .string(project.fingerprint)
      report.execution["configuration"] = .string(command.scope.config ?? (root + ".md-utils/md-utils.json").string)
    }
    return report
  }
  static func json<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
  }
}
