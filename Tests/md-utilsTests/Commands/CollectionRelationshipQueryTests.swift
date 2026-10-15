import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit
import Testing
import Yams
@testable import md_utils

/// Each query uses an isolated collection; fixtures never depend on the caller's cwd.
private struct QueryFixture {
  let root: Path
  init() throws {
    root = Path(#filePath).parent().parent().parent().parent() + "tmp/query-188-\(UUID().uuidString)/"
    try root.mkpath()
  }
  func write(_ path: String, _ content: String) throws {
    try (root + path).parent().mkpath()
    try (root + path).write(content)
  }
  func definitions() throws {
    try write(".md-utils/md-utils.json", "{\"configVersion\":\"0.3.0\"}")
    try write(".md-utils/types/person.mdtype.json", """
      {"md-utils-type-schema":"1","name":"Person","version":"1",
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["name"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try write(".md-utils/types/book.mdtype.json", """
      {"md-utils-type-schema":"2","name":"Book","version":"1","requires":["document-relationships"],
       "frontmatter":{"schemas":[{"inline":{"type":"object","required":["title"]}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
       "relationships":{"author":{"select":["author"],"target":{"type":"person.mdtype.json"}},
       "editor":{"select":["editor"],"target":{"type":"person.mdtype.json"}}}}
      """)
    try write(".md-utils/rules/books.mdrule.json", """
      {"name":"Books","match":{"paths":["books/**"]},"types":"book.mdtype.json"}
      """)
  }
  func run(_ extra: [String], detail: String = "evidence") async throws -> (result: MarkdownCollectionQueryResult, complete: Bool) {
    let command = try CLIEntry.parseAsRoot(["rel", "both", "--root", root.string, "--detail", detail] + extra)
    let options = try #require((command as? CLIEntry.Relationships.Both)?.options)
    return try await MarkdownCollectionQuerySession.run(options.request(.both), root: root, noIndex: true)
  }
  func remove() { try? root.delete() }
}

struct CollectionRelationshipQueryTests {
  @Test func `ordinary links need no definitions and incoming sources are root wide`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("selected/a.md", "# A\n")
    try fixture.write("outside/b.md", "[A](../selected/a.md)\n[[selected/a]]\n[A again][ref]\n\n[ref]: ../selected/a.md\n")
    let query = try await fixture.run(["--select-folder", "selected/"])
    #expect(query.complete)
    #expect(query.result.selected == ["selected/a.md"])
    #expect(query.result.links.first?.occurrenceCount == 3)
    #expect(query.result.occurrences?.count == 3)
    #expect(query.result.files?.first?.unnamed.incoming?.count == 3)
  }

  @Test func `named overlap repeated links and failed rule requirements retain evidence`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    try fixture.write("books/a.md", "---\nauthor: '[[people/alice]]'\n---\n[[people/alice]] [[people/alice]]\n")
    try fixture.write("people/alice.md", "---\nname: Alice\n---\n")
    let query = try await fixture.run(["books/a.md", "people/alice.md"])
    #expect(query.complete)
    #expect(query.result.relationships.first?.predicate == "Book:author")
    #expect(query.result.links.first?.occurrenceCount == 2)
    #expect(query.result.occurrences?.count == 3)
    #expect(query.result.namedRelationships?.first?.applicability.contains { $0.kind == "ruleRequirement" } == true)
    let required = try await fixture.run(["--select-required-type", "Book"])
    #expect(required.result.selected == ["books/a.md"])
    let conforming = try await fixture.run(["--select-type", "Book"])
    #expect(conforming.result.selected.isEmpty)
    let rule = try await fixture.run(["--select-rule", "Books"])
    #expect(rule.result.selected == ["books/a.md"])
  }

  @Test func `relation filtering never turns filtered named occurrences into unnamed links`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    try fixture.write("books/a.md", "---\nauthor: '[[people/alice]]'\neditor: '[[people/alice]]'\n---\n[[people/alice]]\n")
    try fixture.write("people/alice.md", "---\nname: Alice\n---\n")
    let query = try await fixture.run(["books/a.md", "--type", "Book", "--relation", "author"])
    #expect(query.result.relationships.count == 1)
    #expect(query.result.links.first?.occurrenceCount == 1)
  }

  @Test func `set operations exclusions and JMESPath envelope preserve TOML skips`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("notes/a.md", "---\ntags: [swift]\n---\nAlpha")
    try fixture.write("notes/b.md", "---\ntags: [Swift]\n---\nBeta")
    try fixture.write("notes/c.md", "+++\ntags = ['swift']\n+++\nAlpha")
    let tags = try await fixture.run(["--select-folder", "notes/", "--select-tag", "swift", "--select-mode", "intersection"])
    #expect(tags.result.selected == ["notes/a.md"])
    let query = try await fixture.run(["--select-jmespath", "contains(body, 'Alpha')", "--exclude-file", "notes/a.md"])
    #expect(query.complete)
    #expect(query.result.selected.isEmpty)
    #expect(query.result.skipped == ["notes/c.md"])
    #expect(query.result.notices.contains { $0.code == "selection.toml.skipped" })
  }

  @Test(arguments: ["summary", "explain", "evidence"]) func `detail does not change incomplete result semantics`(detail: String) async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("a.md", "[[missing]]")
    let query = try await fixture.run(["a.md", "absent.md"], detail: detail)
    #expect(query.complete == false)
    #expect(query.result.selected == ["a.md", "absent.md"])
    #expect(query.result.notices.contains { $0.code == "query.incomplete" })
    #expect((query.result.coverage == nil) == (detail == "summary"))
    #expect((query.result.occurrences == nil) == (detail != "evidence"))
    let data = try JSONEncoder().encode(query.result)
    let decoded = try YAMLDecoder().decode(MarkdownCollectionQueryResult.self, from: YAMLEncoder().encode(query.result))
    #expect(decoded.selected == query.result.selected)
    if detail == "summary" {
      let text = String(decoding: data, as: UTF8.self)
      #expect(text.contains("sourceRevision") == false)
      #expect(text.contains("coverage") == false)
    }
  }

  @Test func `file lists preserve whitespace support NUL and enforce preflight`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("space name.md", "# note")
    try fixture.write("paths.txt", "space name.md\n\nspace name.md\n")
    let query = try await fixture.run(["--files-from", (fixture.root + "paths.txt").string])
    #expect(query.result.selected == ["space name.md"])
    try fixture.write("empty.txt", "")
    try Data([0xff]).write(to: URL(fileURLWithPath: (fixture.root + "unreadable.md").string))
    #expect(try await fixture.run(["--files-from", (fixture.root + "empty.txt").string]).complete)
    try fixture.write("bad.txt", "space name.md\r\n")
    await #expect(throws: (any Error).self) { try await fixture.run(["--files-from", (fixture.root + "bad.txt").string]) }
    var input: Substring = "line\nbreak.md\0space name.md\0"
    #expect(try MarkdownQueryFileListParser(nulDelimited: true).parse(&input) == ["line\nbreak.md", "space name.md"])
    await #expect(throws: (any Error).self) { try await fixture.run(["../escape.md"]) }
    await #expect(throws: (any Error).self) { try await fixture.run(["--select-folder", ".", "--select-tag", "swift"]) }
  }

  @Test func `Markdown destinations are exact source relative and once decoded`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("notes/a.md", "[space](b%20c.md#heading) [literal](b%2520c.md) [missing](b) [root](/b.md)")
    try fixture.write("notes/b c.md", "# B")
    try fixture.write("notes/b%20c.md", "# C")
    try fixture.write("notes/b.md", "# D")
    let query = try await fixture.run(["notes/a.md"])
    #expect(query.result.links.map(\.object) == ["notes/b c.md", "notes/b%20c.md"])
    #expect(query.result.occurrences?.filter { $0.resolution?.status == .unresolved }.count == 1)
    #expect(query.complete == false)
  }

  @Test func `unconditional requirements intersect alternatives and ignore negation`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    try (fixture.root + ".md-utils/rules/books.mdrule.json").delete()
    try fixture.write(".md-utils/rules/alternatives.mdrule.json", """
      {"name":"Alternatives","match":{"paths":["*.md"]},"types":{"anyOf":[
        {"allOf":["book.mdtype.json","person.mdtype.json"]},
        {"allOf":["book.mdtype.json",{"not":"person.mdtype.json"}]}]}}
      """)
    try fixture.write("a.md", "---\nauthor: 'broken'\n---\n")
    let book = try await fixture.run(["--select-required-type", "Book"])
    let person = try await fixture.run(["--select-required-type", "Person"])
    #expect(book.result.selected == ["a.md"])
    #expect(person.result.selected.isEmpty)
    #expect(book.result.occurrences?.first?.value == .string("broken"))
    #expect(book.result.namedRelationships?.first?.applicability.contains { $0.kind == "ruleRequirement" } == true)
  }

  @Test func `hints preserve malformed assertions and multiple interpretations share occurrences`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    let definition: String = try (fixture.root + ".md-utils/types/book.mdtype.json").read()
    try fixture.write(".md-utils/types/other.mdtype.json", definition.replacingOccurrences(of: "\"Book\"", with: "\"Other\""))
    try fixture.write("a.md", "---\n$md-utils:\n  typeHints: [Book, Other]\nauthor: 'See [[people/alice]]'\n---\n")
    try fixture.write("people/alice.md", "---\nname: Alice\n---\n")
    let query = try await fixture.run(["a.md"])
    let interpretations = try #require(query.result.namedRelationships)
    #expect(interpretations.count == 2)
    #expect(Set(interpretations.map(\.occurrence)).count == 1)
    #expect(interpretations.allSatisfy { $0.applicability.contains { $0.kind == "typeHint" && $0.verification == .fail } })
    #expect(query.result.links.isEmpty)
    #expect(query.result.occurrences?.count == 2)
    #expect(interpretations.allSatisfy { $0.containedOccurrences.count == 1 })
  }

  @Test func `ordinary categories are excluded and exact raw ranges survive Unicode`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    let content = "é [B](b.md) `[[b]]` ![[b]] ![B](b.md) [site](https://example.com/b.md) [[a#self]] [self](#self)\n"
    try fixture.write("a.md", content)
    try fixture.write("b.md", "# B")
    let query = try await fixture.run(["a.md"])
    let occurrences = try #require(query.result.occurrences)
    #expect(occurrences.count == 1)
    let occurrence = try #require(occurrences.first)
    let span = try #require(occurrence.location.sourceUTF8Range)
    #expect(String(decoding: Array(content.utf8)[span], as: UTF8.self) == "[B](b.md)")
    #expect(occurrence.value == .string("[B](b.md)"))
  }

  @Test func `ambiguity is not incoming evidence and known broken links do not fail the query`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("a.md", "[[b]] [[missing]]")
    try fixture.write("one/b.md", "# B")
    try fixture.write("two/b.md", "# B")
    let query = try await fixture.run(["a.md", "one/b.md"])
    #expect(query.complete)
    #expect(query.result.links.isEmpty)
    #expect(query.result.files?.first(where: { $0.path == "one/b.md" })?.unnamed.incoming == [])
    #expect(query.result.occurrences?.contains { $0.resolution?.candidates == ["one/b.md", "two/b.md"] } == true)
  }

  @Test func `indexed parity limited alias and all output formats honor detail and status`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    try fixture.write("a.md", "[[b]]")
    try fixture.write("b.md", "# B")
    let request = MarkdownCollectionQueryRequest(direction: .both, selectors: [.files(["a.md", "b.md"])], detail: .evidence)
    let direct = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true)
    let database = try SQLiteIndexDatabase(path: (fixture.root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: URL(fileURLWithPath: fixture.root.string).resolvingSymlinksInPath().path)
    let indexed = try await MarkdownCollectionQuerySession.run(request, root: fixture.root)
    #expect(indexed.result.links == direct.result.links)
    #expect(indexed.complete == direct.complete)
    for detail in ["summary", "explain", "evidence"] {
      for format in ["--json", "--yaml"] {
        let result = try CLIProcessTestHelper.run(["rel", "both", "a.md", "--root", fixture.root.string,
          "--index-only", "--detail", detail, format])
        #expect(result.status == 1)
        let decoded = format == "--json"
          ? try JSONDecoder().decode(MarkdownCollectionQueryResult.self, from: Data(result.standardOutput.utf8))
          : try YAMLDecoder().decode(MarkdownCollectionQueryResult.self, from: result.standardOutput)
        #expect(decoded.detail.rawValue == detail)
        #expect(decoded.notices.contains { $0.code == "query.incomplete" })
        #expect((decoded.coverage == nil) == (detail == "summary"))
      }
    }
  }

  @Test func `record budget returns available results and unknown type selection remains incomplete`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    try fixture.write("a.md", "---\ntitle: A\nauthor: '[[b]]'\n---\n")
    try fixture.write("b.md", "---\nname: B\n---\n")
    var limits = MarkdownRelationshipLimits(); limits.records = 1
    let request = MarkdownCollectionQueryRequest(direction: .both, selectors: [.type("Book")], detail: .evidence)
    let query = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true, limits: limits)
    #expect(query.complete == false)
    #expect(query.result.coverage?.selection == "incomplete")
    #expect(query.result.selected.isEmpty)
  }

  @Test func `candidate and occurrence budgets return partial envelopes`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("a.md", "[[b]] [[b]] [[b]]")
    try fixture.write("b.md", "# B")
    let request = MarkdownCollectionQueryRequest(direction: .both, selectors: [.folder("")], detail: .evidence)
    var limits = MarkdownRelationshipLimits(); limits.candidates = 1
    let candidates = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true, limits: limits)
    #expect(candidates.complete == false)
    #expect(candidates.result.coverage?.candidates == "incomplete")
    limits = .init(); limits.occurrences = 1
    let occurrences = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true, limits: limits)
    #expect(occurrences.complete == false)
    #expect(occurrences.result.occurrences?.count == 1)
    #expect(occurrences.result.coverage?.sources == "incomplete")
  }

  @Test func `incoming ambiguity retains candidates without inventing incoming edges`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("a.md", "[[b]]")
    try fixture.write("one/b.md", "# B")
    try fixture.write("two/b.md", "# B")
    let request = MarkdownCollectionQueryRequest(direction: .incoming, selectors: [.files(["one/b.md"])], detail: .evidence)
    let query = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true)
    #expect(query.complete)
    #expect(query.result.links.isEmpty)
    #expect(query.result.files?.first?.unnamed.incoming == [])
    #expect(query.result.files?.first?.unnamed.outgoing == nil)
    #expect(query.result.occurrences?.first?.resolution?.status == .ambiguous)
    #expect(query.result.notices.contains { $0.code == "relationship.unresolved" })
  }

  @Test func `unknown exclusion is incomplete but a definite union match remains selected`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.definitions()
    try fixture.write("a.md", "---\ntitle: A\nauthor: '[[b]]'\n---\n")
    try fixture.write("b.md", "---\nname: B\n---\n")
    var limits = MarkdownRelationshipLimits(); limits.records = 1
    var request = MarkdownCollectionQueryRequest(direction: .outgoing,
      selectors: [.files(["a.md"]), .type("Book")], detail: .explain)
    let union = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true, limits: limits)
    #expect(union.result.selected == ["a.md"])
    request.selectors = [.files(["a.md"])]; request.exclusions = [.type("Book")]
    let excluded = try await MarkdownCollectionQuerySession.run(request, root: fixture.root, noIndex: true, limits: limits)
    #expect(excluded.result.selected.isEmpty)
    #expect(excluded.result.coverage?.selection == "incomplete")
  }

  @Test func `absent frontmatter JMESPath marker and invalid expressions are explicit`() async throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("a.md", "# A")
    let query = try await fixture.run(["--select-jmespath", "frontmatterFormat == 'none' && length(frontmatter) == `0`"])
    #expect(query.result.selected == ["a.md"])
    await #expect(throws: (any Error).self) { try await fixture.run(["--select-jmespath", "["]) }
  }

  @Test func `stdin lists relative roots and concise human output work at the process boundary`() throws {
    let fixture = try QueryFixture(); defer { fixture.remove() }
    try fixture.write("a.md", "[[b]]")
    try fixture.write("b.md", "# B")
    for (flag, input) in [("--files-from", "a.md\nb.md\n"), ("--files-from0", "a.md\0b.md\0")] {
      let result = try CLIProcessTestHelper.run(["rel", "in", "--root", ".", flag, "-", "--json"],
        standardInput: input, workingDirectory: URL(fileURLWithPath: fixture.root.string))
      #expect(result.status == 0)
      let decoded = try JSONDecoder().decode(MarkdownCollectionQueryResult.self, from: Data(result.standardOutput.utf8))
      #expect(decoded.selected == ["a.md", "b.md"])
      #expect(decoded.links.first?.subject == "a.md")
    }
    let missing = try CLIProcessTestHelper.run(["rel", "in", "missing.md", "--root", fixture.root.string])
    #expect(missing.status == 1)
    #expect(missing.standardOutput.contains("Use --detail explain."))
    #expect(missing.standardOutput.contains("Coverage:") == false)
    #expect(missing.standardOutput.contains("sourceRevision") == false)
    #expect(missing.standardOutput.contains("\u{001B}[") == false)
  }
}
