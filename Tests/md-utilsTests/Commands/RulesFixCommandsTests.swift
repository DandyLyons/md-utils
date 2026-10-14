import Foundation
import PathKit
import Testing

struct RulesFixCommandsTests {
  @Test func `default review prints severity provenance and complete opt in commands without writes`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let before = try (fixture.root + "Bob.md").read(.utf8)
    let output = try CLIProcessTestHelper.run(fixture.arguments)
    #expect(output.status != 0)
    #expect(output.standardOutput.contains("ERROR · rule: people · policy: return"))
    #expect(output.standardOutput.contains("Alice.md frontmatter /spouse"))
    #expect(output.standardOutput.contains("--select 1 --review 'fix-review-v1-"))
    #expect(output.standardOutput.contains("--apply"))
    #expect(output.standardOutput.contains("Assessment when selected alone: fail → pass"))
    #expect(output.standardOutput.contains("Preview only. No files changed."))
    #expect(try (fixture.root + "Bob.md").read(.utf8) == before)
    #expect((fixture.root + ".md-utils/writer.lock").exists == false)
    #expect((fixture.root + ".md-utils/index.sqlite").exists == false)
    #expect((fixture.root + ".md-utils/drafts/").exists == false)
  }

  @Test func `number selection only previews and explicit token application writes`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let initial = try fixture.review()
    let token = try #require(initial["token"] as? String)
    let selected = try CLIProcessTestHelper.run(fixture.arguments + ["--select", "1,1", "--select", "1", "--json"])
    let preview = try object(selected.standardOutput)
    #expect(preview["selected"] as? [Int] == [1])
    #expect((preview["files"] as? [[String: Any]])?.first?["path"] as? String == "Bob.md")
    #expect((fixture.root + ".md-utils/writer.lock").exists == false)
    let applied = try CLIProcessTestHelper.run(fixture.arguments + ["--select", "1", "--review", token, "--apply", "--json"])
    #expect(applied.status == 0, "\(applied.standardOutput)\n\(applied.standardError)")
    let result = try object(applied.standardOutput)
    #expect(result["applied"] as? Bool == true)
    #expect((result["after"] as? [String: Any])?["outcome"] as? String == "pass")
    #expect(try (fixture.root + "Bob.md").read(.utf8).contains("[[Alice]]"))
  }

  @Test func `apply without review or selection and yes alone cannot approve relationship edits`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    for options in [["--apply"], ["--select", "1", "--apply"], ["--yes", "--apply"], ["--select", "1,,2"]] {
      let result = try CLIProcessTestHelper.run(fixture.arguments + options)
      #expect(result.status != 0)
      #expect(try (fixture.root + "Bob.md").read(.utf8) == "# Bob\n")
      #expect((fixture.root + ".md-utils/drafts/").exists == false)
    }
  }

  @Test func `stale tokens cannot reinterpret numbered suggestions`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let token = try #require(fixture.review()["token"] as? String)
    try (fixture.root + "Alice.md").write("# No assertion\n")
    let result = try CLIProcessTestHelper.run(fixture.arguments + ["--select", "1", "--review", token, "--apply"])
    #expect(result.status != 0)
    #expect(result.standardError.contains("preview again"))
    #expect((fixture.root + ".md-utils/drafts/").exists == false)
  }

  @Test func `automatic const and input required default share the rule fix command`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try (fixture.root + ".md-utils/types/person.mdtype.json").write("""
      {"md-utils-type-schema":"2","name":"Person","version":"1", "frontmatter":{"schemas":[{"inline":{
        "type":"object","required":["kind","status"],"properties":{"kind":{"const":"note"},"status":{"default":"draft"}}
      }}]},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]}}
      """)
    try (fixture.root + ".md-utils/rules/people.mdrule.json").write("""
      {"name":"people","match":{"paths":["*.md"]},"types":"person.mdtype.json"}
      """)
    try (fixture.root + "Bob.md").write("---\nname: Bob\n---\n# Bob\n")
    let preview = try object(CLIProcessTestHelper.run(fixture.arguments + ["--yes", "--json"]).standardOutput)
    #expect((preview["selected"] as? [Int])?.count == 2)
    let applied = try CLIProcessTestHelper.run(fixture.arguments + ["--yes", "--apply", "--json"])
    // Defaults remain unselected, so required validation still fails after const fixes.
    #expect(applied.status != 0)
    let after = try (fixture.root + "Bob.md").read(.utf8)
    #expect(after.contains("kind: note"))
    #expect(after.contains("status:") == false)
    let defaults = try fixture.review()
    let token = try #require(defaults["token"] as? String)
    let confirmed = try CLIProcessTestHelper.run(fixture.arguments + ["--select", "1,2", "--review", token, "--apply", "--json"])
    #expect(confirmed.status == 0, "\(confirmed.standardOutput)\(confirmed.standardError)")
    #expect(try (fixture.root + "Bob.md").read(.utf8).contains("status: draft"))
  }

  private func object(_ text: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }

  private struct Fixture {
    let root: Path
    var arguments: [String] {
      ["rules", "fix", "people", "--config", (root + ".md-utils/md-utils.json").string, "--project-root", root.string]
    }
    init() throws {
      root = Path(#filePath).parent().parent().parent().parent() + "tmp/rules-fix-cli-\(UUID().uuidString)/"
      try (root + ".md-utils/types/").mkpath()
      try (root + ".md-utils/rules/").mkpath()
      try (root + ".md-utils/md-utils.json").write("{\"configVersion\":\"0.3.0\"}")
      try (root + ".md-utils/types/person.mdtype.json").write("""
        {"md-utils-type-schema":"2","name":"Person","version":"1","requires":["document-relationships"],
        "frontmatter":{"schemas":[]},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
        "relationships":{"spouse":{"select":["spouse"],"target":{"type":"person.mdtype.json"}}}}
        """)
      try (root + ".md-utils/rules/people.mdrule.json").write("""
        {"md-utils-rule-schema":"1","name":"people","match":{"paths":["*.md"]},"types":"person.mdtype.json",
        "relationshipPolicies":[{"id":"return","kind":"reciprocity","relation":{"type":"person.mdtype.json","name":"spouse"},"scope":"reachable"}]}
        """)
      try (root + "Alice.md").write("---\nspouse: '[[Bob]]'\n---\n# Alice\n")
      try (root + "Bob.md").write("# Bob\n")
    }
    func review() throws -> [String: Any] {
      let result = try CLIProcessTestHelper.run(arguments + ["--json"])
      return try #require(JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any])
    }
    func remove() { try? root.delete() }
  }
}
