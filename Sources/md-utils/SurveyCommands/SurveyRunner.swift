import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit

struct SurveyCoverageReport: Codable {
  var files = 0
  var markdown = 0
  var otherText = 0
  var parsed = 0
  var absent = 0
  var malformed = 0
  var unsupported = 0
  var unreadable = 0
  var skippedBinary = 0
  var markdownStates: [String: Int] = [:]
  var otherTextStates: [String: Int] = [:]
}

struct SurveyHint: Codable {
  var argv: [String]
  var workingDirectory: String
  var explanation: String
}

struct SurveyReport: Codable {
  var schemaVersion = 1
  var root: String
  var paths: [String]
  var requestedMetrics: [String]
  var selection: [String: JSONValue] = [:]
  var parameters: [String: JSONValue] = [:]
  var complete = true
  var metricComplete: [String: Bool] = [:]
  var source = "direct"
  var snapshotGeneration: Int?
  var coverage = SurveyCoverageReport()
  var scopeNotes = ["Scope note: hidden directory entries and symlinks are currently skipped. Configured definitions inside .md-utils/ may still be loaded."]
  var limitations: [String] = []
  var metrics: [String: JSONValue] = [:]
  var hints: [SurveyHint] = []
  var omittedHints = 0

  mutating func unavailable(_ message: String, metric: String? = nil) {
    complete = false
    limitations.append(message)
    if let metric { metricComplete[metric] = false }
    else { for metric in requestedMetrics { metricComplete[metric] = false } }
  }

  func text() -> String {
    func row(_ label: String, _ markdown: Int, _ other: Int) -> String {
      label.padding(toLength: 27, withPad: " ", startingAt: 0)
        + String(format: "%10d %10d %10d", markdown, other, markdown + other)
    }
    var lines = ["Survey: " + paths.joined(separator: ", "), "",
      "                              Markdown Other text      Total",
      row("Files", coverage.markdown, coverage.otherText),
    ]
    for (state, label) in [("parsed", "Frontmatter parsed"), ("malformed", "Frontmatter malformed"), ("absent", "No frontmatter"), ("unsupported", "Unsupported syntax")] {
      lines.append(row(label, coverage.markdownStates[state] ?? 0, coverage.otherTextStates[state] ?? 0))
    }
    lines += ["",
      "Unreadable: \(coverage.unreadable); skipped binary: \(coverage.skippedBinary)",
      "Source: \(source)" + (snapshotGeneration.map { " (generation \($0))" } ?? ""),
    ]
    lines += scopeNotes
    for metric in requestedMetrics where metric != "coverage" {
      guard let value = metrics[metric] else { continue }
      lines.append("\n\(metric):")
      if metric == "keys", let rowsValue = value.objectValue?["rows"], case .array(let rows) = rowsValue {
        for row in rows {
          guard let object = row.objectValue, let key = object["key"]?.stringValue else { continue }
          let kinds = object["kinds"]?.objectValue ?? [:]
          let summary = kinds.keys.sorted().map { "\($0): \(Self.display(kinds[$0] ?? .null))" }.joined(separator: ", ")
          lines.append("  \(key): \(Self.display(object["present"] ?? .null)) files; \(summary)")
        }
        lines.append("  Omitted keys: \(Self.display(value.objectValue?["omitted"] ?? .integer(0)))")
        continue
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      if let data = try? encoder.encode(value) { lines.append(String(decoding: data, as: UTF8.self)) }
    }
    lines += limitations.map { "Incomplete: " + $0 }
    for hint in hints {
      lines.append("\n" + hint.explanation)
      lines.append("  " + hint.argv.map(Self.quote).joined(separator: " "))
    }
    return lines.joined(separator: "\n")
  }

  static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func display(_ value: JSONValue) -> String {
    guard let data = try? JSONEncoder().encode(value) else { return "unavailable" }
    return String(decoding: data, as: UTF8.self)
  }
}

enum SurveyRunner {
  static let available = Set(["coverage", "malformed-fm", "keys", "rules", "types", "standards", "uncovered", "overlaps", "type-matches", "relationships"])

  static func json<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
  }

  static func run(metric: String, arguments: [String], options: SurveyOptions) async throws -> SurveyReport {
    try Task.checkCancellation()
    try options.validateRequest(metric: metric, arguments: arguments)
    let root = Path(options.projectRoot ?? Path.current.string).absolute().normalize()
    var paths = arguments
    let key = ["key", "values"].contains(metric) ? paths.removeFirst() : nil
    let positionalPaths = paths
    var requested = [metric]
    if metric == "overview" {
      requested = options.metrics.isEmpty ? ["coverage", "rules", "types", "keys", "malformed-fm"] :
        options.metrics.flatMap { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
      guard requested.allSatisfy(available.contains) else { throw ValidationError("Unknown survey metric; choose \(available.sorted().joined(separator: ", "))") }
    }
    requested = requested.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    for (file, nul) in options.filesFrom.map({ ($0, false) }) + options.filesFrom0.map({ ($0, true) }) {
      let data = file == "-" ? FileHandle.standardInput.readDataToEndOfFile() : try Data(contentsOf: URL(fileURLWithPath: file))
      guard data.count <= 64 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw ValidationError("File lists require bounded UTF-8 input") }
      var input = Substring(text)
      paths += try MarkdownQueryFileListParser(nulDelimited: nul).parse(&input).map { (root + $0).string }
    }
    if paths.isEmpty && options.filesFrom.isEmpty && options.filesFrom0.isEmpty { paths = [Path.current.string] }
    let selections = try paths.map { path -> String in
      let absolute = Path(path).absolute().normalize().string
      guard absolute == root.string || absolute.hasPrefix(root.string + "/") else { throw ValidationError("Survey input is outside --project-root: \(path)") }
      let relative = absolute == root.string ? "" : String(absolute.dropFirst(root.string.count + 1))
      return relative + ((path.hasSuffix("/") || absolute == root.string) && !relative.isEmpty ? "/" : "")
    }
    var report = SurveyReport(root: root.string, paths: paths, requestedMetrics: requested)
    report.selection = [
      "recursive": .boolean(options.recursive), "markdownOnly": .boolean(options.markdownOnly),
      "exclusions": .array(options.exclude.map(JSONValue.string)),
      "filesFrom": .array(options.filesFrom.map(JSONValue.string)),
      "filesFrom0": .array(options.filesFrom0.map(JSONValue.string)),
      "config": options.config.map(JSONValue.string) ?? .null,
    ]
    report.parameters = [
      "property": key.map(JSONValue.string) ?? .null, "pointer": .boolean(options.pointer),
      "elements": .boolean(options.elements), "count": .string(options.count),
      "top": .integer(options.top), "limit": .integer(options.limit),
      "minFiles": .integer(options.minFiles ?? (metric == "key" ? 20 : 1)),
      "minShare": .number(options.minShare), "outliers": .boolean(options.outliers),
      "format": options.format.map(JSONValue.string) ?? .null,
      "types": .array(options.type.map(JSONValue.string)), "rules": .array(options.rule.map(JSONValue.string)),
    ]
    report.metricComplete = Dictionary(uniqueKeysWithValues: requested.map { ($0, true) })
    var records: [MarkdownRecord] = []
    var observations: [MarkdownSurveyObservation] = []
    if options.indexOnly {
      report.source = "snapshot"
      // A snapshot-only failure is never permission to inspect source files.
      do {
        let snapshot = try SurveyIndexSnapshot.read(root: root, selections: selections, includeNonMarkdown: !options.markdownOnly, maxFiles: options.maxFiles)
        observations = snapshot.observations
        report.snapshotGeneration = snapshot.generation
        for problem in snapshot.limitations { report.unavailable(problem) }
      } catch is CancellationError { throw CancellationError() }
      catch { report.unavailable("Published survey evidence unavailable: \(error)") }
    } else {
      let needsRecords = !Set(requested).intersection(["rules", "types", "uncovered", "overlaps", "type-matches"]).isEmpty
      var usedCache = false
      if !options.noIndex, (root + ".md-utils/index.sqlite").exists,
        !paths.isEmpty, paths.allSatisfy({ Path($0).isDirectory }), options.recursive {
        do {
          let directories = selections.map { $0.isEmpty || $0.hasSuffix("/") ? $0 : $0 + "/" }
          let snapshot = try await SurveyIndexSnapshot.refresh(root: root,
            config: options.config.map { Path($0) } ?? root + ".md-utils/md-utils.json",
            directories: directories, includeNonMarkdown: !options.markdownOnly,
            verifyHashes: options.verifyHashes, maxFiles: options.maxFiles)
          observations = snapshot.observations
          report.snapshotGeneration = snapshot.generation
          report.source = "index"
          usedCache = true
        } catch is CancellationError { throw CancellationError() }
        catch {
          try Task.checkCancellation()
          FileHandle.standardError.write(Data("Warning: survey index unavailable (\(error)); reading source files directly.\n".utf8))
        }
      }
      if !usedCache || needsRecords {
        records = try discover(root: root, paths: paths, options: options, report: &report)
        // Contract metrics consume source records. Keep their observations tied to
        // those same records rather than mixing a cache baseline with newer text.
        observations = []
        for record in records { observations.append(try await MarkdownSurveyObservation.read(record)) }
        if usedCache {
          report.source = "source-after-index-refresh"
          report.snapshotGeneration = nil
        }
      }
    }
    // Filters apply to both source and snapshot evidence without filesystem access.
    observations = observations.filter { accepted($0.path, selections: selections, options: options) }
    for observation in observations {
      if observation.state == .binary { report.coverage.skippedBinary += 1; continue }
      report.coverage.files += 1
      if isMarkdown(observation.path) {
        report.coverage.markdown += 1
        report.coverage.markdownStates[observation.state.rawValue, default: 0] += 1
      } else {
        report.coverage.otherText += 1
        report.coverage.otherTextStates[observation.state.rawValue, default: 0] += 1
      }
      switch observation.state {
      case .parsed: report.coverage.parsed += 1
      case .absent: report.coverage.absent += 1
      case .malformed: report.coverage.malformed += 1
      case .unsupported: report.coverage.unsupported += 1
      case .binary: break
      }
    }
    observations.removeAll { $0.state == .binary }
    for metric in requested {
      try Task.checkCancellation()
      switch metric {
      case "coverage": report.metrics[metric] = try json(report.coverage)
      case "malformed-fm":
        let rows = observations.filter { observation in
          observation.state == .malformed && (options.format == nil || observation.format?.rawValue == options.format || observation.diagnostics.contains {
            $0.code == "record.frontmatter.invalid-\(options.format ?? "")"
          })
        }
        report.metrics[metric] = try table(rows, limit: options.limit)
      case "keys": report.metrics[metric] = try json(MarkdownSurveyStatistics.keys(observations, top: options.top, minFiles: options.minFiles ?? 1))
      case "key":
        if let key {
          var row = try MarkdownSurveyStatistics.key(observations, key: key, pointer: options.pointer,
            outliers: options.outliers, minFiles: options.minFiles ?? 20, minShare: options.minShare)
          let total = row.outlierPaths.count
          if options.limit > 0 { row.outlierPaths = Array(row.outlierPaths.prefix(options.limit)) }
          report.metrics[metric] = .object(["summary": try json(row), "outlierTotal": .integer(total), "outlierOmitted": .integer(total - row.outlierPaths.count)])
        }
      case "values":
        if let key { report.metrics[metric] = try json(MarkdownSurveyStatistics.values(observations, key: key, pointer: options.pointer,
          elements: options.elements, occurrences: options.count == "occurrences", top: options.top)) }
      case "standards": report.unavailable("survey standards is unsupported until the standards runtime is implemented", metric: metric)
      case "relationships":
        if !options.indexOnly && options.config != nil {
          report.unavailable("Relationship queries currently require the conventional project configuration", metric: metric)
          continue
        }
        let selected = Set(observations.filter { isMarkdown($0.path) }.map(\.path))
        do {
          let result = try await MarkdownCollectionQuerySession.run(
            .init(direction: .outgoing, selectors: [.files(selected)], types: options.type, detail: .evidence), root: root,
            noIndex: options.noIndex, indexedOnly: options.indexOnly, verifyHashes: options.verifyHashes,
          )
          report.metrics[metric] = try relationshipSummary(result.result, selected: selected, limit: options.limit)
          if !result.complete { report.unavailable("Relationship evidence is incomplete", metric: metric) }
          if observations.contains(where: { !isMarkdown($0.path) }) {
            report.scopeNotes.append("Relationship analysis covers Markdown files only; other text files are excluded from this metric.")
          }
        } catch is CancellationError { throw CancellationError() }
        catch { report.unavailable("Relationships: \(error)", metric: metric) }
      default: break
      }
    }
    let contracts = Set(requested).intersection(["rules", "types", "uncovered", "overlaps", "type-matches"])
    if !contracts.isEmpty {
      if options.indexOnly {
        for metric in contracts { report.unavailable("Snapshot has no survey \(metric) projection", metric: metric) }
      } else {
        try await SurveyContracts.populate(root: root, records: records, requested: contracts, options: options, report: &report)
      }
    }
    if !options.noHints {
      let hintPaths = positionalPaths.isEmpty && options.filesFrom.isEmpty && options.filesFrom0.isEmpty ? paths : positionalPaths
      let scope = hintPaths + ["--project-root", root.string] + (options.config.map { ["--config", $0] } ?? [])
        + options.filesFrom.flatMap { ["--files-from", $0] } + options.filesFrom0.flatMap { ["--files-from0", $0] }
        + options.exclude.flatMap { ["--exclude", $0] }
        + (options.recursive ? [] : ["--no-recursive"]) + (options.markdownOnly ? ["--markdown-only"] : [])
        + (options.indexOnly ? ["--index-only"] : [])
      if requested.contains("types") {
        report.hints.append(.init(argv: ["md-utils", "survey", "type-matches"] + scope + options.type.flatMap { ["--type", $0] }, workingDirectory: Path.current.string,
          explanation: "To discover which documents conform to these types, run type-matches. This opt-in assessment can be expensive; matching does not establish intended usage."))
      }
      if report.coverage.malformed > 0 && metric != "malformed-fm" {
        report.hints.append(.init(argv: ["md-utils", "survey", "malformed-fm"] + scope, workingDirectory: Path.current.string,
          explanation: "Inspect malformed frontmatter and parser diagnostics."))
      }
      if requested.contains("relationships"), let first = observations.first(where: { isMarkdown($0.path) }) {
        report.hints.append(.init(argv: ["md-utils", "rel", "out", first.path, "--root", root.string, "--detail", "explain"],
          workingDirectory: Path.current.string, explanation: "Inspect outgoing relationship evidence for a representative source; targets resolve across the project root."))
      }
      if let rowsValue = report.metrics["keys"]?.objectValue?["rows"], case .array(let rows) = rowsValue {
        for row in rows {
          guard let name = row.objectValue?["key"]?.stringValue,
            (row.objectValue?["kinds"]?.objectValue?.count ?? 0) > 1 else { continue }
          report.hints.append(.init(argv: ["md-utils", "survey", "key", name] + scope,
            workingDirectory: Path.current.string, explanation: "Inspect the mixed observed value kinds for \(name); these are conventions, not requirements."))
        }
      }
      if metric == "key", let key {
        report.hints.append(.init(argv: ["md-utils", "survey", "values", key] + scope + (options.pointer ? ["--pointer"] : []),
          workingDirectory: Path.current.string, explanation: "Explore frequent values and their distribution for this property."))
      }
      // A consumed stdin list cannot be replayed by a generated command. Preserve
      // the report's evidence instead of presenting a command that would hang.
      if (options.filesFrom + options.filesFrom0).contains("-") {
        report.hints.removeAll { $0.argv.contains("-") }
        report.scopeNotes.append("Save the stdin file list to replay scope-specific investigation commands.")
      }
    }
    if options.limit > 0, report.hints.count > options.limit {
      report.omittedHints = report.hints.count - options.limit
      report.hints = Array(report.hints.prefix(options.limit))
    }
    return report
  }

  static func table<T: Encodable>(_ rows: [T], limit: Int) throws -> JSONValue {
    let visible = limit == 0 ? rows : Array(rows.prefix(limit))
    return .object(["rows": try json(visible), "total": .integer(rows.count), "omitted": .integer(rows.count - visible.count)])
  }

  static func relationshipSummary(_ query: MarkdownCollectionQueryResult, selected: Set<String>, limit: Int) throws -> JSONValue {
    let occurrences = query.occurrences ?? []
    let byID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
    var resolution: [String: Int] = [:]
    var inside = 0
    var outside = 0
    var selfLinks = 0
    for occurrence in occurrences where selected.contains(occurrence.source) {
      resolution[occurrence.resolution?.status.rawValue ?? "malformed", default: 0] += 1
      if let destination = occurrence.resolution?.destination {
        if destination == occurrence.source { selfLinks += 1 }
        else if selected.contains(destination) { inside += 1 }
        else { outside += 1 }
      }
    }
    struct Group: Hashable {
      var type: String
      var relation: String
    }
    let groups = Dictionary(grouping: query.namedRelationships ?? []) {
      Group(type: $0.assertion.type, relation: $0.assertion.relationship)
    }
    let ordered = groups.keys.sorted { $0.type == $1.type ? $0.relation < $1.relation : $0.type < $1.type }
    let named: [JSONValue] = try ordered.map { group in
      let interpretations = groups[group] ?? []
      let sources = Set(interpretations.compactMap { byID[$0.occurrence]?.source })
      return .object(["type": .string(group.type), "relationship": .string(group.relation), "documents": .integer(sources.count),
        "assertions": .integer(interpretations.count), "sources": try table(sources.sorted(), limit: limit)])
    }
    return .object([
      "namedRelationships": try table(named, limit: limit),
      "ordinaryLinks": try table(query.links.filter { $0.subject != $0.object }, limit: limit),
      "resolution": try json(resolution), "selfLinks": .integer(selfLinks),
      "targetsInsideSelection": .integer(inside), "targetsOutsideSelection": .integer(outside),
      "coverage": try json(query.coverage), "notices": try table(query.notices, limit: limit),
    ])
  }

  static func isMarkdown(_ path: String) -> Bool { ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }

  static func accepted(_ path: String, selections: [String], options: SurveyOptions) -> Bool {
    guard !options.markdownOnly || isMarkdown(path) else { return false }
    guard !options.exclude.contains(where: { matches(path, glob: $0) || path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) else { return false }
    return selections.contains { selection in
      if path == selection { return true }
      let prefix = selection.isEmpty ? "" : (selection.hasSuffix("/") ? selection : selection + "/")
      guard path.hasPrefix(prefix) else { return false }
      return options.recursive || !path.dropFirst(prefix.count).contains("/")
    }
  }

  static func discover(root: Path, paths: [String], options: SurveyOptions, report: inout SurveyReport) throws -> [MarkdownRecord] {
    var found: Set<String> = []
    var records: [MarkdownRecord] = []
    var bytes = 0
    func visit(_ url: URL) throws {
      try Task.checkCancellation()
      let path = url.standardizedFileURL.path
      let relative = path == root.string ? "" : String(path.dropFirst(root.string.count + 1))
      guard !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return }
      guard !options.exclude.contains(where: { matches(relative, glob: $0) || relative == $0 || relative.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) else { return }
      guard found.insert(path).inserted else { return }
      if found.count / 4 > options.maxFiles { throw SurveyDiscoveryError.budget }
      let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
      if values.isSymbolicLink == true || url.resolvingSymlinksInPath().path != path { return }
      if values.isDirectory == true {
        for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]).sorted(by: { $0.path < $1.path }) {
          if !options.recursive, try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true { continue }
          do { try visit(child) }
          catch is CancellationError { throw CancellationError() }
          catch SurveyDiscoveryError.budget { throw SurveyDiscoveryError.budget }
          catch {
            report.coverage.unreadable += 1
            report.unavailable("\(child.path): \(error)")
          }
        }
      } else if values.isRegularFile == true && (!options.markdownOnly || isMarkdown(path)) {
        guard records.count < options.maxFiles, let size = values.fileSize, size <= 64 * 1024 * 1024,
          bytes + size <= 256 * 1024 * 1024 else { throw SurveyDiscoveryError.budget }
        let data = try Data(contentsOf: url)
        let after = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard after.fileSize == size, data.count == size,
          after.contentModificationDate == values.contentModificationDate else {
          throw ValidationError("File changed while reading: \(relative); retry survey")
        }
        bytes += data.count
        if data.contains(0) { report.coverage.skippedBinary += 1; return }
        guard let text = String(data: data, encoding: .utf8) else { throw ValidationError("Invalid UTF-8: \(relative)") }
        records.append(MarkdownRecord(content: text, context: MarkdownRecordContext(
          path: try MarkdownRecordPath(relative), modificationDate: values.contentModificationDate,
        )))
      }
    }
    for path in paths {
      do { try visit(URL(fileURLWithPath: Path(path).absolute().normalize().string)) }
      catch is CancellationError { throw CancellationError() }
      catch SurveyDiscoveryError.budget {
        report.unavailable(SurveyDiscoveryError.budget.description)
        break
      }
      catch { report.coverage.unreadable += 1; report.unavailable("\(path): \(error)") }
    }
    return records.sorted { ($0.context.path?.rawValue ?? "") < ($1.context.path?.rawValue ?? "") }
  }

  static func matches(_ path: String, glob: String) -> Bool {
    (try? MarkdownRecordPath(path).matches(glob: glob)) ?? false
  }
}

private enum SurveyDiscoveryError: Error, CustomStringConvertible {
  case budget
  var description: String { "Survey input/discovery budget exhausted; results are incomplete" }
}
