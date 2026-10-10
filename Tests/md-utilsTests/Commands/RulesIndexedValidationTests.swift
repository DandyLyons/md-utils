import ArgumentParser
import Foundation
import GRDB
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit
import Testing
@testable import md_utils

private struct RulesIndexFixture {
  let root: Path
  var config: Path { root + ".md-utils/md-utils.json" }
  var databasePath: Path { root + ".md-utils/index.sqlite" }

  init(version: String = "0.3.0") throws {
    root = Path(#filePath).parent().parent().parent().parent() + "tmp/rules-index-\(UUID().uuidString)/"
    try (root + ".md-utils/rules/").mkpath()
    try (root + ".md-utils/types/").mkpath()
    try (root + ".md-utils/schemas/").mkpath()
    try (root + "notes/").mkpath()
    try write(".md-utils/types/book.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Book","version":"1",
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try write(".md-utils/rules/books.mdrule.json", """
      {"name":"books","match":{"paths":["notes/**"]},"types":"book.mdtype.json"}
      """)
    try write(".md-utils/schemas/book.json", "{\"type\":\"object\",\"required\":[\"title\"]}")
    if version == "0.3.0" {
      try config.write("{\"configVersion\":\"0.3.0\"}")
    } else if version == "0.2.0" {
      try config.write("""
        {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
          {"name":"books","match":{"paths":["notes/**"]},
           "checks":[{"type":"frontmatterSchema","schema":"book.json","frontmatterRequired":false}]}]}
        """)
    } else {
      try config.write("""
        {"configVersion":"0.1.0","schemaDirectory":".md-utils/schemas/","schemaRules":[
          {"name":"books","schema":"book.json","frontmatterRequired":false,"match":{"paths":["notes/**"]}}]}
        """)
    }
  }

  func write(_ path: String, _ content: String) throws { try (root + path).write(content) }
  func remove() { try? root.delete() }
  func database() throws -> SQLiteIndexDatabase {
    let db = try SQLiteIndexDatabase(path: databasePath.string)
    try db.prepareCollection(root: URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path)
    return db
  }
  func validate(rule: String? = "books", noIndex: Bool = false, verifyHashes: Bool = false,
    indexedOnly: Bool = false,
    includeNonMarkdown: Bool = false, warning: (String) -> Void = { _ in },
  ) async throws -> RuleValidationSummary {
    try await RulesValidatorRunner.validate(ruleName: rule, includeNonMarkdown: includeNonMarkdown,
      root: root, configPath: config, projectRoot: root, noIndex: noIndex, indexedOnly: indexedOnly, verifyHashes: verifyHashes, warning: warning)
  }
}

struct RulesIndexedValidationTests {
  @Test func `indexed only omits new paths reuses candidates and retains limited freshness`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    _ = try fixture.database()
    _ = try await fixture.validate()
    try fixture.write("notes/new.md", "---\nother: New\n---\n")
    let unchanged = try await fixture.validate(indexedOnly: true)
    #expect(unchanged.totalFiles == 1)
    #expect(try #require(unchanged.indexReport).cached == 1)
    #expect(RuleValidationSummaryFormatter.render(unchanged).contains("New files were not discovered."))
    #expect(try fixture.database().freshness().scopes.first?.state == "limited")
    let repeated = try await fixture.validate(indexedOnly: true)
    #expect(try #require(repeated.indexReport).hashed == 0)
    try fixture.write("notes/one.md", "---\nother: Changed\n---\n")
    #expect(try await fixture.validate(indexedOnly: true).hasFailures)
    try (fixture.root + "notes/one.md").move(fixture.root + "notes/renamed.md")
    let deleted = try await fixture.validate(indexedOnly: true)
    #expect(deleted.hasFailures)
    #expect(deleted.results.map(\.filePath) == ["notes/one.md"])
    #expect(try await fixture.validate().totalFiles == 2)
  }

  @Test func `indexed only requires existing registered scopes and never falls back`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    await #expect(throws: (any Error).self) { try await fixture.validate(indexedOnly: true) }
    _ = try fixture.database()
    await #expect(throws: (any Error).self) { try await fixture.validate(indexedOnly: true) }
    await #expect(throws: (any Error).self) { try await fixture.validate(noIndex: true, indexedOnly: true) }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    _ = try await fixture.validate()
    await #expect(throws: (any Error).self) {
      try await fixture.validate(indexedOnly: true, includeNonMarkdown: true)
    }
    try fixture.write(".md-utils/rules/also.mdrule.json", "{\"name\":\"also\",\"types\":\"book.mdtype.json\"}")
    let all = try await fixture.validate(rule: nil, indexedOnly: true)
    #expect(all.uncoveredRules == ["also"])
    #expect(try #require(all.indexReport).evaluated == 1)
    try Data([0xff]).write(to: URL(fileURLWithPath: (fixture.root + "notes/one.md").string))
    let unreadable = try await fixture.validate(indexedOnly: true)
    #expect(unreadable.hasFailures)
    #expect(unreadable.indexReport != nil)
  }

  @Test func `indexed only rejects symlink replaced known candidates`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    _ = try fixture.database()
    _ = try await fixture.validate()
    try (fixture.root + "notes/").move(fixture.root + "moved/")
    try FileManager.default.createSymbolicLink(atPath: URL(fileURLWithPath: (fixture.root + "notes/").string).path,
      withDestinationPath: (fixture.root + "moved/").string)
    let result = try await fixture.validate(indexedOnly: true)
    #expect(result.hasFailures)
    #expect(result.results.first?.errors.first?.message.contains("symlink") == true)
  }

  @Test func `indexed only verifies hashes and rechecks prior nonmembers after definitions change`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    let file = fixture.root + "notes/one.md"
    try file.write("---\ntitle: One\n---\n")
    // Use the broad path selector first to establish a recorded candidate baseline.
    try fixture.write(".md-utils/rules/books.mdrule.json", "{\"name\":\"books\",\"match\":{\"paths\":[\"notes/**\"]},\"types\":\"book.mdtype.json\"}")
    // Whole-second timestamps avoid precision loss when Foundation restores mtime.
    let modified = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.string)
    _ = try fixture.database()
    _ = try await fixture.validate()
    try file.write("---\nother: One\n---\n")
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.string)
    #expect(try await fixture.validate(indexedOnly: true).hasFailures == false)
    #expect(try await fixture.validate(verifyHashes: true, indexedOnly: true).hasFailures)
    try fixture.write(".md-utils/rules/books.mdrule.json", "{\"name\":\"books\",\"match\":{\"paths\":[\"elsewhere/**\"]},\"types\":\"book.mdtype.json\"}")
    #expect(try await fixture.validate(indexedOnly: true).results.isEmpty)
    try fixture.write(".md-utils/rules/books.mdrule.json", "{\"name\":\"books\",\"types\":\"book.mdtype.json\"}")
    let broader = try await fixture.validate(indexedOnly: true)
    #expect(broader.totalFiles == 1)
    #expect(broader.hasFailures)
  }
  @Test func `positive rule paths avoid irrelevant trees and missing prefixes prune old members`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    try fixture.write("outside.md", "---\ntitle: [broken\n---\n")
    let direct = try await fixture.validate(noIndex: true)
    #expect(direct.totalFiles == 1)
    _ = try fixture.database()
    var warnings: [String] = []
    let indexed = try await fixture.validate(warning: { warnings.append($0) })
    #expect(indexed.totalFiles == 1)
    #expect(warnings.isEmpty)
    #expect(try #require(indexed.indexReport).evaluated == 1)
    try (fixture.root + "notes/").delete()
    let missing = try await fixture.validate()
    #expect(missing.results.isEmpty)
    #expect(missing.indexReport != nil)
    #expect(try fixture.database().selectedPaths().isEmpty)
  }

  @Test(arguments: [false, true])
  func `nonstandard config uses explicit root and cancellation never falls back`(indexedOnly: Bool) async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    let customConfig = fixture.root + "settings.json"
    try fixture.config.move(customConfig)
    _ = try fixture.database()
    let summary = try await RulesValidatorRunner.validate(ruleName: "books", configPath: customConfig, projectRoot: fixture.root)
    #expect(summary.indexReport != nil)
    #expect(summary.hasFailures == false)
    #expect(try fixture.database().configurationPath() == customConfig.string)
    let generation = try fixture.database().freshness().generation
    let configString = customConfig.string
    let rootString = fixture.root.string
    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      var warnings: [String] = []
      do {
        _ = try await RulesValidatorRunner.validate(ruleName: "books", configPath: Path(configString),
          projectRoot: Path(rootString), indexedOnly: indexedOnly, warning: { warnings.append($0) })
        Issue.record("Expected cancellation")
      } catch is CancellationError {
        #expect(warnings.isEmpty)
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
    await cancelled.value
    #expect(try fixture.database().freshness().generation == generation)
  }

  @Test(arguments: [false, true])
  func `superseded validation snapshot rejects a newer writer generation`(indexedOnly: Bool) async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    let db = try fixture.database()
    _ = try await fixture.validate()
    let first = try await fixture.validate(indexedOnly: indexedOnly)
    let report = try #require(first.indexReport)
    _ = try await fixture.validate()
    let evaluator = try IndexProjectEvaluator(root: fixture.root, configPath: fixture.config)
    #expect(throws: IndexProjectError.self) {
      try IndexedRuleValidation.snapshot(database: db, scopes: [IndexScope(kind: .rule, name: "books")],
        fingerprint: evaluator.fingerprint, report: report, indexedOnly: indexedOnly)
    }
  }

  @Test func `incompatible cache and declaration drift fall back without overwriting settings`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    _ = try fixture.database()
    _ = try await fixture.validate()
    var settings = try IndexConfiguration.load(root: fixture.root.string)
    settings.bodyMode = .fts
    try settings.save(root: fixture.root.string)
    var warnings: [String] = []
    let fallback = try await fixture.validate(warning: { warnings.append($0) })
    #expect(fallback.indexReport == nil)
    #expect(warnings.first?.contains("--rebuild") == true)
    #expect(try IndexConfiguration.load(root: fixture.root.string) == settings)
    await #expect(throws: (any Error).self) { try await fixture.validate(indexedOnly: true) }
    try await DatabaseQueue(path: fixture.databasePath.string).write { db in
      try db.execute(sql: "UPDATE index_metadata SET value='incompatible' WHERE key='format'")
    }
    warnings.removeAll()
    let incompatible = try await fixture.validate(warning: { warnings.append($0) })
    #expect(incompatible.indexReport == nil)
    #expect(incompatible.hasFailures == false)
    #expect(warnings.first?.contains("--rebuild") == true)
    await #expect(throws: (any Error).self) { try await fixture.validate(indexedOnly: true) }
  }

  @Test func `non UTF8 source fails direct fallback rather than validating stale content`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    _ = try fixture.database()
    _ = try await fixture.validate()
    try Data([0xff, 0xfe]).write(to: URL(fileURLWithPath: (fixture.root + "notes/one.md").string))
    var warnings: [String] = []
    do {
      _ = try await fixture.validate(warning: { warnings.append($0) })
      Issue.record("Expected authoritative source read failure")
    } catch {
      #expect(warnings.count == 1)
      #expect(warnings.first?.contains("validating source files directly") == true)
    }
  }

  @Test func `symlink files and directories are excluded from both validation paths`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    try FileManager.default.createSymbolicLink(atPath: (fixture.root + "notes/link.md").string,
      withDestinationPath: (fixture.root + "notes/one.md").string)
    try FileManager.default.createSymbolicLink(atPath: URL(fileURLWithPath: (fixture.root + "linked/").string).path,
      withDestinationPath: (fixture.root + "notes/").string)
    let direct = try await fixture.validate(noIndex: true)
    _ = try fixture.database()
    let indexed = try await fixture.validate()
    #expect(direct.totalFiles == 1)
    #expect(indexed.totalFiles == 1)
    #expect(indexed.results.map(\.filePath) == direct.results.map(\.filePath))
  }

  @Test func `CLI parses automatic index controls`() throws {
    let command = try #require(CLIEntry.parseAsRoot([
      "rules", "validate", "books", "--no-index", "--verify-hashes",
    ]) as? CLIEntry.RulesCommands.Validate)
    #expect(command.noIndex)
    #expect(command.verifyHashes)
    let limited = try #require(CLIEntry.parseAsRoot([
      "rules", "validate", "books", "--indexed-only", "--verify-hashes",
    ]) as? CLIEntry.RulesCommands.Validate)
    #expect(limited.indexedOnly)
  }

  @Test(arguments: ["0.1.0", "0.2.0", "0.3.0"])
  func `indexed reports match direct reports including skipped and failed records`(version: String) async throws {
    let fixture = try RulesIndexFixture(version: version)
    defer { fixture.remove() }
    try fixture.write("notes/good.md", "---\ntitle: Good\n---\n# Good")
    try fixture.write("notes/bad.md", "---\nother: true\n---\n# Bad")
    try fixture.write("notes/absent.md", "# Absent")
    try fixture.write("outside.md", "# Outside")
    let direct = try await fixture.validate()
    #expect(direct.indexReport == nil)
    #expect(fixture.databasePath.exists == false)
    _ = try fixture.database()
    var warnings: [String] = []
    let initial = try await fixture.validate(warning: { warnings.append($0) })
    #expect(warnings.isEmpty)
    let initialReport = try #require(initial.indexReport)
    #expect(initialReport.evaluated == 3)
    #expect(initial.totalFiles == direct.totalFiles)
    #expect(initial.errors == direct.errors)
    #expect(initial.hasFailures == direct.hasFailures)
    #expect(RuleValidationSummaryFormatter.render(initial, includeOk: true)
      == RuleValidationSummaryFormatter.render(direct, includeOk: true))
    let unchanged = try await fixture.validate()
    let report = try #require(unchanged.indexReport)
    #expect(report.evaluated == 0)
    #expect(report.hashed == 0)
    #expect(report.cached == 3)
    #expect(try fixture.database().scopes() == [IndexScope(kind: .rule, name: "books")])
  }

  @Test func `refresh handles edits creation deletion and definition changes`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    try fixture.write("notes/two.md", "---\ntitle: Two\n---\n")
    _ = try fixture.database()
    _ = try await fixture.validate()
    try fixture.write("notes/one.md", "---\nother: changed\n---\n")
    try (fixture.root + "notes/two.md").delete()
    try fixture.write("notes/three.md", "---\ntitle: Three\n---\n")
    let changed = try await fixture.validate()
    #expect(changed.results.map(\.filePath) == ["notes/one.md", "notes/three.md"])
    #expect(changed.hasFailures)
    #expect(try #require(changed.indexReport).evaluated == 2)
    try fixture.write(".md-utils/types/book.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Book","version":"2",
       "frontmatter":{"schemas":[]},"body":{"requirements":[],"recommendations":[]},
       "context":{"requirements":[],"recommendations":[]}}
      """)
    let revised = try await fixture.validate()
    #expect(revised.hasFailures == false)
    #expect(try #require(revised.indexReport).evaluated == 2)
  }

  @Test func `hash verification catches stat preserving edits and bypass leaves cache untouched`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    let file = fixture.root + "notes/one.md"
    try file.write("---\ntitle: One\n---\n")
    _ = try fixture.database()
    _ = try await fixture.validate()
    let attributes = try FileManager.default.attributesOfItem(atPath: file.string)
    let modified = try #require(attributes[.modificationDate] as? Date)
    try file.write("---\nother: One\n---\n")
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.string)
    let before = try fixture.database().freshness().generation
    let direct = try await fixture.validate(noIndex: true)
    #expect(direct.hasFailures)
    #expect(direct.indexReport == nil)
    #expect(try fixture.database().freshness().generation == before)
    let verified = try await fixture.validate(verifyHashes: true)
    #expect(verified.hasFailures)
    #expect(try #require(verified.indexReport).hashed == 1)
  }

  @Test func `corrupt index falls back without changing direct results`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    let direct = try await fixture.validate(noIndex: true)
    try fixture.databasePath.write("not SQLite")
    var warnings: [String] = []
    let fallback = try await fixture.validate(warning: { warnings.append($0) })
    #expect(fallback.indexReport == nil)
    #expect(fallback.hasFailures == false)
    #expect(warnings.count == 1)
    #expect(warnings.first?.contains("validating source files directly") == true)
    #expect(RuleValidationSummaryFormatter.render(fallback, includeOk: true)
      == RuleValidationSummaryFormatter.render(direct, includeOk: true))
    await #expect(throws: (any Error).self) { try await fixture.validate(indexedOnly: true) }
  }

  @Test func `parse errors fall back and remain validation errors`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: [broken\n---\n")
    let direct = try await fixture.validate(noIndex: true)
    _ = try fixture.database()
    var warnings: [String] = []
    let fallback = try await fixture.validate(warning: { warnings.append($0) })
    #expect(fallback.hasFailures)
    #expect(fallback.indexReport == nil)
    #expect(warnings.count == 1)
    #expect(RuleValidationSummaryFormatter.render(fallback, includeOk: true)
      == RuleValidationSummaryFormatter.render(direct, includeOk: true))
  }

  @Test func `all rules and non Markdown inclusion keep independent scopes`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/rules/also.mdrule.json", "{\"name\":\"also\",\"types\":\"book.mdtype.json\"}")
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    try fixture.write("notes/host.swift", "/*\n---\ntitle: Host\n---\n*/\nlet x = 1")
    _ = try fixture.database()
    let markdown = try await fixture.validate(rule: nil)
    #expect(markdown.results.count == 2)
    let included = try await fixture.validate(rule: nil, includeNonMarkdown: true)
    let direct = try await fixture.validate(rule: nil, noIndex: true, includeNonMarkdown: true)
    #expect(try #require(included.indexReport).evaluated == 4)
    #expect(RuleValidationSummaryFormatter.render(included, includeOk: true)
      == RuleValidationSummaryFormatter.render(direct, includeOk: true))
    #expect(try fixture.database().scopes().count == 4)
  }

  @Test func `unrelated missing scope does not prevent indexed rule validation`() async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    try fixture.write("notes/one.md", "---\ntitle: One\n---\n")
    let db = try fixture.database()
    let evaluator = try IndexProjectEvaluator(root: fixture.root, configPath: fixture.config)
    let indexer = try CollectionIndexer(database: db, root: URL(fileURLWithPath: fixture.root.string))
    _ = try await indexer.update(adding: IndexScope(path: "missing/"), fingerprint: evaluator.fingerprint, evaluate: evaluator.evaluate)
    var warnings: [String] = []
    let summary = try await fixture.validate(warning: { warnings.append($0) })
    #expect(summary.indexReport != nil)
    #expect(summary.hasFailures == false)
    #expect(warnings.isEmpty)
    #expect(try db.freshness().scopes.contains { $0.definition.path == "missing/" && $0.state == "incomplete" })
  }

  @Test(arguments: [1_000, 1_001])
  func `uncached advisory starts above one thousand files`(count: Int) async throws {
    let fixture = try RulesIndexFixture()
    defer { fixture.remove() }
    for index in 0..<count { try fixture.write("notes/\(index).md", "---\ntitle: Book\n---\n") }
    var warnings: [String] = []
    let summary = try await fixture.validate(warning: { warnings.append($0) })
    #expect(summary.totalFiles == count)
    #expect(warnings.count == (count > 1_000 ? 1 : 0))
    #expect(fixture.databasePath.exists == false)
    if count > 1_000 {
      #expect(warnings.first?.contains("md-utils index rule 'books'") == true)
      #expect(warnings.first?.contains("--project-root") == true)
    }
  }
}
