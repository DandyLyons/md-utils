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

struct SurveyCommandsTests {
  @Test func vanillaSurveySelectsOverview() throws {
    let parsed = try CLIEntry.parseAsRoot(["survey", "./notes/"])
    #expect(parsed is SurveyCommand<SurveyOverview>)
  }
  @Test(arguments: ["overview", "coverage", "malformed-fm", "keys", "rules", "types", "standards", "uncovered", "overlaps", "type-matches", "relationships"])
  func focusedCommandsAreDiscoverable(_ metric: String) throws {
    let parsed = try CLIEntry.parseAsRoot(["survey", metric, "./notes/", "--json"])
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

  @Test func standardsAreExplicitlyUnsupported() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    let report = try await fixture.report("standards")
    #expect(report.complete == false)
    #expect(report.limitations.contains { $0.contains("standards") })
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
    try fixture.write("notes/invalid.md", "---\nother: value\n---\n")
    try fixture.write("outside.md", "outside")
    let overlap = try await fixture.report("overlaps")
    #expect(overlap.complete)
    #expect(overlap.metrics["overlaps"]?.objectValue?["total"] == .integer(1))
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
      ["survey", "coverage", "--format", "yaml"],
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
    let report = try await fixture.report("relationships", paths: [(fixture.root + "notes/").string], flags: ["--limit", "1"])
    #expect(report.complete)
    #expect(report.metrics["relationships"]?.objectValue?["ordinaryLinks"] != nil)
    #expect(report.metrics["relationships"]?.objectValue?["resolution"] != nil)
  }

  @Test func directAndCachedCoverageAgreeForBinaryAndMalformedFiles() async throws {
    let fixture = try SurveyFixture()
    defer { fixture.remove() }
    try fixture.write("notes/bad.md", "---\nx: [broken\n---\n")
    try fixture.write("notes/blob.bin", "binary\0bytes")
    try (fixture.root + ".md-utils/").mkpath()
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    _ = try CollectionIndexer(database: database, root: URL(fileURLWithPath: fixture.root.string))
    let paths = [(fixture.root + "notes/").string]
    let direct = try await fixture.report("coverage", paths: paths, flags: ["--no-index"])
    let cached = try await fixture.report("coverage", paths: paths)
    #expect(cached.complete)
    #expect(cached.coverage.files == direct.coverage.files)
    #expect(cached.coverage.skippedBinary == 1)
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
