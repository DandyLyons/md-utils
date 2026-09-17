import ArgumentParser
import Foundation
import GRDB
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit
import Testing
@testable import md_utils

private struct IndexCommandFixture {
    let root: Path
    var config: Path { root + ".md-utils/md-utils.json" }
    var databasePath: Path { root + ".md-utils/index.sqlite" }

    init() throws {
        root = Path.current.absolute() + "tmp/index-command-\(UUID().uuidString)/"
        try (root + ".md-utils/types/").mkpath()
        try (root + ".md-utils/rules/").mkpath()
        try (root + "notes/").mkpath()
        try config.write("{\"configVersion\":\"0.3.0\"}")
        try (root + ".md-utils/types/book.mdtype.json").write("""
            {"md-utils-type-schema":"1","name":"Book","version":"1",
             "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
             "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
            """)
        try (root + ".md-utils/rules/books.mdrule.json").write("""
            {"name":"books","match":{"paths":["notes/**"]},"types":"book.mdtype.json"}
            """)
    }

    func write(_ name: String, _ content: String) throws { try (root + name).write(content) }
    func remove() { try? root.delete() }
    func evaluator() throws -> IndexProjectEvaluator { try IndexProjectEvaluator(root: root, configPath: config) }
    func database() throws -> SQLiteIndexDatabase { try SQLiteIndexDatabase(path: databasePath.string) }
    func read<T>(_ action: (Database) throws -> T) throws -> T { try DatabaseQueue(path: databasePath.string).read(action) }
}

@Suite("Index commands")
struct IndexCommandsTests {
    @Test func `CLI registers scopes refreshes and rebuilds in place`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write("notes/book.md", "---\ntitle: Book\n---\n# Book")
        var create = try #require(CLIEntry.parseAsRoot(["index", "update", (fixture.root + "notes/").string,
            "--project-root", fixture.root.string]) as? CLIEntry.Index.Update)
        try await create.run()
        var refresh = try #require(CLIEntry.parseAsRoot(["index", "update", "--project-root", fixture.root.string,
            "--rebuild", "--verify-hashes"]) as? CLIEntry.Index.Update)
        try await refresh.run()
        #expect(try fixture.database().selectedPaths() == ["notes/book.md"])
        #expect(try fixture.database().scopes() == [IndexScope(path: "notes/")])
        #expect(try fixture.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM documents_fts") } == 1)
    }

    @Test func `type index equals types find and overlapping conformance stays independent`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write("notes/good.md", "---\ntitle: Book\n---\n# Book")
        try fixture.write("notes/bad.md", "No title")
        try fixture.write(".md-utils/types/other.mdtype.json", """
            {"md-utils-type-schema":"1","name":"Other","version":"1","frontmatter":{"schemas":[]},
             "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
            """)
        var command = try #require(CLIEntry.parseAsRoot(["index", "type", "Book", (fixture.root + "notes/").string,
            "--project-root", fixture.root.string]) as? CLIEntry.Index.SelectType)
        try await command.run()
        let expected = try await TypesRunner.assess(typeName: "Book", files: [(fixture.root + "notes/good.md"),
            (fixture.root + "notes/bad.md")], root: fixture.root).filter(\.assessment.conforms)
            .map { relativePath(from: fixture.root, to: $0.file) }.sorted()
        let book = IndexScope(kind: .type, path: "notes/", name: "Book")
        #expect(try fixture.database().selectedPaths(scope: book) == expected)
        command.name = "Other"
        try await command.run()
        try fixture.write("notes/good.md", "Now missing title")
        var refresh = try #require(CLIEntry.parseAsRoot(["index", "update", "--project-root", fixture.root.string]) as? CLIEntry.Index.Update)
        try await refresh.run()
        #expect(try fixture.database().selectedPaths(scope: book).isEmpty)
        #expect(try fixture.database().selectedPaths().count == 2)
        #expect(try fixture.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM assessments WHERE selected=0") } == 2)
    }

    @Test func `rule retains invalid members and full branch evidence without treating nonmembers as selected`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write("notes/good.md", "---\ntitle: Book\n---\n# Book")
        try fixture.write("notes/bad.md", "No title")
        try fixture.write("outside.md", "No match")
        var command = try #require(CLIEntry.parseAsRoot(["index", "rule", "books", "--config", fixture.config.string]) as? CLIEntry.Index.SelectRule)
        try await command.run()
        let expected = try await RulesValidatorRunner.filesMatching(ruleName: "books", configPath: fixture.config)
            .map { relativePath(from: fixture.root, to: $0) }.sorted()
        #expect(try fixture.database().selectedPaths() == expected)
        #expect(expected == ["notes/bad.md", "notes/good.md"])
        #expect(try fixture.read { try String.fetchOne($0, sql: "SELECT status FROM assessments WHERE path='notes/bad.md'") } == "failed")
        let detail = try #require(fixture.read { try String.fetchOne($0, sql: "SELECT detail FROM assessments WHERE path='notes/bad.md'") })
        let object = try #require(JSONSerialization.jsonObject(with: Data(detail.utf8)) as? [String: Any])
        #expect((object["typeExpression"] as? [String: Any])?["status"] as? String == "notMatched")
    }

    @Test func `transitive schema and definition changes invalidate untouched files`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try (fixture.root + "schemas/").mkpath()
        try fixture.write("schemas/parent.json", "{\"$ref\":\"child.json\"}")
        try fixture.write("schemas/child.json", "{\"type\":\"object\",\"required\":[\"title\"]}")
        try fixture.write(".md-utils/types/book.mdtype.json", """
            {"md-utils-type-schema":"1","name":"Book","version":"1",
             "frontmatter":{"schemas":[{"ref":"../../schemas/parent.json"}]},
             "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
            """)
        try fixture.write("notes/good.md", "---\ntitle: Book\n---\n# Book")
        let before = try fixture.evaluator()
        let db = try fixture.database()
        let indexer = try CollectionIndexer(database: db, root: URL(fileURLWithPath: fixture.root.string))
        let scope = IndexScope(kind: .type, path: "notes/", name: "Book")
        _ = try await indexer.update(adding: scope, fingerprint: before.fingerprint, evaluate: before.evaluate)
        try fixture.write("schemas/child.json", "{\"type\":\"object\",\"required\":[\"author\"]}")
        let after = try fixture.evaluator()
        #expect(before.fingerprint != after.fingerprint)
        let report = try await indexer.update(fingerprint: after.fingerprint, evaluate: after.evaluate)
        #expect(report.evaluated == 1)
        #expect(try db.selectedPaths().isEmpty)
        try fixture.write(".md-utils/rules/books.mdrule.json", "{\"name\":\"books\",\"types\":\"book.mdtype.json\"}")
        #expect(try fixture.evaluator().fingerprint != after.fingerprint)
        #expect(IndexFingerprint.combined(["new evaluator", after.fingerprint]) != after.fingerprint)
    }

    @Test func `path moves and mtime predicates use fresh native context`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write(".md-utils/rules/books.mdrule.json", """
            {"name":"books","match":{"allOf":[{"paths":["notes/**"]},{"file":{"modifiedAfter":"2020-01-01"}}]},"types":"book.mdtype.json"}
            """)
        try fixture.write("notes/book.md", "---\ntitle: Book\n---\n")
        var command = try #require(CLIEntry.parseAsRoot(["index", "rule", "books", "--project-root", fixture.root.string]) as? CLIEntry.Index.SelectRule)
        try await command.run()
        #expect(try fixture.database().selectedPaths() == ["notes/book.md"])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: (fixture.root + "notes/book.md").string)
        try await command.run()
        #expect(try fixture.database().selectedPaths().isEmpty)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: (fixture.root + "notes/book.md").string)
        try (fixture.root + "notes/book.md").move(fixture.root + "outside.md")
        try await command.run()
        #expect(try fixture.database().selectedPaths().isEmpty)
        #expect(try fixture.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM files WHERE path='notes/book.md'") } == 0)
    }

    @Test func `extraction reuses YAML TOML wrappers and line comments and reports parse failure`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        let evaluator = try fixture.evaluator()
        let scope = IndexScope(kind: .rule, name: "books", includeNonMarkdown: true)
        for (path, content) in [
            ("notes/yaml.md", "---\ntitle: YAML\n---\nbody"),
            ("notes/toml.md", "+++\ntitle = \"TOML\"\n+++\nbody"),
            ("notes/file.swift", "/*\n---\ntitle: Swift\n---\n*/\nlet x = 1"),
            ("notes/file.sh", "# ---\n# title: Shell\n# ---\necho body"),
        ] {
            let result = try await evaluator.evaluate(scope: scope, path: path, content: content, modified: Date())
            #expect(result.parseState == "ok")
            #expect(result.assessment.selected)
            #expect(result.assessment.status == "passed")
            #expect(result.metadata.contains("title"))
        }
        let malformed = try await evaluator.evaluate(scope: scope, path: "notes/bad.md", content: "---\ntitle: [\n---\nbody", modified: Date())
        #expect(malformed.parseState == "error")
        #expect(malformed.assessment.selected)
        #expect(malformed.assessment.status == "evaluation-error")
        #expect(malformed.assessment.diagnostics.contains { $0.category == "parse" })
    }

    @Test func `legacy JMESPath matching uses native query provider`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write(".md-utils/md-utils.json", """
            {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
              {"name":"query","match":{"paths":["notes/**"],"frontmatterQuery":{"jmespath":"title == 'Book'"}},
               "checks":[{"type":"requiredHeading","heading":"Book"}]}]}
            """)
        let evaluator = try fixture.evaluator()
        let selected = try await evaluator.evaluate(scope: IndexScope(kind: .rule, name: "query"), path: "notes/book.md",
            content: "---\ntitle: Book\n---\n", modified: Date())
        #expect(selected.assessment.selected)
        let other = try await evaluator.evaluate(scope: IndexScope(kind: .rule, name: "query"), path: "notes/other.md",
            content: "---\ntitle: Other\n---\n", modified: Date())
        #expect(!other.assessment.selected)
    }

    @Test func `custom config is persisted and failed reload invalidates old current rows`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write("notes/book.md", "---\ntitle: Book\n---\n")
        try fixture.config.move(fixture.root + "custom.json")
        var command = try #require(CLIEntry.parseAsRoot(["index", "rule", "books", "--config", (fixture.root + "custom.json").string,
            "--project-root", fixture.root.string]) as? CLIEntry.Index.SelectRule)
        try await command.run()
        #expect(try fixture.database().configurationPath() == (fixture.root + "custom.json").string)
        var update = try #require(CLIEntry.parseAsRoot(["index", "update", "--project-root", fixture.root.string]) as? CLIEntry.Index.Update)
        try await update.run()
        try fixture.write("custom.json", "invalid")
        await #expect(throws: (any Error).self) { try await update.run() }
        var query = try #require(CLIEntry.parseAsRoot(["index", "query", "SELECT path FROM current_documents",
            "--project-root", fixture.root.string]) as? CLIEntry.Index.Query)
        await #expect(throws: (any Error).self) { try await query.run() }
        #expect(try fixture.database().selectedPaths().isEmpty)
        #expect(try fixture.read { try String.fetchOne($0, sql: "SELECT state FROM scopes") } == "incomplete")
    }

    @Test func `query refreshes before read only SQL and exposes field and freshness commands`() async throws {
        let fixture = try IndexCommandFixture()
        defer { fixture.remove() }
        try fixture.write("notes/book.md", "---\ntitle: First\nstatus: draft\n---\nold body")
        var update = try #require(CLIEntry.parseAsRoot(["index", "update", (fixture.root + "notes/").string,
            "--project-root", fixture.root.string]) as? CLIEntry.Index.Update)
        try await update.run()
        try fixture.write("notes/book.md", "---\ntitle: Updated\nstatus: published\n---\nnew body")

        let query = try CLIProcessTestHelper.run(["index", "query",
            "SELECT json_extract(metadata, '$.title') AS title, body FROM current_documents",
            "--project-root", fixture.root.string], workingDirectory: URL(fileURLWithPath: fixture.root.string))
        #expect(query.status == 0)
        let output = try #require(JSONSerialization.jsonObject(with: Data(query.standardOutput.utf8)) as? [String: Any])
        #expect(output["columns"] as? [String] == ["title", "body"])
        let rows = try #require(output["rows"] as? [[Any]])
        #expect(rows.first?[0] as? String == "Updated")
        #expect(rows.first?[1] as? String == "new body")

        let mutation = try CLIProcessTestHelper.run(["index", "query", "DELETE FROM documents",
            "--project-root", fixture.root.string], workingDirectory: URL(fileURLWithPath: fixture.root.string))
        #expect(mutation.status != 0)
        #expect(mutation.standardError.contains("read-only"))
        #expect(try fixture.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM documents") } == 1)

        let field = try CLIProcessTestHelper.run(["index", "field", "add", "$.status",
            "--project-root", fixture.root.string], workingDirectory: URL(fileURLWithPath: fixture.root.string))
        #expect(field.status == 0)
        #expect(field.standardOutput.contains("json_extract(metadata, '$.status')"))
        let status = try CLIProcessTestHelper.run(["index", "status", "--project-root", fixture.root.string],
            workingDirectory: URL(fileURLWithPath: fixture.root.string))
        #expect(status.status == 0)
        #expect(status.standardOutput.contains("current: yes"))
    }

    @Test func `query renderers preserve machine readable shapes`() throws {
        let result = IndexQueryResult(columns: ["name", "count"],
            rows: [[.text("a,b"), .integer(2)], [.text("quoted \"value\""), .null]], truncated: false)
        let jsonl = try IndexQueryRenderer.render(result, format: .jsonl)
        #expect(jsonl.contains("{\"count\":2,\"name\":\"a,b\"}"))
        let csv = try IndexQueryRenderer.render(result, format: .csv)
        #expect(csv == "name,count\n\"a,b\",2\n\"quoted \"\"value\"\"\",\n")
        #expect(throws: (any Error).self) {
            try IndexQueryRenderer.render(IndexQueryResult(columns: ["value", "value"], rows: [], truncated: false), format: .jsonl)
        }
    }
}
