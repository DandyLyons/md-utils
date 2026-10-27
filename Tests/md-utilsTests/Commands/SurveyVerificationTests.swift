import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit
import Testing
@testable import md_utils

private struct SurveyVerificationFixture {
  let root = Path.current.absolute() + "tmp/survey-verification-\(UUID().uuidString)"
  init() throws { try root.mkpath() }
  func write(_ path: String, _ content: String) throws {
    try (root + path).parent().mkpath()
    try (root + path).write(content)
  }
  func remove() { try? root.delete() }
  func database() throws -> SQLiteIndexDatabase {
    try (root + ".md-utils").mkpath()
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    _ = try CollectionIndexer(database: database, root: URL(fileURLWithPath: root.string))
    return database
  }
  func report(_ metric: String, path: String = "notes/", flags: [String] = []) async throws -> SurveyReport {
    let options = try SurveyOptions.parse(["--project-root", root.string] + flags)
    return try await SurveyRunner.run(metric: metric, arguments: [(root + path).string], options: options)
  }
}

private actor TypeMatchAnalysisCounter {
  var count = 0
  func increment() { count += 1 }
}

struct SurveyVerificationTests {
  @Test func localTypeMatchingParsesEachRecordOnceAndPreservesEveryOutcome() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    for name in ["Book", "Article", "Person"] {
      let body = name == "Article" ? "[{\"id\":\"summary\",\"heading\":{\"text\":\"Summary\"}}]" : "[]"
      try fixture.write(".md-utils/types/\(name).mdtype.json", """
        {"md-utils-type-schema":"1","name":"\(name)","version":"1",
         "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
         "body":{"requirements":\(body),"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
        """)
    }
    let inputs = [
      ("notes/good.md", "---\ntitle: Example\n---\n# Summary\n"),
      ("notes/headless.md", "---\ntitle: No heading\n---\nPlain body\n"),
      ("notes/missing.md", "No frontmatter"),
      ("notes/malformed.md", "---\nx: [broken\n---\n"),
      ("notes/catalog.base", "views: []"),
    ]
    let records = try inputs.map { path, content in
      MarkdownRecord(content: content, context: .init(path: try MarkdownRecordPath(path)))
    }
    let project = try IndexProjectEvaluator(root: fixture.root, configPath: fixture.root + ".md-utils/md-utils.json")
    let registry = try MarkdownTypeRegistry(definitions: project.types.definitions, schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: fixture.root), typeResourceBindings: project.types.typeResourceBindings)
    let checker = MarkdownTypeChecker(registry: registry)
    var expected: [String: [String: [String]]] = [:]
    // Independently analyze each type/record pair as the pre-optimization oracle.
    for definition in project.types.definitions {
      var outcomes: [String: [String]] = ["pass": [], "fail": [], "unavailable": []]
      for record in records {
        let path = try #require(record.context.path?.rawValue)
        let analysis = await MarkdownRecordAnalyzer.analyze(record, contentKind: .rulesKind(forFileName: path))
        let result = try checker.assess(analysis, as: definition.name)
        outcomes[result.outcome.rawValue, default: []].append(path)
      }
      expected[definition.name.rawValue] = outcomes
    }
    let counter = TypeMatchAnalysisCounter()
    var report = SurveyReport(root: fixture.root.string, paths: [fixture.root.string], requestedMetrics: ["type-matches"])
    let options = try SurveyOptions.parse(["--no-hints", "--limit", "0"])
    try await SurveyContracts.populate(root: fixture.root, records: records, requested: ["type-matches"], options: options, report: &report, analyze: { record, requirements, kind in
      await counter.increment()
      return await MarkdownRecordAnalyzer.analyze(record, requirements: requirements, contentKind: kind)
    })
    let count = await counter.count
    #expect(count == records.count)
    guard case .array(let rows) = report.metrics["type-matches"]?.objectValue?["rows"] else {
      Issue.record("Expected type outcomes"); return
    }
    #expect(rows.count == expected.count)
    for row in rows {
      let fields = try #require(row.objectValue)
      let reference = try #require(expected[fields["type"]?.stringValue ?? ""])
      for outcome in ["pass", "fail", "unavailable"] {
        let paths = try #require(reference[outcome])
        #expect(fields["outcomes"]?.objectValue?[outcome]?.objectValue?["rows"] == .array(paths.map(JSONValue.string)))
      }
    }
    let rootString = fixture.root.string
    let cancelled = Task {
      var report = SurveyReport(root: rootString, paths: [rootString], requestedMetrics: ["type-matches"])
      let options = try SurveyOptions.parse(["--no-hints"])
      try await SurveyContracts.populate(root: Path(rootString), records: records, requested: ["type-matches"], options: options, report: &report, analyze: { record, requirements, kind in
        let result = await MarkdownRecordAnalyzer.analyze(record, requirements: requirements, contentKind: kind)
        withUnsafeCurrentTask { $0?.cancel() }
        return result
      })
    }
    do {
      try await cancelled.value
      Issue.record("Expected local analysis cancellation to propagate")
    } catch is CancellationError {}
  }
  @Test func hiddenFilesAndSymlinkAncestorsAreSkippedVisibly() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write("visible.md", "visible")
    try fixture.write(".hidden.md", "hidden")
    try fixture.write(".private/secret.md", "secret")
    try FileManager.default.createSymbolicLink(atPath: (fixture.root + "alias.md").string, withDestinationPath: (fixture.root + "visible.md").string)
    try FileManager.default.createSymbolicLink(atPath: (fixture.root + "alias-folder").string, withDestinationPath: (fixture.root + ".private").string)
    let recursive = try await fixture.report("coverage", path: "", flags: ["--no-index"])
    #expect(recursive.complete)
    #expect(recursive.coverage.files == 1)
    #expect(recursive.text().contains("symlinks"))
    for path in ["alias.md", "alias-folder/secret.md", ".hidden.md"] {
      let explicit = try await fixture.report("coverage", path: path, flags: ["--no-index"])
      #expect(explicit.complete)
      #expect(explicit.coverage.files == 0)
      #expect(explicit.coverage.unreadable == 0)
    }
  }

  @Test(arguments: [false, true])
  func snapshotBudgetCountsSelectedTextRatherThanSkippedEvidence(_ markdownOnly: Bool) async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    for index in 0..<8 { try fixture.write("notes/a-\(index).pdf", "%PDF-1.7\nattachment") }
    if markdownOnly { try fixture.write("notes/b.txt", "extra text") }
    try fixture.write("notes/z.md", "---\nx: 1\n---")
    let database = try fixture.database()
    _ = try await fixture.report("coverage")
    let selection = markdownOnly ? ["--markdown-only"] : []
    let direct = try await fixture.report("coverage", flags: selection + ["--no-index", "--max-files", "1"])
    let snapshot = try await fixture.report("coverage", flags: selection + ["--index-only", "--max-files", "1"])
    #expect(direct.complete)
    #expect(snapshot.complete)
    #expect(snapshot.coverage.files == 1)
    #expect(snapshot.coverage.skippedBinary == direct.coverage.skippedBinary)
    #expect(snapshot.metrics == direct.metrics)
    _ = database
  }

  @Test func refreshChangesAndDeletionsPreserveTypedStatisticsWithoutScanningOtherFolders() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\nvalue: 1\nwhen: 2026-10-27\nempty: null\nflags: [true, false]\n---")
    try fixture.write("notes/delete.md", "---\nvalue: old\n---")
    try fixture.write("unrelated/broken.txt", "temporary")
    try Data([0xff, 0xfe]).write(to: URL(fileURLWithPath: (fixture.root + "unrelated/broken.txt").string))
    let database = try fixture.database()
    let flags = ["--metrics", "coverage,keys,malformed-fm"]
    let first = try await fixture.report("overview", flags: flags)
    #expect(first.complete)
    #expect(first.source == "index")
    let direct = try await fixture.report("overview", flags: flags + ["--no-index"])
    #expect(first.metrics == direct.metrics)
    try (fixture.root + "notes/delete.md").delete()
    try fixture.write("notes/one.md", "---\nvalue: changed\nwhen: 2026-10-27\nempty: null\nflags: [true, false]\n---")
    try fixture.write("notes/new.txt", "+++\nvalue = 2.5\n+++\n")
    let refreshed = try await fixture.report("overview", flags: flags)
    let changedDirect = try await fixture.report("overview", flags: flags + ["--no-index"])
    #expect(refreshed.complete)
    #expect(refreshed.source == "index")
    #expect(refreshed.metrics == changedDirect.metrics)
    #expect(refreshed.metrics != first.metrics)
    #expect(refreshed.snapshotGeneration != first.snapshotGeneration)
    _ = database
  }

  @Test func snapshotQueriesIgnoreDeletedConfigurationAndSourcesWithoutMutatingDatabase() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/md-utils.json", "{\"configVersion\":\"0.3.0\"}")
    try fixture.write("notes/one.md", "---\nvalue: 1\n---")
    let database = try fixture.database()
    let original = try await fixture.report("keys")
    try (fixture.root + "notes").delete()
    try (fixture.root + ".md-utils/md-utils.json").delete()
    let location = URL(fileURLWithPath: (fixture.root + ".md-utils/index.sqlite").string)
    let before = try Data(contentsOf: location)
    let snapshot = try await fixture.report("keys", flags: ["--index-only", "--config", (fixture.root + "missing-config.json").string])
    #expect(snapshot.complete)
    #expect(snapshot.metrics == original.metrics)
    #expect(snapshot.snapshotGeneration == original.snapshotGeneration)
    let customRelationships = try await fixture.report("relationships", flags: ["--index-only", "--config", (fixture.root + "missing-config.json").string])
    #expect(!customRelationships.complete)
    #expect(customRelationships.metrics["relationships"] == nil)
    #expect(customRelationships.limitations.contains { $0.contains("conventional project configuration") })
    let contracts = try await fixture.report("overview", flags: ["--index-only", "--metrics", "coverage,rules,types,type-matches,uncovered,overlaps"])
    #expect(contracts.metricComplete["coverage"] == true)
    for metric in ["rules", "types", "type-matches", "uncovered", "overlaps"] {
      #expect(contracts.metricComplete[metric] == false)
      #expect(contracts.metrics[metric] == nil)
    }
    #expect(try Data(contentsOf: location) == before)
    _ = database
  }

  @Test func relationshipSummaryPreservesSelfLinksAndSelectionBoundaries() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/types/self.mdtype.json", """
      {"md-utils-type-schema":"2","requires":["document-relationships"],"name":"Self","version":"1",
       "frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
       "relationships":{"ref":{"select":["ref"],"target":{"type":"self.mdtype.json"}}}}
      """)
    try fixture.write("notes/a.md", "---\nref: '[[a]]'\n---\n[[b]] [[a]] [[../outside]] [[missing]]")
    try fixture.write("notes/b.md", "B")
    try fixture.write("outside.md", "Outside")
    let report = try await fixture.report("relationships", flags: ["--no-index", "--limit", "1", "--type", "Self"])
    let summary = try #require(report.metrics["relationships"]?.objectValue)
    #expect(report.complete)
    #expect(summary["selfLinks"] == .integer(1))
    #expect(summary["targetsInsideSelection"] == .integer(1))
    #expect(summary["targetsOutsideSelection"] == .integer(1))
    #expect(summary["resolution"]?.objectValue?["unresolved"] == .integer(1))
    #expect(summary["ordinaryLinks"]?.objectValue?["total"] == .integer(2))
    #expect(summary["ordinaryLinks"]?.objectValue?["omitted"] == .integer(1))
  }

  @Test func typeMatchingReassessesRecursiveTargetsOutsideSelection() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/types/person.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Person","version":"1",
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try fixture.write(".md-utils/types/parent.mdtype.json", """
      {"md-utils-type-schema":"2","requires":["document-relationships"],"name":"Parent","version":"1",
       "frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
       "relationships":{"person":{"select":["ref"],"target":{"type":"person.mdtype.json"}}}}
      """)
    try fixture.write("people/good.md", "---\ntitle: Person\n---")
    try fixture.write("people/bad.md", "No title")
    try fixture.write("notes/good.md", "---\nref: '[[../people/good]]'\n---")
    try fixture.write("notes/bad.md", "---\nref: '[[../people/bad]]'\n---")
    try fixture.write("notes/unsupported.base", "views: []")
    let flags = ["--no-index", "--type", "Parent"]
    let project = try IndexProjectEvaluator(root: fixture.root, configPath: fixture.root + ".md-utils/md-utils.json")
    let registry = try MarkdownTypeRegistry(definitions: project.types.definitions, schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: fixture.root), typeResourceBindings: project.types.typeResourceBindings)
    let collection = try await MarkdownRelationshipNativeCollection.load(root: fixture.root, noIndex: true, includeNonMarkdown: true)
    let source = try #require(try await collection.record(at: "notes/good.md"))
    let assessment = try await MarkdownTypeChecker(registry: registry).assess(source, as: MarkdownTypeName(rawValue: "Parent"), collection: collection)
    #expect(assessment.outcome == .pass, Comment(rawValue: assessment.diagnostics.map(\.message).joined(separator: "; ")))
    let before = try await fixture.report("type-matches", flags: flags)
    guard case .array(let rows) = before.metrics["type-matches"]?.objectValue?["rows"] else {
      Issue.record("Expected type assessments"); return
    }
    let outcomes = try #require(rows.first?.objectValue?["outcomes"]?.objectValue)
    for outcome in ["pass", "fail", "unavailable"] { #expect(outcomes[outcome]?.objectValue?["total"] == .integer(1)) }
    try fixture.write("people/bad.md", "---\ntitle: Repaired\n---")
    let after = try await fixture.report("type-matches", flags: flags)
    guard case .array(let updated) = after.metrics["type-matches"]?.objectValue?["rows"] else {
      Issue.record("Expected updated type assessments"); return
    }
    #expect(updated.first?.objectValue?["outcomes"]?.objectValue?["pass"]?.objectValue?["total"] == .integer(2))
    let options = try SurveyOptions.parse(["--no-index", "--no-hints", "--type", "Parent"])
    let composed = "---\nref: '[[../people/good]]'\n---\nCaf\u{e9}"
    let decomposed = "---\nref: '[[../people/good]]'\n---\nCafe\u{301}"
    #expect(composed == decomposed, "Swift String equality alone does not establish byte identity")
    try fixture.write("notes/good.md", composed)
    for content in ["Stale contents", decomposed] {
      var stale = SurveyReport(root: fixture.root.string, paths: [fixture.root.string], requestedMetrics: ["type-matches"])
      let oldSource = MarkdownRecord(content: content, context: .init(path: try MarkdownRecordPath("notes/good.md")))
      try await SurveyContracts.populate(root: fixture.root, records: [oldSource], requested: ["type-matches"], options: options, report: &stale)
      guard case .array(let staleRows) = stale.metrics["type-matches"]?.objectValue?["rows"] else {
        Issue.record("Expected stale source outcome"); return
      }
      #expect(staleRows.first?.objectValue?["outcomes"]?.objectValue?["unavailable"]?.objectValue?["total"] == .integer(1))
    }
  }

  @Test func changedDefinitionsChangeTypeAssessmentsAfterIndexRefresh() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    let definition = """
      {"md-utils-type-schema":"1","name":"Book","version":"1",
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """
    try fixture.write(".md-utils/types/book.mdtype.json", definition)
    try fixture.write("notes/one.md", "---\ntitle: Book\n---")
    let database = try fixture.database()
    let before = try await fixture.report("type-matches", flags: ["--type", "Book"])
    try fixture.write(".md-utils/types/book.mdtype.json", definition.replacingOccurrences(of: "[\"title\"]", with: "[\"author\"]"))
    let after = try await fixture.report("type-matches", flags: ["--type", "Book"])
    let direct = try await fixture.report("type-matches", flags: ["--type", "Book", "--no-index"])
    #expect(before.metrics != after.metrics)
    #expect(after.metrics == direct.metrics)
    #expect(after.source == "source-after-index-refresh")
    _ = database
  }

  @Test func absentRulesAndInvalidConfigurationHaveDifferentResults() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "No rules configured")
    let absent = try await fixture.report("uncovered", flags: ["--no-index"])
    #expect(absent.complete)
    #expect(absent.metrics["uncovered"]?.objectValue?["configuredRules"] == .integer(0))
    #expect(absent.metrics["uncovered"]?.objectValue?["files"]?.objectValue?["total"] == .integer(1))
    try fixture.write(".md-utils/md-utils.json", "{broken json")
    let invalid = try await fixture.report("uncovered", flags: ["--no-index"])
    #expect(!invalid.complete)
    #expect(invalid.metrics["uncovered"] == nil)
  }

  @Test func cancelledCacheRefreshDoesNotFallBackToSources() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write("notes/bad.txt", "temporary")
    try Data([0xff, 0xfe]).write(to: URL(fileURLWithPath: (fixture.root + "notes/bad.txt").string))
    try fixture.write(".md-utils/index.sqlite", "placeholder: injected refresh must run")
    let options = try SurveyOptions.parse(["--project-root", fixture.root.string])
    await #expect(throws: CancellationError.self) {
      try await SurveyRunner.run(metric: "coverage", arguments: [(fixture.root + "notes").string], options: options, cacheRefresh: { throw CancellationError() })
    }
  }

  @Test func oversizedTextIsBudgetExhaustionBeforeReadingItsContents() async throws {
    let fixture = try SurveyVerificationFixture()
    defer { fixture.remove() }
    try fixture.write("notes/large.md", String(repeating: "a", count: 8192))
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: (fixture.root + "notes/large.md").string))
    try handle.truncate(atOffset: 72 * 1024 * 1024)
    try handle.close()
    let report = try await fixture.report("coverage", flags: ["--no-index"])
    #expect(!report.complete)
    #expect(report.coverage.unreadable == 0)
    #expect(report.coverage.files == 0)
    #expect(report.limitations.contains { $0.contains("budget exhausted") })
  }
}
