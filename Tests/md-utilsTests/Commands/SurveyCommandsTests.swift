import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit
import Testing
@testable import md_utils

private struct SurveyFixture {
  let root: Path
  init() throws {
    root = Path.current.absolute() + "tmp/survey-tests-\(UUID().uuidString)/"
    try root.mkpath()
  }
  func write(_ path: String, _ content: String) throws {
    try (root + path).parent().mkpath()
    try (root + path).write(content)
  }
  func remove() { try? root.delete() }
  func report(_ metric: String, paths: [String]? = nil, flags: [String] = []) async throws -> SurveyReport {
    let options = try SurveyOptions.parse(["--project-root", root.string] + flags)
    return try await SurveyRunner.run(metric: metric, arguments: paths ?? [root.string], options: options)
  }
}

private actor SurveyAnalysisCounter {
  var count = 0
  func increment() { count += 1 }
}

struct SurveyCommandsTests {
  @Test(arguments: ["overview", "coverage", "malformed-fm", "keys", "key", "values", "rules", "types", "standards", "uncovered", "overlaps", "type-matches", "relationships"])
  func surveyOutputFormatsAreConsistent(_ metric: String) throws {
    let arguments = ["survey", metric] + (["key", "values"].contains(metric) ? ["Status"] : []) + ["./notes/"]
    for format in ["text", "json", "json-pretty"] {
      _ = try CLIEntry.parseAsRoot(arguments + ["--format", format])
    }
    #expect(throws: (any Error).self) { try CLIEntry.parseAsRoot(arguments + ["--json"]) }
    #expect(throws: (any Error).self) { try CLIEntry.parseAsRoot(arguments + ["--format", "yaml"]) }
  }

  @Test func compactAndPrettySurveyJSONContainIdenticalData() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("bad.md", "---\nx: [broken\n---")
    try fixture.write("bad-toml.md", "+++\nx = [\n+++\n")
    let arguments = ["survey", "malformed-fm", fixture.root.string, "--project-root", fixture.root.string, "--fm-format", "yaml", "--no-index"]
    let compact = try CLIProcessTestHelper.run(arguments + ["--format", "json"])
    let pretty = try CLIProcessTestHelper.run(arguments + ["--format", "json-pretty"])
    #expect(compact.status == 0)
    #expect(pretty.status == 0)
    #expect(compact.standardOutput.split(separator: "\n").count == 1)
    #expect(pretty.standardOutput.split(separator: "\n").count > 1)
    let left = try JSONDecoder().decode(JSONValue.self, from: Data(compact.standardOutput.utf8))
    let right = try JSONDecoder().decode(JSONValue.self, from: Data(pretty.standardOutput.utf8))
    #expect(left == right)
    #expect(!compact.standardOutput.contains("\u{1B}"))
    #expect(!pretty.standardOutput.contains("\u{1B}"))
    #expect(left.objectValue?["parameters"]?.objectValue?["fmFormat"] == .string("yaml"))
    #expect(left.objectValue?["metrics"]?.objectValue?["malformed-fm"]?.objectValue?["total"] == .integer(1))
    let toml = try await fixture.report("malformed-fm", flags: ["--fm-format", "toml"])
    #expect(toml.metrics["malformed-fm"]?.objectValue?["total"] == .integer(1))
    let implicitText = try CLIProcessTestHelper.run(arguments)
    let explicitText = try CLIProcessTestHelper.run(arguments + ["--format", "text"])
    #expect(implicitText.standardOutput == explicitText.standardOutput)
  }
  @Test func ruleSurveyAnalyzesEachRecordOnceWithoutChangingSelection() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/md-utils.json", "{\"configVersion\":\"0.3.0\"}")
    try fixture.write(".md-utils/types/empty.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Empty","version":"1","frontmatter":{},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    let matches = [
      "paths": "{\"paths\":[\"notes/**\"]}",
      "metadata": "{\"frontmatter\":{\"publish\":{\"equals\":true}}}",
      "headings": "{\"document\":{\"hasHeading\":\"Summary\"}}",
    ]
    for (name, match) in matches {
      try fixture.write(".md-utils/rules/\(name).mdrule.json", "{\"name\":\"\(name)\",\"match\":\(match),\"types\":\"empty.mdtype.json\"}")
    }
    let inputs = [
      ("notes/good.md", "---\npublish: true\n---\n# Summary\n"),
      ("notes/bad.md", "---\nx: [broken\n---\n"),
      ("notes/catalog.base", "views: []"),
      ("notes/absent.md", "# Title\n"),
    ]
    let records = try inputs.map { path, content in
      MarkdownRecord(content: content, context: .init(path: try MarkdownRecordPath(path)))
    }
    let project = try IndexProjectEvaluator(root: fixture.root, configPath: fixture.root + ".md-utils/md-utils.json")
    let registry = try #require(project.rules)
    let checker = MarkdownRuleChecker(registry: registry)
    var expected: [String: [Int]] = [:]
    // The existing per-rule evaluator is the semantic oracle, including unsupported and malformed hosts.
    for definition in registry.definitions {
      var selected = 0, uncertain = 0
      let compiled = try #require(registry.rule(named: definition.name))
      for record in records {
        let path = try #require(record.context.path?.rawValue)
        let analysis = await MarkdownRecordAnalyzer.analyze(record, requirements: checker.analysisRequirements(for: compiled), contentKind: .rulesKind(forFileName: path))
        let result = try checker.assessApplicability(analysis, rule: definition)
        if result.unavailable { uncertain += 1 } else if result.matches { selected += 1 }
      }
      expected[definition.name] = [selected, uncertain]
    }
    let counter = SurveyAnalysisCounter()
    var report = SurveyReport(root: fixture.root.string, paths: [fixture.root.string], requestedMetrics: ["rules"])
    let options = try SurveyOptions.parse(["--no-hints"])
    try await SurveyContracts.populate(root: fixture.root, records: records, requested: ["rules"], options: options, report: &report, analyze: { record, requirements, kind in
      await counter.increment()
      return await MarkdownRecordAnalyzer.analyze(record, requirements: requirements, contentKind: kind)
    })
    let analyses = await counter.count
    #expect(analyses == records.count)
    #expect(report.complete)
    guard case .array(let rows) = report.metrics["rules"]?.objectValue?["rows"] else {
      Issue.record("Expected rule rows"); return
    }
    #expect(rows.count == expected.count)
    for row in rows {
      let fields = try #require(row.objectValue)
      let counts = try #require(expected[fields["name"]?.stringValue ?? ""])
      #expect(fields["selected"] == .integer(counts[0]))
      #expect(fields["unknown"] == .integer(counts[1]))
    }
    let typeCounter = SurveyAnalysisCounter()
    var inventory = SurveyReport(root: fixture.root.string, paths: [fixture.root.string], requestedMetrics: ["types"])
    try await SurveyContracts.populate(root: fixture.root, records: records, requested: ["types"], options: options, report: &inventory, analyze: { record, requirements, kind in
      await typeCounter.increment()
      return await MarkdownRecordAnalyzer.analyze(record, requirements: requirements, contentKind: kind)
    })
    let inventoryAnalyses = await typeCounter.count
    #expect(inventoryAnalyses == records.count)
    #expect(inventory.complete)
    if case .array(let types) = inventory.metrics["types"]?.objectValue?["rows"] {
      #expect(types.first?.objectValue?["referencedByApplicableRule"] == .boolean(true))
    } else { Issue.record("Expected referenced type inventory") }
    let rootString = fixture.root.string
    // Cancellation during shared parsing must stop before any rule consumes the result.
    let cancelled = Task {
      var report = SurveyReport(root: rootString, paths: [rootString], requestedMetrics: ["rules"])
      let options = try SurveyOptions.parse(["--no-hints"])
      try await SurveyContracts.populate(root: Path(rootString), records: records, requested: ["rules"], options: options, report: &report, analyze: { record, requirements, kind in
        let result = await MarkdownRecordAnalyzer.analyze(record, requirements: requirements, contentKind: kind)
        withUnsafeCurrentTask { $0?.cancel() }
        return result
      })
    }
    do {
      try await cancelled.value
      Issue.record("Expected cancellation to propagate")
    } catch is CancellationError {
      // Cancellation must not be converted into an incomplete report or fallback.
    }
  }
  @Test func overviewIsCompactAndKeepsPartialMetricsVisible() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "---\na: text\nb: text\nc: text\nd: text\ne: text\n---\n")
    try fixture.write("two.md", "---\na: [text]\nb: [text]\nc: [text]\nd: [text]\ne: [text]\n---\n")
    var report = try await fixture.report("overview", flags: ["--no-index"])
    #expect(report.hints.count <= 3)
    #expect(report.hints.filter { $0.argv.prefix(3) == ["md-utils", "survey", "key"] }.count == 1)
    report.unavailable("Example rule limitation", metric: "rules")
    let text = report.text(overview: true)
    #expect(text.split(separator: "\n").count < 35)
    #expect(text.contains("Incomplete metrics: rules"))
    #expect(text.contains("Common keys"))
  }

  @Test func progressReportsPhaseChangesOnlyAndStops() async {
    let progress = SurveyProgress()
    #expect(await progress.nextMessage() == "Please be patient. Discovering files…")
    #expect(await progress.nextMessage() == nil)
    await progress.update("Analyzing 26,241 text files…")
    #expect(await progress.nextMessage() == "Please be patient. Analyzing 26,241 text files…")
    await progress.finish()
    await progress.update("Must not print")
    #expect(await progress.nextMessage() == nil)
  }

  @Test func valueHintsDescribeAFrontmatterPipelineAndRespectRestrictedScope() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/read.md", "---\nStatus: ✅ Read\n---\nBody must not appear")
    try fixture.write("notes/null.md", "---\nStatus: null\n---\n")
    try fixture.write("notes/missing.md", "---\ntitle: Missing\n---\n")
    let report = try await fixture.report("values", paths: ["Status", (fixture.root + "notes/").string])
    let encoded = try SurveyRunner.json(report)
    guard case .array(let hints) = encoded.objectValue?["hints"] else {
      Issue.record("Expected structured hints"); return
    }
    #expect(hints.count == 1)
    #expect(hints.allSatisfy { $0.objectValue?["pipeTo"] != nil })
    #expect(report.text().contains("md-utils fm dump"))
    #expect(report.text().contains(" | jq "))
    #expect(report.text().contains("✅ Read"))
    let hint = try #require(report.hints.first)
    let matches = try CLIProcessTestHelper.run(Array(hint.argv.dropFirst()))
    #expect(matches.status == 0)
    #expect(matches.standardOutput.contains("Body must not appear") == false)
    #expect(hint.pipeTo == ["jq", "--arg", "key", "Status", "--argjson", "value", "\"✅ Read\"", ".frontMatter[] | select(has($key) and .[$key] == $value)"])
    let restricted = try await fixture.report("values", paths: ["Status", (fixture.root + "notes/").string], flags: ["--exclude", "notes/missing.md"])
    #expect(restricted.hints.isEmpty)
  }

  @Test func textReportsRenderValuesAndNestedFindingsWithoutJSONEnvelopes() {
    var report = SurveyReport(root: ".", paths: ["notes/"], requestedMetrics: ["values", "rules", "types", "malformed-fm", "uncovered", "overlaps", "type-matches", "relationships"])
    report.parameters["property"] = .string("Status")
    report.metrics["values"] = .object([
      "present": .integer(2), "missing": .integer(1), "denominator": .integer(2),
      "counting": .string("documents"), "total": .integer(1), "omitted": .integer(0),
      "rows": .array([.object(["count": .integer(2), "proportion": .number(1),
        "value": .object(["kind": .string("string"), "value": .string("Read")]),
      ])]),
    ])
    for metric in report.requestedMetrics where metric != "values" {
      report.metrics[metric] = .object(["total": .integer(1), "omitted": .integer(0),
        "rows": .array([.object(["name": .string("Example"), "selected": .integer(2)])]),
      ])
    }
    let text = report.text()
    #expect(text.contains("100.0%"))
    #expect(text.contains("Read"))
    #expect(text.contains("Selected: 2"))
    #expect(text.contains("\"rows\"") == false)
    #expect(text.contains("\"counting\"") == false)
    #expect(SurveyReport.quote("md-utils") == "md-utils")
    #expect(SurveyReport.quote("a folder/") == "'a folder/'")
    #expect(SurveyReport.quote("$(touch file)") == "'$(touch file)'")
    #expect(SurveyReport.quote("it's") == "'it'\\''s'")
  }

  @Test func largeNonTextAttachmentsDoNotStopKeySurvey() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("a.pdf", "%PDF-1.7\n")
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: (fixture.root + "a.pdf").string))
    try handle.truncate(atOffset: 81 * 1024 * 1024)
    try handle.close()
    try fixture.write("b.dat", "attachment\0bytes")
    try fixture.write("c.zip", "PK\u{3}\u{4}archive")
    try fixture.write("z.md", "---\nstatus: draft\n---\n")
    for json in [false, true] {
      let result = try CLIProcessTestHelper.run([
        "survey", "key", "status", fixture.root.string,
        "--project-root", fixture.root.string, "--no-index",
      ] + (json ? ["--format", "json"] : []))
      #expect(result.status == 0)
      #expect(result.standardError.isEmpty)
      if json {
        let report = try JSONDecoder().decode(JSONValue.self, from: Data(result.standardOutput.utf8))
        #expect(report.objectValue?["complete"] == .boolean(true))
        #expect(report.objectValue?["coverage"]?.objectValue?["skippedNonText"] == .integer(3))
      } else {
        #expect(result.standardOutput.contains("Skipped: 3 non-text files"))
        #expect(result.standardOutput.contains("Present: 1"))
        #expect(result.standardOutput.contains("\"summary\"") == false)
      }
    }
  }

  @Test func vanillaSurveySelectsOverview() throws {
    let parsed = try CLIEntry.parseAsRoot(["survey", "./notes/"])
    #expect(parsed is SurveyCommand<SurveyOverview>)
  }
  @Test(arguments: ["overview", "coverage", "malformed-fm", "keys", "rules", "types", "standards", "uncovered", "overlaps", "type-matches", "relationships"])
  func focusedCommandsAreDiscoverable(_ metric: String) throws {
    let parsed = try CLIEntry.parseAsRoot(["survey", metric, "./notes/", "--format", "json"])
    #expect(type(of: parsed).configuration.commandName == metric)
  }

  @Test func recursiveTextScopeDeduplicatesAndExplainsExclusions() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "---\ntitle: One\n---\n")
    try fixture.write("nested/two.txt", "text")
    try fixture.write(".hidden.md", "hidden")
    try FileManager.default.createSymbolicLink(atPath: (fixture.root + "linked.md").string, withDestinationPath: (fixture.root + "one.md").string)
    let report = try await fixture.report("coverage", paths: [fixture.root.string, (fixture.root + "one.md").string])
    #expect(report.coverage.files == 2)
    #expect(report.coverage.markdown == 1)
    #expect(report.coverage.otherText == 1)
    #expect(report.scopeNotes.contains { $0.contains("hidden") && $0.contains("symlinks") })
    #expect(report.complete)
    #expect(report.text().contains("Frontmatter parsed"))
    #expect(report.text().contains("Other text"))
    #expect((fixture.root + ".md-utils/index.sqlite").exists == false)
    #expect(try await fixture.report("coverage", flags: ["--no-recursive"]).coverage.files == 1)
    #expect(try await fixture.report("coverage", flags: ["--markdown-only"]).coverage.files == 1)
  }

  @Test func malformedIsSuccessfulWhileMissingInputIsIncomplete() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("bad.md", "---\nx: [broken\n---\n")
    let malformed = try await fixture.report("malformed-fm")
    #expect(malformed.complete)
    #expect(malformed.coverage.malformed == 1)
    let missing = try await fixture.report("coverage", paths: [(fixture.root + "missing.md").string])
    #expect(missing.complete == false)
    #expect(missing.coverage.unreadable == 1)
  }

  @Test func fileListOnlyDoesNotAddWorkingDirectory() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "one")
    try fixture.write("two.md", "two")
    try fixture.write("selected.paths", "one.md\n")
    let result = try await fixture.report("coverage", paths: [], flags: ["--files-from", (fixture.root + "selected.paths").string])
    #expect(result.coverage.files == 1)
  }

  @Test func keyPresenceHintsSurveyTheFolderWithALiteralKey() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("a note.md", "---\nStatus: null\n---\n")
    try fixture.write("other.md", "---\ntitle: Other\n---\n")
    for metric in ["key", "keys"] {
      let arguments = metric == "key" ? ["Status", fixture.root.string] : [fixture.root.string]
      let report = try await fixture.report(metric, paths: arguments, flags: ["--no-index"])
      let hint = try #require(report.hints.first { $0.argv.prefix(3) == ["md-utils", "fm", "has"] })
      #expect(hint.argv.contains("Status"))
      #expect(hint.argv.contains(fixture.root.normalize().string))
      #expect(!hint.argv.contains((fixture.root + "a note.md").string))
      #expect(!hint.argv.contains("--no-index"))
      let result = try CLIProcessTestHelper.run(Array(hint.argv.dropFirst()))
      #expect(result.standardOutput.contains("a note.md: true"))
      #expect(result.standardOutput.contains("other.md: false"))
    }
    let pointer = try await fixture.report("key", paths: ["/Status", fixture.root.string], flags: ["--pointer"])
    #expect(!pointer.hints.contains { $0.argv.contains("has") })
    let quiet = try await fixture.report("keys", flags: ["--no-hints"])
    #expect(quiet.hints.isEmpty)
    let restricted = try await fixture.report("key", paths: ["Status", fixture.root.string], flags: ["--exclude", "other.md", "--no-recursive", "--markdown-only"])
    let restrictedHint = try #require(restricted.hints.first { $0.argv.prefix(3) == ["md-utils", "fm", "has"] })
    #expect(restrictedHint.argv.contains("--no-recursive"))
    #expect(!restrictedHint.argv.contains("--include-non-md"))
    #expect(restrictedHint.argv.contains((fixture.root + "other.md").string))
    let filtered = try CLIProcessTestHelper.run(Array(restrictedHint.argv.dropFirst()))
    #expect(!filtered.standardOutput.contains("false"))
  }

  @Test func unassessableFilesHaveBoundedReasonsAndInvestigationHints() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("bad.md", "---\nx: [broken\n---\n")
    try fixture.write("catalog.base", "views: []")
    try Data([0xff, 0xfe, 0x61]).write(to: URL(fileURLWithPath: (fixture.root + "unreadable.md").string))
    let report = try await fixture.report("key", paths: ["Status", fixture.root.string], flags: ["--no-index", "--limit", "1"])
    let encoded = try SurveyRunner.json(report).objectValue?["fileIssues"]?.objectValue
    #expect(encoded?["total"] == .integer(3))
    #expect(encoded?["omitted"] == .integer(2))
    #expect(report.text().contains("File assessment issues"))
    #expect(report.hints.contains { $0.argv.contains("--format") && $0.argv.contains("coverage") })
    let full = try await fixture.report("coverage", flags: ["--no-index", "--limit", "0", "--no-hints"])
    let text = full.text()
    #expect(text.contains("bad.md"))
    #expect(text.contains("catalog.base"))
    #expect(text.contains("unreadable.md"))
    #expect(text.contains("unsupported"))
    #expect(text.contains("malformed"))
    #expect(text.contains("unreadable"))
    #expect(full.hints.isEmpty)
  }

  @Test func standardsAreExplicitlyUnsupported() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    let report = try await fixture.report("standards")
    #expect(report.complete == false)
    #expect(report.limitations.contains { $0.contains("standards") })
    try fixture.write("a.md", "---\ntitle: A\n---")
    try fixture.write("b.md", "---\ntitle: B\n---")
    let fast = try await fixture.report("standards", flags: ["--max-files", "1"])
    #expect(fast.coverage.files == 0)
    #expect(fast.source == "not-run")
    #expect(!fast.coverageEvaluated)
    #expect(fast.limitations.count == 1)
    #expect(fast.text() == "survey standards is an upcoming feature.")
    let mixed = try await fixture.report("overview", flags: ["--metrics", "coverage,standards"])
    #expect(mixed.coverage.files == 2)
    #expect(mixed.coverageEvaluated)
    #expect(mixed.metricComplete["coverage"] == true)
    #expect(mixed.metricComplete["standards"] == false)
  }

  @Test(arguments: ["types", "type-matches", "relationships", "uncovered", "overlaps"])
  func focusedSummariesLeadWithFindings(_ metric: String) throws {
    var report = SurveyReport(root: ".", paths: ["notes/"], requestedMetrics: [metric])
    let empty = try SurveyRunner.table([String](), limit: 20)
    report.metrics[metric] = metric == "uncovered"
      ? .object(["files": empty, "unknown": empty, "configuredRules": .integer(0)]) : empty
    let text = report.text()
    #expect(!text.contains("Frontmatter parsed"))
    #expect(text.contains("0"))
    #expect(text.contains("Source:"))
  }

  @Test func typeMatchSummaryKeepsCountsAndBoundsExamples() throws {
    var report = SurveyReport(root: ".", paths: ["notes/"], requestedMetrics: ["type-matches"])
    let paths = (1...8).map { "notes/example-\($0).md" }
    let outcomes: JSONValue = .object([
      "pass": try SurveyRunner.table(paths, limit: 20),
      "fail": try SurveyRunner.table([String](), limit: 20),
      "unavailable": try SurveyRunner.table(["unknown.base"], limit: 20),
    ])
    report.metrics["type-matches"] = try SurveyRunner.table([
      JSONValue.object(["type": .string("Book"), "outcomes": outcomes]),
    ], limit: 20)
    let text = report.text()
    #expect(text.contains("Assessed"))
    #expect(text.contains("Unavailable"))
    #expect(text.contains("5 more"))
    #expect(!text.contains("example-8.md"))
    #expect(text.contains("--type Book"))
    report.parameters["limit"] = .integer(0)
    #expect(report.text().contains("example-8.md"))
    #expect(report.metrics["type-matches"]?.objectValue?["rows"] != nil)
  }

  @Test func typeInventoryHasAnActionableMatchingHint() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    let report = try await fixture.report("types")
    #expect(report.hints.contains { $0.argv.contains("type-matches") && $0.explanation.contains("conform") })
  }

  @Test func snapshotModeNeverFallsBackWhenDatabaseMissing() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("valid.md", "---\ntitle: Present\n---\n")
    let report = try await fixture.report("keys", flags: ["--index-only"])
    #expect(report.complete == false)
    #expect(report.coverage.files == 0)
    #expect((fixture.root + ".md-utils/index.sqlite").exists == false)
  }

  @Test func existingIndexRefreshesAndSnapshotSurvivesDeletedSources() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\nx: 1\n---\n")
    try (fixture.root + ".md-utils/").mkpath()
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    _ = try CollectionIndexer(database: database, root: URL(fileURLWithPath: fixture.root.string))
    let cached = try await fixture.report("keys", paths: [(fixture.root + "notes/").string + "/"])
    #expect(cached.source == "index")
    #expect(cached.coverage.files == 1)
    try fixture.write("notes/two.txt", "---\nx: two\n---\n")
    let changed = try await fixture.report("keys", paths: [(fixture.root + "notes/").string + "/"])
    #expect(changed.coverage.files == 2)
    try (fixture.root + "notes/").delete()
    let snapshot = try await fixture.report("keys", paths: [(fixture.root + "notes/").string + "/"], flags: ["--index-only"])
    #expect(snapshot.complete)
    #expect(snapshot.coverage.files == 2)
    #expect(snapshot.metrics["keys"] == changed.metrics["keys"])
    #expect(snapshot.snapshotGeneration == changed.snapshotGeneration)
  }

  @Test func ruleSelectionDoesNotRequireConformanceAndOverlapsRemainInformational() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/md-utils.json", "{\"configVersion\":\"0.3.0\"}")
    try fixture.write(".md-utils/types/book.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Book","version":"1",
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    for name in ["books", "also-books"] {
      try fixture.write(".md-utils/rules/\(name).mdrule.json", """
        {"name":"\(name)","match":{"paths":["notes/**"]},"types":"book.mdtype.json"}
        """)
    }
    try fixture.write(".md-utils/rules/aaa-unused.mdrule.json", """
      {"name":"aaa-unused","match":{"paths":["nowhere/**"]},"types":"book.mdtype.json"}
      """)
    try fixture.write(".md-utils/types/unused.mdtype.json", """
      {"md-utils-type-schema":"1","name":"AUnused","version":"1","frontmatter":{},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try fixture.write("notes/invalid.md", "---\nother: value\n---\n")
    try fixture.write("outside.md", "outside")
    let overlap = try await fixture.report("overlaps")
    #expect(overlap.complete)
    #expect(overlap.metrics["overlaps"]?.objectValue?["total"] == .integer(1))
    #expect(overlap.hints.contains { $0.argv.contains("validate") } == false)
    let rankedRules = try await fixture.report("rules", flags: ["--limit", "1", "--no-index"])
    if case .array(let rows) = rankedRules.metrics["rules"]?.objectValue?["rows"] {
      #expect(rows.first?.objectValue?["name"] == .string("also-books"))
    } else { Issue.record("Expected ranked rules") }
    #expect(rankedRules.hints.count == 3)
    let matchingHint = try #require(rankedRules.hints.first { $0.argv.prefix(3) == ["md-utils", "rules", "matching"] })
    #expect(matchingHint.argv.contains((fixture.root + "notes/invalid.md").string))
    #expect(matchingHint.argv.contains("--explain"))
    let filesHint = try #require(rankedRules.hints.first { $0.argv.prefix(3) == ["md-utils", "rules", "files-matching"] })
    #expect(filesHint.argv.contains("also-books"))
    #expect(filesHint.argv.contains("--include-non-md"))
    #expect(filesHint.explanation.contains("beyond"))
    #expect(rankedRules.hints.allSatisfy { $0.argv.contains((fixture.root + ".md-utils/md-utils.json").string) })
    #expect(rankedRules.hints.first?.argv.contains("describe") == true)
    #expect(rankedRules.hints.first?.argv.contains((fixture.root + ".md-utils/md-utils.json").string) == true)
    #expect(rankedRules.metrics["rules"]?.objectValue?["summary"]?.objectValue?["noMatchRules"] == .integer(1))
    #expect(!rankedRules.text().contains("Frontmatter parsed"))
    #expect(!rankedRules.text().contains("aaa-unused"))
    let missingRules = try await fixture.report("rules", paths: [(fixture.root + "missing/").string])
    #expect(!missingRules.complete)
    #expect(missingRules.metrics.isEmpty)
    #expect(missingRules.text().contains("Input does not exist:"))
    try fixture.write(".md-utils/rules/tagged.mdrule.json", """
      {"name":"tagged","match":{"frontmatter":{"tags":{"includes":"book"}}},"types":"book.mdtype.json"}
      """)
    try fixture.write("notes/catalog.base", "views: []")
    try fixture.write(".md-utils/rules/tagged-again.mdrule.json", """
      {"name":"tagged-again","match":{"frontmatter":{"tags":{"includes":"book"}}},"types":"book.mdtype.json"}
      """)
    let uncertainRules = try await fixture.report("rules", flags: ["--no-index"])
    #expect(uncertainRules.complete, "Unassessed files are findings, not execution failures")
    let summary = uncertainRules.metrics["rules"]?.objectValue?["summary"]?.objectValue
    #expect(summary?["uncertainFiles"] == .integer(1))
    #expect(summary?["uncertainRuleFilePairs"] == .integer(2))
    #expect(summary?["assessmentComplete"] == .boolean(false))
    if case .array(let rows) = uncertainRules.metrics["rules"]?.objectValue?["uncertainties"]?.objectValue?["rows"] {
      #expect(rows.count == 2)
      #expect(rows.allSatisfy { $0.objectValue?["path"] == .string("notes/catalog.base") })
      #expect(rows.allSatisfy { $0.objectValue?["reasons"] != .array([]) })
    } else { Issue.record("Expected structured uncertainty details") }
    #expect(uncertainRules.text().contains("notes/catalog.base"))
    #expect(uncertainRules.text().contains("tagged"))
    try (fixture.root + "notes/catalog.base").delete()
    let rankedTypes = try await fixture.report("types", flags: ["--limit", "1"])
    if case .array(let rows) = rankedTypes.metrics["types"]?.objectValue?["rows"] {
      #expect(rows.first?.objectValue?["name"] == .string("Book"))
    } else { Issue.record("Expected relevant type first") }
    let uncovered = try await fixture.report("uncovered")
    #expect(uncovered.metrics["uncovered"]?.objectValue?["files"]?.objectValue?["total"] == .integer(1))
    let types = try await fixture.report("type-matches", paths: [(fixture.root + "notes/").string], flags: ["--type", "Book"])
    #expect(types.complete)
    let rows = try #require(types.metrics["type-matches"]?.objectValue?["rows"])
    guard case .array(let values) = rows else { Issue.record("Expected type-match rows"); return }
    #expect(values.first?.objectValue?["outcomes"]?.objectValue?["fail"]?.objectValue?["total"] == .integer(1))
    let inventory = try await fixture.report("types", flags: ["--type", "Book"])
    #expect(inventory.hints.contains { $0.argv.contains("type-matches") && $0.argv.contains("Book") })
  }

  @Test func unrelatedSubcommandOptionsAreRejected() {
    for arguments in [
      ["survey", "coverage", "--elements"],
      ["survey", "keys", "--pointer"],
      ["survey", "values", "status", "--outliers"],
      ["survey", "coverage", "--fm-format", "yaml"],
    ] {
      #expect(throws: (any Error).self) { try CLIEntry.parseAsRoot(arguments) }
    }
  }

  @Test func brokenCacheFallsBackWithoutChangingFindings() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\nx: 1\n---\n")
    try fixture.write(".md-utils/index.sqlite", "not sqlite")
    let fallback = try await fixture.report("keys", paths: [(fixture.root + "notes/").string])
    let direct = try await fixture.report("keys", paths: [(fixture.root + "notes/").string], flags: ["--no-index"])
    #expect(fallback.complete)
    #expect(fallback.metrics == direct.metrics)
    #expect(fallback.source == "direct")
  }

  @Test func relationshipsAreSummarizedAndLimited() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/a.md", "[[b]] [[missing]] [[a]]")
    try fixture.write("notes/b.md", "B")
    try fixture.write("notes/0-clean.md", "No links")
    let report = try await fixture.report("relationships", paths: [(fixture.root + "notes/").string], flags: ["--limit", "1", "--no-index"])
    #expect(report.complete)
    #expect(report.metrics["relationships"]?.objectValue?["ordinaryLinks"] != nil)
    #expect(report.metrics["relationships"]?.objectValue?["resolution"] != nil)
    let hint = try #require(report.hints.first { $0.argv.prefix(3) == ["md-utils", "rel", "out"] })
    #expect(hint.argv.contains("notes/a.md"))
    #expect(hint.explanation.contains("unresolved"))
    #expect(hint.argv.contains("--no-index"))
    let text = report.text()
    #expect(text.contains("distinct ordinary links"))
    #expect(text.contains("Link occurrences:"))
    #expect(text.contains("Resolution namespace: full project"))
    if let headline = text.range(of: "Link occurrences:"), let examples = text.range(of: "Example links:") {
      #expect(headline.lowerBound < examples.lowerBound)
    } else { Issue.record("Expected relationship summary before examples") }
  }

  @Test func keyPrevalenceUsesAssessableFilesAndHandlesZeroDenominator() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "---\nStatus: Read\n---")
    try fixture.write("two.md", "---\nStatus: null\n---")
    try fixture.write("absent.md", "No frontmatter")
    try fixture.write("bad.md", "---\nx: [broken\n---")
    try fixture.write("catalog.base", "views: []")
    let report = try await fixture.report("key", paths: ["Status", fixture.root.string])
    let summary = report.metrics["key"]?.objectValue?["summary"]?.objectValue
    #expect(summary?["assessable"] == .integer(3))
    #expect(summary?["presentProportion"] == .number(2.0 / 3.0))
    #expect(report.text().contains("2 of 3 assessable files (66.7%)"))
    #expect(report.text().contains("33.3%"))
    let keys = try await fixture.report("keys")
    #expect(keys.text().contains("66.7%"))
    let none = try await fixture.report("key", paths: ["Status", (fixture.root + "bad.md").string])
    #expect(none.metrics["key"]?.objectValue?["summary"]?.objectValue?["presentProportion"] == .null)
    #expect(none.text().contains("N/A"))
    let all = try await fixture.report("key", paths: ["Status", (fixture.root + "two.md").string])
    #expect(all.text().contains("100.0%"))
    let absent = try await fixture.report("key", paths: ["Status", (fixture.root + "absent.md").string])
    #expect(absent.text().contains("0 of 1 assessable files (0.0%)"))
  }

  @Test func directAndCachedCoverageAgreeForBinaryAndMalformedFiles() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/bad.md", "---\nx: [broken\n---\n")
    try fixture.write("notes/blob.bin", "binary\0bytes")
    try fixture.write("notes/document.pdf", "%PDF-1.7\nattachment")
    try (fixture.root + ".md-utils/").mkpath()
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    _ = try CollectionIndexer(database: database, root: URL(fileURLWithPath: fixture.root.string))
    let paths = [(fixture.root + "notes/").string]
    let direct = try await fixture.report("coverage", paths: paths, flags: ["--no-index"])
    let cached = try await fixture.report("coverage", paths: paths)
    #expect(cached.complete)
    #expect(cached.coverage.files == direct.coverage.files)
    #expect(cached.coverage.skippedBinary == 2)
    #expect(cached.coverage.malformed == 1)
  }

  @Test func selectionLimitsAndPointersAreValidatedWithoutRunning() {
    for arguments in [
      ["survey", "key", "/bad~2escape", "--pointer"],
      ["survey", "--metrics", "not-a-metric"],
      ["survey", "--max-files", "0"],
      ["survey", "--index-only", "--verify-hashes"],
      ["survey", "values", "tags", "--count", "occurrences"],
    ] { #expect(throws: (any Error).self) { try CLIEntry.parseAsRoot(arguments) } }
  }

  @Test func unreadableTextDoesNotHideReadableSiblings() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try Data([0xff, 0xfe]).write(to: URL(fileURLWithPath: (fixture.root + "a.txt").string))
    try fixture.write("b.md", "---\ntitle: Available\n---\n")
    let report = try await fixture.report("coverage", flags: ["--no-index"])
    #expect(report.complete == false)
    #expect(report.coverage.unreadable == 1)
    #expect(report.coverage.files == 1)
  }

  @Test func missingExplicitConfigurationIsNotNoRules() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("note.md", "note")
    let report = try await fixture.report("uncovered", flags: ["--config", (fixture.root + "missing.json").string])
    #expect(report.complete == false)
    #expect(report.metrics["uncovered"] == nil)
  }

  @Test func nulListsExclusionsAndConfinement() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "one")
    try fixture.write("two.md", "two")
    try fixture.write("selected.paths0", "one.md\0two.md\0")
    let report = try await fixture.report("coverage", paths: [], flags: ["--files-from0", (fixture.root + "selected.paths0").string, "--exclude", "two.md"])
    #expect(report.coverage.files == 1)
    await #expect(throws: ValidationError.self) { try await fixture.report("coverage", paths: ["/"]) }
  }

  @Test func hashVerificationDetectsStatPreservingChanges() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\nx: 1\n---\n")
    // Whole seconds round-trip through both Foundation and native stat without
    // timestamp precision differences accidentally invalidating the cache.
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
      ofItemAtPath: (fixture.root + "notes/one.md").string)
    try (fixture.root + ".md-utils/").mkpath()
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    _ = try CollectionIndexer(database: database, root: URL(fileURLWithPath: fixture.root.string))
    let paths = [(fixture.root + "notes/").string]
    let first = try await fixture.report("keys", paths: paths)
    let file = fixture.root + "notes/one.md"
    let date = try #require(FileManager.default.attributesOfItem(atPath: file.string)[.modificationDate] as? Date)
    try fixture.write("notes/one.md", "---\nx: a\n---\n")
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.string)
    let ordinary = try await fixture.report("keys", paths: paths)
    #expect(ordinary.metrics["keys"] == first.metrics["keys"])
    let verified = try await fixture.report("keys", paths: paths, flags: ["--verify-hashes"])
    #expect(verified.metrics["keys"] != first.metrics["keys"])
    #expect(verified.complete)
  }

  @Test func cancelledPublicationCannotExposeNewExtraction() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\nx: original\n---\n")
    try (fixture.root + ".md-utils/").mkpath()
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    let indexer = try CollectionIndexer(database: database, root: URL(fileURLWithPath: fixture.root.string))
    let paths = [(fixture.root + "notes/").string]
    let original = try await fixture.report("keys", paths: paths)
    try fixture.write("notes/one.md", "---\ndifferent: replacement\n---\n")
    await #expect(throws: CancellationError.self) {
      try await indexer.updateMany(refreshing: [IndexScope(path: "notes/", includeNonMarkdown: true)],
        fingerprint: "interrupted-survey-test", evaluate: { _, _, _, _ in throw CancellationError() })
    }
    let snapshot = try await fixture.report("keys", paths: paths, flags: ["--index-only"])
    #expect(snapshot.metrics["keys"] == original.metrics["keys"])
    #expect(snapshot.snapshotGeneration == original.snapshotGeneration)
    #expect(snapshot.complete == false, "An interrupted scope is conservatively marked incomplete")
  }

  @Test func permissionDeniedInputsRemainVisibleAndDoNotHideSiblings() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("a.md", "unreadable")
    try fixture.write("b.md", "readable")
    let path = (fixture.root + "a.md").string
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
    let report = try await fixture.report("coverage", flags: ["--no-index"])
    #expect(report.complete == false)
    #expect(report.coverage.files == 1)
    #expect(report.coverage.unreadable == 1)
  }

  @Test func budgetExhaustionIsNotAnUnreadableFile() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("a.md", "one")
    try fixture.write("b.md", "two")
    let report = try await fixture.report("coverage", flags: ["--max-files", "1", "--no-index"])
    #expect(report.complete == false)
    #expect(report.coverage.files == 1)
    #expect(report.coverage.unreadable == 0)
    #expect(report.limitations.contains { $0.contains("budget exhausted") })
  }

  @Test func mixedKeyKindsOfferFocusedInvestigation() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "---\ntags: [swift]\n---\n")
    try fixture.write("two.md", "---\ntags: swift\n---\n")
    let report = try await fixture.report("keys")
    #expect(report.hints.contains { $0.argv.starts(with: ["md-utils", "survey", "key", "tags"]) })
    let silent = try await fixture.report("keys", flags: ["--no-hints"])
    #expect(silent.hints.isEmpty)
    #expect(silent.scopeNotes.isEmpty == false)
  }

  @Test func jsonRetainsSelectionAndMetricParameters() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("one.md", "---\na: {b: value}\n---\n")
    let report = try await fixture.report("values", paths: ["/a/b", fixture.root.string], flags: ["--pointer", "--exclude", "archive/", "--top", "3"])
    let object = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(report)).objectValue
    #expect(object?["parameters"]?.objectValue?["property"] == .string("/a/b"))
    #expect(object?["parameters"]?.objectValue?["pointer"] == .boolean(true))
    #expect(object?["selection"]?.objectValue?["exclusions"] == .array([.string("archive/")]))
  }

  @Test func relationshipGroupsPreserveTypeAndRelationIdentity() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    for (name, relation, file) in [("A", "b.c", "a"), ("A.b", "c", "ab")] {
      try fixture.write(".md-utils/types/\(file).mdtype.json", """
        {"md-utils-type-schema":"2","requires":["document-relationships"],"name":"\(name)","version":"1",
         "frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
         "relationships":{"\(relation)":{"select":["ref"],"target":{"type":"person.mdtype.json"}}}}
        """)
    }
    try fixture.write(".md-utils/types/person.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Person","version":"1","frontmatter":{},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try fixture.write("source.md", "---\nref: '[[target]]'\n---\n")
    try fixture.write("target.md", "target")
    let report = try await fixture.report("relationships", paths: [(fixture.root + "source.md").string], flags: ["--type", "A", "--type", "A.b"])
    #expect(report.complete)
    #expect(report.metrics["relationships"]?.objectValue?["namedRelationships"]?.objectValue?["total"] == .integer(2))
  }
}
