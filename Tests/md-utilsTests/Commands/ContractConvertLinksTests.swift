import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import PathKit
import Testing
@testable import md_utils

struct ContractConvertLinksTests {
  private func workspace() throws -> Path {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/contract-convert-\(UUID().uuidString)"
    try (root + "people").mkpath()
    try (root + ".md-utils/types").mkpath()
    try (root + "people/Alice.md").write("# Alice\n")
    try (root + ".md-utils/types/links.mdtype.json").write("""
      {"md-utils-type-schema":"2","requires":["wikilink-constraints"],"name":"Links","version":"1",
       "frontmatter":{"schemas":[{"inline":{"properties":{"link":{"type":"string","format":"Wikilink",
         "wikilink":{"styles":["vault-path"],"markdownExtension":"require"}}}}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    return root
  }

  @Test func previewApplyNoopAndSeparateAssessment() async throws {
    let root = try workspace(); defer { try? root.delete() }
    let file = root + "source.md"
    let source = "---\nlink: '[[Alice]]'\n---\nBody [[Alice]]\n"
    try file.write(source)
    let preview = try await WikilinkContractConversionSession.run(file: file, root: root, type: "Links")
    #expect(preview.plan.hasChanges)
    #expect(preview.assessment.conforms)
    #expect(try file.read() as String == source)
    #expect((root + ".md-utils/index.sqlite").exists == false)
    let applied = try await WikilinkContractConversionSession.run(file: file, root: root, type: "Links", apply: true)
    #expect(applied.applied)
    #expect(try file.read() as String == preview.plan.proposed.content)
    let date = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.string)
    let noop = try await WikilinkContractConversionSession.run(file: file, root: root, type: "Links", apply: true)
    #expect(noop.applied == false)
    #expect(try FileManager.default.attributesOfItem(atPath: file.string)[.modificationDate] as? Date == date)
  }

  @Test(arguments: ["source", "definition", "namespace", "target"])
  func authoritativeEvidenceIsRecheckedBeforeWrite(_ change: String) async throws {
    let root = try workspace(); defer { try? root.delete() }
    let file = root + "source.md"
    let source = "---\nlink: '[[Alice]]'\n---\n"
    try file.write(source)
    let directory = root.string
    await #expect(throws: IndexProjectError.self) {
      try await WikilinkContractConversionSession.execute(file: file, root: root, type: "Links", apply: true,
        beforeVerification: {
          let root = Path(directory)
          switch change {
          case "source": try (root + "source.md").write(source + "external edit\n")
          case "definition":
            let file = root + ".md-utils/types/links.mdtype.json"
            let original: String = try file.read()
            try file.write(original.replacingOccurrences(of: "vault-path", with: "relative-path"))
          case "namespace": try (root + "Alice.md").write("# New ambiguity\n")
          default: try (root + "people/Alice.md").write("# Changed target\n")
          }
        })
    }
    #expect(try file.read() as String == (change == "source" ? source + "external edit\n" : source))
  }

  @Test func existingPassingTypesAreProtected() async throws {
    let root = try workspace(); defer { try? root.delete() }
    try (root + ".md-utils/types/preserve.mdtype.json").write("""
      {"md-utils-type-schema":"1","name":"Preserve","version":"1",
       "frontmatter":{"schemas":[{"inline":{"properties":{"link":{"const":"[[Alice]]"}}}}]},
       "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    let file = root + "source.md"
    let source = "---\nlink: '[[Alice]]'\n---\n"
    try file.write(source)
    let result = try await WikilinkContractConversionSession.run(file: file, root: root, type: "Links", apply: true)
    #expect(result.plan.unresolved)
    #expect(result.blockers.isEmpty == false)
    #expect(result.applied == false)
    #expect(try file.read() as String == source)
  }

  @Test func existingPassingRulesAreProtected() async throws {
    let root = try workspace(); defer { try? root.delete() }
    try (root + ".md-utils/schemas").mkpath()
    try (root + ".md-utils/schemas/preserve.json").write("{\"properties\":{\"link\":{\"const\":\"[[Alice]]\"}}}")
    try (root + ".md-utils/md-utils.json").write("""
      {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
        {"name":"preserve","match":{"paths":["source.md"]},
         "checks":[{"type":"frontmatterSchema","schema":"preserve.json","frontmatterRequired":false}]}]}
      """)
    let file = root + "source.md"
    let source = "---\nlink: '[[Alice]]'\n---\n"
    try file.write(source)
    let result = try await WikilinkContractConversionSession.run(file: file, root: root, type: "Links", apply: true)
    #expect(result.plan.unresolved)
    #expect(result.blockers.contains { $0.contains("preserve") })
    #expect(result.applied == false)
    #expect(try file.read() as String == source)
  }

  @Test func invalidOptionCombinationsFailBeforeReadingFiles() async throws {
    for args in [
      ["--type", "Links", "--to", "wiki-path"], ["--type", "Links", "--scope", "body"],
      ["--type", "Links", "--prefer-style", "absolute"], ["--to", "wiki-path", "--prefer-style", "name"],
    ] {
      var command = try #require(CLIEntry.parseAsRoot(["links", "convert", "--root", "."] + args) as? CLIEntry.ConvertLinks)
      await #expect(throws: ValidationError.self) { try await command.run() }
    }
  }

  @Test func unrelatedFailureDoesNotMasqueradeAsUnresolvedLexicalRepair() throws {
    let root = try workspace(); defer { try? root.delete() }
    let definition = root + ".md-utils/types/links.mdtype.json"
    let original: String = try definition.read()
    try definition.write(original.replacingOccurrences(of: "\"properties\":", with: "\"required\":[\"title\"],\"properties\":"))
    let file = root + "source.md"
    try file.write("---\nlink: '[[Alice]]'\n---\n")
    let result = try CLIProcessTestHelper.run([
      "links", "convert", "--root", root.string, "--type", "Links", "--in-place", "--json", file.string,
    ])
    #expect(result.status == 0)
    let rows = try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [[String: Any]])
    #expect(rows.first?["status"] as? String == "changed")
    #expect((rows.first?["assessment"] as? [String: Any])?["outcome"] as? String == "fail")
  }

  @Test func loadedSchemaChangesInvalidateThePlanAndPreviewDoesNotCreateLocks() async throws {
    let root = try workspace(); defer { try? root.delete() }
    let definition = root + ".md-utils/types/links.mdtype.json"
    let original: String = try definition.read()
    let decoded = try #require(JSONSerialization.jsonObject(with: Data(original.utf8)) as? [String: Any])
    let frontmatter = try #require(decoded["frontmatter"] as? [String: Any])
    let schemas = try #require(frontmatter["schemas"] as? [[String: Any]])
    let schema = try #require(schemas.first?["inline"])
    let schemaFile = root + ".md-utils/types/link-schema.json"
    try JSONSerialization.data(withJSONObject: schema).write(to: URL(fileURLWithPath: schemaFile.string))
    var referenced = decoded
    referenced["frontmatter"] = ["schemas": [["ref": "link-schema.json"]]]
    try JSONSerialization.data(withJSONObject: referenced).write(to: URL(fileURLWithPath: definition.string))
    let file = root + "source.md"
    let source = "---\nlink: '[[Alice]]'\n---\n"
    try file.write(source)
    let before = try root.recursiveChildren().map(\.string).sorted()
    let result = try await WikilinkContractConversionSession.run(file: file, root: root, type: "Links")
    #expect(result.plan.hasChanges)
    #expect(try root.recursiveChildren().map(\.string).sorted() == before)
    let schemaPath = schemaFile.string
    await #expect(throws: IndexProjectError.self) {
      try await WikilinkContractConversionSession.execute(file: file, root: root, type: "Links", apply: true,
        beforeVerification: { try Path(schemaPath).write("{\"type\":\"object\"}") })
    }
    #expect(try file.read() as String == source)
  }

  @Test func partialBatchReportsUnresolvedAndOperationalFailure() throws {
    let root = try workspace(); defer { try? root.delete() }
    try (root + "a.md").write("---\nlink: '[[Alice]]'\n---\n")
    try (root + "b.md").write("---\nlink: '[[Missing]]'\n---\n")
    let report = try CLIProcessTestHelper.run([
      "links", "convert", "--root", root.string, "--type", "Links", "--in-place", "--json",
      (root + "a.md").string, (root + "b.md").string,
    ])
    #expect(report.status == 1)
    let rows = try #require(JSONSerialization.jsonObject(with: Data(report.standardOutput.utf8)) as? [[String: Any]])
    #expect(rows.compactMap { $0["status"] as? String } == ["changed", "unresolved"])
    #expect(try (root + "a.md").read().contains("people/Alice.md"))
    #expect(try (root + "b.md").read().contains("[[Missing]]"))
    // A selected non-UTF-8 source fails operationally; later files are explicitly unprocessed.
    try Data([0xff]).write(to: URL(fileURLWithPath: (root + "c.md").string))
    try (root + "d.md").write("---\nlink: '[[Missing]]'\n---\n")
    let failed = try CLIProcessTestHelper.run([
      "links", "convert", "--root", root.string, "--type", "Links", "--json",
      (root + "c.md").string, (root + "d.md").string,
    ])
    #expect(failed.status == 1)
    let failures = try #require(JSONSerialization.jsonObject(with: Data(failed.standardOutput.utf8)) as? [[String: Any]])
    #expect(failures.compactMap { $0["status"] as? String } == ["failed", "unprocessed"])
  }
}
