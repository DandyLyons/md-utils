import ArgumentParser
import Foundation
import Testing
@testable import md_utils

struct CreationBatchTests {
  @Test func inputLimitsAndRepeatedFileIdentity() throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    let path = fixture.root.appendingPathComponent("input.json").path
    let options = try InstanceCreationOptions.parse(["--value-file", path, "--value-file", path, "--filename-data", "$.title"])
    let items = try CreationBatch.load(options: options, inputByteLimit: 3)
    #expect(items[0].failures.isEmpty)
    #expect(items[1].failures.isEmpty == false)
    #expect(items[0].identity != items[1].identity)
    #expect(throws: (any Error).self) { try CreationBatch.load(options: options, maximumItems: 1) }
  }

  @Test(arguments: [
    ["--values", "batch.json", "--filename", "x.md"],
    ["--values", "batch.json", "--value", "input.json", "--filename-data", "$.title"],
    ["--values", "batch.json", "--value-file", "input.json", "--filename-data", "$.title"],
    ["--value", "input.json", "--value-file", "input.json", "--filename-data", "$.title"],
  ])
  func conflictingInputOptionsAreRejected(_ args: [String]) {
    #expect(throws: (any Error).self) {
      let options = try InstanceCreationOptions.parse(args)
      try options.validate()
    }
  }

  @Test func bodyModeWorksPerItem() throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/types/book.mdtype.json", #"{"md-utils-type-schema":"1","name":"Book","version":"1","frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},"creation":{"template":{"inline":"{{ data.title }}","mode":"body"}}}"#)
    try fixture.write("batch.json", #"[{"frontmatter":{"title":"Dune"},"data":{"title":"Dune body"}},{"frontmatter":{"title":"Foundation"},"data":{"title":"Foundation body"}}]"#)
    let result = try CLIProcessTestHelper.run([
      "types", "new", "--type", "Book", "--root", fixture.root.path,
      "--values", fixture.root.appendingPathComponent("batch.json").path,
      "--filename-data", "$.frontmatter.title", fixture.root.appendingPathComponent("Books/").path,
    ])
    #expect(result.status == 0)
    for title in ["Dune", "Foundation"] {
      let content = try String(contentsOf: fixture.root.appendingPathComponent("Books/\(title).md"), encoding: .utf8)
      #expect(content.contains("title: \(title)"))
      #expect(content.contains("\(title) body"))
    }
  }

  @Test func renderingFailuresAreCollectedForEveryItem() throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    try fixture.write(".md-utils/types/book.mdtype.json", #"{"md-utils-type-schema":"1","name":"Book","version":"1","frontmatter":{},"body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},"creation":{"template":{"inline":"{{ title }}","mode":"body"}}}"#)
    try fixture.write("batch.json", #"[{"title":"Dune","frontmatter":42},{"title":"Foundation","frontmatter":42}]"#)
    let result = try CLIProcessTestHelper.run([
      "types", "new", "--type", "Book", "--root", fixture.root.path,
      "--values", fixture.root.appendingPathComponent("batch.json").path,
      "--filename-data", "$.title", fixture.root.appendingPathComponent("Books/").path,
    ])
    #expect(result.status != 0)
    #expect(result.standardError.contains("batch.json[0]"))
    #expect(result.standardError.contains("batch.json[1]"))
    #expect(result.standardError.contains("Rendering/assessment"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).isEmpty)
  }

  @Test func danglingSymlinksBlockPreflightAndDryRunNeverInvokesWriter() throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    let destination = fixture.root.appendingPathComponent("Books/link.md")
    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: fixture.root.appendingPathComponent("missing.md"))
    var items = [CreationBatch.Item(identity: "link", destination: destination, content: Data())]
    CreationBatch.checkDestinations(&items)
    #expect(items[0].failures.contains { $0.contains("already exists") })
    let planned = [CreationBatch.Item(identity: "safe", destination: fixture.root.appendingPathComponent("Books/safe.md"), content: Data())]
    let results = CreationBatch.persist(planned, dryRun: true) { _, _ in Issue.record("Dry run invoked writer") }
    #expect(results.map(\.status) == ["Would create"])
  }

  @Test(arguments: ["md", "txt", ""])
  func arrayCreationAppliesDefaultsAndAdvisoryAssessments(_ suffix: String) throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    try fixture.write("batch.json", #"[{"title":"Foundation"},{}]"#)
    let args = ["rules", "new", "--rule", "Books", "--config", fixture.root.appendingPathComponent(".md-utils/md-utils.json").path,
      "--values", fixture.root.appendingPathComponent("batch.json").path, "--filename-data", "$.title", "--extension", suffix,
    ]
    let preview = try CLIProcessTestHelper.run(args + ["--dry-run"])
    #expect(preview.status == 0)
    #expect(preview.standardOutput.contains("Would create"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).isEmpty)
    let result = try CLIProcessTestHelper.run(args)
    #expect(result.status == 0)
    #expect(result.standardOutput.contains("batch.json[0]"))
    #expect(result.standardOutput.contains("batch.json[1]"))
    #expect(result.standardOutput.contains("Type \"Book\": does not conform (advisory)"))
    #expect(result.standardOutput.contains("Rule \"Books\""))
    for title in ["Foundation", "Dune"] {
      let name = title + (suffix.isEmpty ? "" : "." + suffix)
      #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/" + name), encoding: .utf8) == "# \(title)")
    }
  }

  @Test func allCollisionParticipantsAndInvalidItemsAreReported() throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    try fixture.write("batch.json", #"[{"title":"Dune"},{"title":"Dune"},{"title":2},{"title":"../escape"},42,{"title":"Good"}]"#)
    try fixture.write("Books/Dune.md", "original")
    let args = ["types", "new", "--type", "Book", "--root", fixture.root.path,
      "--values", fixture.root.appendingPathComponent("batch.json").path,
      "--filename-data", "$.title", fixture.root.appendingPathComponent("Books/").path,
    ]
    for flags in [[], ["--dry-run"]] {
      let result = try CLIProcessTestHelper.run(args + flags)
      #expect(result.status != 0)
      for index in 0...4 { #expect(result.standardError.contains("batch.json[\(index)]")) }
      #expect(result.standardError.contains("Duplicate destination"))
      #expect(result.standardError.contains("already exists"))
      #expect(result.standardError.contains("no files were written"))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path) == ["Dune.md"])
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/Dune.md"), encoding: .utf8) == "original")
  }

  @Test func multipleFilesCollectReadAndJSONFailuresAndPreserveOrder() throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    try fixture.write("other.json", #"{"title":"Foundation"}"#)
    let args = ["types", "new", "--type", "Book", "--root", fixture.root.path,
      "--value-file", fixture.root.appendingPathComponent("input.json").path,
      "--value-file", fixture.root.appendingPathComponent("other.json").path,
      "--filename-data", "$.title", fixture.root.appendingPathComponent("Books/").path,
    ]
    try fixture.write("broken.json", "{")
    let failed = try CLIProcessTestHelper.run(args + [
      "--value-file", fixture.root.appendingPathComponent("broken.json").path,
      "--value-file", fixture.root.appendingPathComponent("absent.json").path,
    ])
    #expect(failed.status != 0)
    #expect(failed.standardError.contains("broken.json (input 3)"))
    #expect(failed.standardError.contains("absent.json (input 4)"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).isEmpty)
    let success = try CLIProcessTestHelper.run(args)
    #expect(success.status == 0)
    let first = try #require(success.standardOutput.range(of: "input.json (input 1)"))
    let second = try #require(success.standardOutput.range(of: "other.json (input 2)"))
    #expect(first.lowerBound < second.lowerBound)
  }

  @Test(arguments: ["[]", "{}", "null"])
  func invalidBatchContainersFail(_ input: String) throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    try fixture.write("batch.json", input)
    let result = try CLIProcessTestHelper.run([
      "types", "new", "--type", "Book", "--root", fixture.root.path,
      "--values", fixture.root.appendingPathComponent("batch.json").path,
      "--filename-data", "$.title", fixture.root.appendingPathComponent("Books/").path,
    ])
    #expect(result.status != 0)
    #expect(result.standardError.contains("nonempty JSON array"))
  }

  @Test(arguments: [true, false])
  func publicationFailurePreservesCompletedFilesAndReportsEveryItem(collision: Bool) throws {
    let fixture = try InstanceCreationTests.Fixture()
    defer { fixture.remove() }
    var items = (0..<3).map { index in
      CreationBatch.Item(identity: "item \(index)", destination: fixture.root.appendingPathComponent("Books/\(index).md"), content: Data("new".utf8))
    }
    CreationBatch.checkDestinations(&items)
    #expect(items.allSatisfy { $0.failures.isEmpty })
    let outcomes = CreationBatch.persist(items, dryRun: false) { data, destination in
      if destination.lastPathComponent == "1.md" {
        if collision { try Data("racing writer".utf8).write(to: destination) }
        else { throw CocoaError(.fileWriteNoPermission) }
      }
      try InstanceCreation.create(data, at: destination)
    }
    #expect(outcomes.map(\.status) == ["Created", "failed", "not attempted"])
    #expect(outcomes[1].error != nil)
    #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/0.md"), encoding: .utf8) == "new")
    #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Books/2.md").path) == false)
    if collision {
      #expect(try String(contentsOf: fixture.root.appendingPathComponent("Books/1.md"), encoding: .utf8) == "racing writer")
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Books/").path).allSatisfy { !$0.hasPrefix(".md-utils-create-") })
  }
}
