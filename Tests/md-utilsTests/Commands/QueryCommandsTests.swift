import Foundation
import PathKit
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesCore
import Testing
@testable import md_utils

private actor QueryAnalysisCounter {
  var count = 0
  func increment() { count += 1 }
}

struct QueryCommandsTests {
  @Test func machinePathsPreserveControlsWhileTextEscapesThem() throws {
    let root = try fixture()
    defer { try? root.delete() }
    let path = root + "line\nbreak.md"
    try path.write("---\nStatus: unique\n---\n")
    let base = ["query", root.string, "--project-root", root.string, "--key", "Status", "--equals", "unique", "--no-index"]
    let text = try CLIProcessTestHelper.run(base)
    let nul = try CLIProcessTestHelper.run(base + ["--print0"])
    let json = try CLIProcessTestHelper.run(base + ["--oformat", "json"])
    #expect(text.status == 0 && nul.status == 0 && json.status == 0)
    #expect(text.standardOutput == path.string.replacingOccurrences(of: "\n", with: "\\n") + "\n")
    #expect(nul.standardOutput == path.string + "\0")
    #expect(json.standardOutput.contains("\u{1B}") == false)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(json.standardOutput.utf8))
    #expect(decoded.objectValue?["results"]?.objectValue?["paths"] == .array([.string(path.string)]))
    let invocation = CLIInvocation(argv: ["md-utils", "query", "O'Reilly", "$value"], workingDirectory: root.string)
    #expect(invocation.displayCommand == "md-utils query 'O'\\''Reilly' '$value'")
  }
  @Test func exclusionsDoNotRefreshABroaderCacheScope() throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + ".md-utils").mkpath()
    try (root + ".md-utils/index.sqlite").write("This cache must not be opened for an exclusion-pruned source query")
    let result = try CLIProcessTestHelper.run(["query", root.string, "--project-root", root.string, "--exclude", "b.md", "--key", "Status", "--equals", "read"])
    #expect(result.status == 0)
    #expect(result.standardError.isEmpty)
    #expect(result.standardOutput.trimmingCharacters(in: .newlines) == (root + "a.md").string)
  }
  @Test func filteringAndFrontmatterOutputShareOneAnalysis() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let command = try QueryFilter.parse([root.string, "--project-root", root.string, "--key", "Status", "--equals", "read", "--output", "frontmatter", "--no-index"])
    let counter = QueryAnalysisCounter()
    let report = try await QueryRunner.run(command, predicate: command.compile(), progress: nil, analyze: { record, requirements, kind in
      await counter.increment()
      #expect(requirements.isEmpty)
      return await MarkdownRecordAnalyzer.analyze(record, requirements: requirements, contentKind: kind)
    })
    #expect(await counter.count == 3)
    #expect(report.summary.matched == 1)
    #expect(report.complete)
  }
  @Test(arguments: [
    ["--json-path", "$..name", "--equals", "a"],
    ["--json-path", "$.a[0:2]", "--exists"],
    ["--key", "x", "--exists", "--match", "all"],
    ["--key", "x", "--equals", "true", "--vtype", "boolean", "--vformat", "Date"],
    ["--key", "x", "--equals", "a", "--case-sensitive", "--case-insensitive"],
    ["--key", "x", "--exists", "--output", "count", "--print0"],
    ["--is-type", "A", "--in-rule", "B"],
  ])
  func invalidRequestsFailBeforeScanning(_ flags: [String]) throws {
    let result = try CLIProcessTestHelper.run(["query", "/definitely-not-a-source"] + flags)
    #expect(result.status == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("outside --project-root") == false)
  }

  @Test func relationshipAliasesReuseExistingCommands() throws {
    let nested = try CLIProcessTestHelper.run(["query", "rel", "out", "--help"])
    let original = try CLIProcessTestHelper.run(["rel", "out", "--help"])
    #expect(nested.status == 0)
    #expect(nested.standardOutput.replacingOccurrences(of: "md-utils query relationships", with: "md-utils relationships") == original.standardOutput)
  }
  @Test func ruleSelectionDoesNotRequireValidFrontmatter() throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + ".md-utils/types").mkpath()
    try (root + ".md-utils/rules").mkpath()
    try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
    try (root + ".md-utils/types/empty.mdtype.json").write("{\"md-utils-type-schema\":\"1\",\"name\":\"Empty\",\"version\":\"1\",\"frontmatter\":{},\"body\":{\"requirements\":[],\"recommendations\":[]},\"context\":{\"requirements\":[],\"recommendations\":[]}}")
    try (root + ".md-utils/rules/all.mdrule.json").write("{\"name\":\"all\",\"match\":{\"paths\":[\"*.md\"]},\"types\":\"empty.mdtype.json\"}")
    try (root + "bad.md").write("---\nx: [\n---\n")
    let base = ["query", root.string, "--project-root", root.string, "--in-rule", "all", "--oformat", "json", "--no-index"]
    let paths = try CLIProcessTestHelper.run(base)
    #expect(paths.status == 0)
    #expect(paths.standardOutput.contains("bad.md"))
    let frontmatter = try CLIProcessTestHelper.run(base + ["--output", "frontmatter"])
    #expect(frontmatter.status == 1)
    #expect(frontmatter.standardOutput.contains("frontmatter-unavailable"))
    let type = try CLIProcessTestHelper.run(["query", (root + "c.md").string, "--project-root", root.string, "--is-type", "Empty", "--print0", "--no-index"])
    #expect(type.status == 0)
    #expect(type.standardOutput == (root + "c.md").string + "\0")
  }

  @Test func snapshotProjectionAvoidsDecodingUnselectedMappings() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + "large.md").write("---\nStatus: Read\nunrelated: '" + String(repeating: "x", count: 1_000_000) + "'\n---\n")
    try (root + ".md-utils").mkpath()
    let evaluator = try IndexProjectEvaluator(root: root, configPath: root + ".md-utils/md-utils.json")
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    let indexer = try CollectionIndexer(database: database, root: URL(fileURLWithPath: root.string))
    _ = try await indexer.updateMany(refreshing: [IndexScope(path: "", includeNonMarkdown: true)], fingerprint: evaluator.fingerprint, evaluate: evaluator.evaluate)
    let full = try FrontmatterIndexSnapshot.read(root: root, selections: [""], includeNonMarkdown: true)
    let selected = try FrontmatterIndexSnapshot.read(root: root, selections: [""], includeNonMarkdown: true, projection: .selected(["Status"]))
    #expect(selected.generation == full.generation)
    #expect(selected.observations.allSatisfy { $0.frontmatter?["unrelated"] == nil })
    #expect(selected.decodedBytes < 10_000)
    #expect(full.decodedBytes > 1_000_000)
  }
  @Test func publishedQueryEvidenceNeedsNoSourceFiles() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let evaluator = try IndexProjectEvaluator(root: root, configPath: root + ".md-utils/md-utils.json")
    try (root + ".md-utils").mkpath()
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    let indexer = try CollectionIndexer(database: database, root: URL(fileURLWithPath: root.string))
    _ = try await indexer.updateMany(refreshing: [IndexScope(path: "", includeNonMarkdown: true)], fingerprint: evaluator.fingerprint, evaluate: evaluator.evaluate)
    try (root + "a.md").delete()
    let result = try CLIProcessTestHelper.run(["query", root.string, "--project-root", root.string, "--key", "Status", "--equals", "read", "--index-only", "--print0"])
    #expect(result.status == 0)
    #expect(result.standardOutput == (root + "a.md").string + "\0")
  }
  @Test func dateModesAndTypedOutputPreserveSourceEvidence() throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + "date.md").write("---\ncreated: 2026-10-28T23:30:00-05:00\nscore: .inf\n---\n")
    let base = ["query", (root + "date.md").string, "--project-root", root.string, "--key", "created", "--same-day", "2026-10-28", "--vformat", "DateTime", "--timezone", "UTC", "--output", "frontmatter", "--oformat", "json", "--no-index"]
    let written = try CLIProcessTestHelper.run(base + ["--date-mode", "written"])
    try #require(written.status == 0, "\(written.standardError)")
    #expect(written.standardOutput.contains("positive-infinity"))
    #expect(written.standardOutput.contains("yaml-timestamp"))
    let normalized = try CLIProcessTestHelper.run(base)
    #expect(normalized.status == 0)
    #expect(normalized.standardOutput.contains("\"matched\":0"))
  }

  @Test func diagnosticAndResultCapsDoNotStopEvaluation() throws {
    let root = try fixture()
    defer { try? root.delete() }
    for index in 0..<3 { try (root + "bad\(index).md").write("---\nx: [\n---\n") }
    let result = try CLIProcessTestHelper.run(["query", root.string, "--project-root", root.string, "--missing-key", "other", "--limit", "1", "--diagnostic-limit", "1", "--oformat", "json", "--no-index"])
    #expect(result.status == 1)
    let report = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
    let summary = try #require(report["summary"] as? [String: Any])
    #expect(summary["matched"] as? Int == 3)
    #expect(summary["unknown"] as? Int == 3)
    #expect(summary["omitted"] as? Int == 2)
    #expect(summary["diagnosticsOmitted"] as? Int == 2)
  }
  private func fixture() throws -> Path {
    let root = Path.current.absolute() + "tmp/query-tests-\(UUID().uuidString)"
    try root.mkpath()
    try (root + "a.md").write("---\nStatus: Read\nprices: [2, 20]\nrating: 3.0\n---\nA")
    try (root + "b.md").write("---\nStatus: unread\nprices: [7]\nrating: '3'\n---\nB")
    try (root + "c.md").write("No metadata")
    return root
  }

  @Test func filtersDocumentsAndRetainsInvocation() throws {
    let root = try fixture()
    defer { try? root.delete() }
    let arguments = ["query", root.string, "--project-root", root.string, "--key", "Status", "--equals", "read", "--oformat", "json", "--no-index"]
    let result = try CLIProcessTestHelper.run(arguments)
    try #require(result.status == 0, "\(result.standardError)")
    let report = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
    let results = try #require(report["results"] as? [String: Any])
    #expect(results["paths"] as? [String] == [(root + "a.md").string])
    let query = try #require(report["query"] as? [String: Any])
    let invocation = try #require(query["invocation"] as? [String: Any])
    #expect(Array((invocation["argv"] as? [String] ?? []).dropFirst()) == arguments)
  }

  @Test func rangeMustMatchOneNode() throws {
    let root = try fixture()
    defer { try? root.delete() }
    let result = try CLIProcessTestHelper.run(["query", root.string, "--project-root", root.string, "--json-path", "$.prices[*]", "--greater-than", "5", "--less-than", "10", "--vtype", "number", "--print0", "--no-index"])
    #expect(result.status == 0)
    #expect(result.standardOutput == (root + "b.md").string + "\0")
  }

  @Test func missingMatchesAbsentFrontmatter() throws {
    let root = try fixture()
    defer { try? root.delete() }
    let result = try CLIProcessTestHelper.run(["query", root.string, "--project-root", root.string, "--missing-key", "Status", "--output", "frontmatter", "--oformat", "json", "--no-index"])
    try #require(result.status == 0, "\(result.standardError)")
    let report = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
    let results = try #require(report["results"] as? [String: Any])
    #expect(results["noFrontMatter"] as? [String] == [(root + "c.md").string])
  }

  @Test func impossibleIntegerRangeFailsBeforeScopeDiscovery() throws {
    let result = try CLIProcessTestHelper.run(["query", "/does-not-exist", "--key", "rating", "--greater-than", "3", "--less-than", "4", "--vtype", "integer"])
    #expect(result.status == 64)
    #expect(result.standardError.contains("range"))
    #expect(result.standardOutput.isEmpty)
  }
}
