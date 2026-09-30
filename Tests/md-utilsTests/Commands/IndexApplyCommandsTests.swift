import ArgumentParser
import Foundation
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServerNative
import PathKit
import Testing
@testable import md_utils

@Suite struct IndexApplyCommandsTests {
  @Test func CLIStagesPreviewsAppliesAndDiscardsWithoutAnHTTPProcess() async throws {
    let root = Path("tmp/draft-cli-\(UUID().uuidString)/").absolute()
    try (root + ".md-utils/server/").mkpath()
    try (root + "notes/").mkpath()
    defer { try? root.delete() }
    try (root + ".md-utils/md-utils.json").write(#"{"configVersion":"0.2.0","rules":[{"name":"notes","match":{"paths":["notes/**"]},"checks":[{"type":"requiredHeading","heading":"Note"}]}]}"#)
    try (root + ".md-utils/server/server.yaml").write("""
      serverConfigVersion: "3"
      resources:
        - name: notes
          route: /notes
          operations: [list, get]
          selection: {mode: rule, rule: notes}
          identityPolicy: {source: logicalPath}
          writable:
            codec: {frontmatterFields: [title], bodyWritable: true}
          mutations: {operations: [patch, replace]}
      """)
    let source = "---\ntitle: Old\n---\n# Note\nBody\n"
    try (root + "notes/one.md").write(source)
    try (root + "edit.json").write(#"{"frontmatter":{"set":{"title":"New"}}}"#)
    let common = ["--project-root", root.string]
    var add = try #require(CLIEntry.parseAsRoot(["index", "draft", "add", "notes/one.md", "--resource", "notes",
      "--revision", IndexFingerprint.hash(Data(source.utf8)), "--patch-file", (root + "edit.json").string,
    ] + common) as? CLIEntry.Index.Draft.Add)
    try await add.run()
    let service = MarkdownDraftService(projectRoot: root.string)
    let id = try #require(service.draftIDs().first)
    var dryRun = try #require(CLIEntry.parseAsRoot(["index", "apply", "--dry-run", "--format", "jsonl"] + common) as? CLIEntry.Index.Apply)
    try await dryRun.run()
    #expect(try (root + "notes/one.md").read(.utf8) == source)
    #expect(!(root + ".md-utils/index.sqlite").exists)
    var apply = try #require(CLIEntry.parseAsRoot(["index", "apply", id] + common) as? CLIEntry.Index.Apply)
    try await apply.run()
    #expect(try service.draft(id).state == .completed)
    #expect(try (root + "notes/one.md").read(.utf8).contains("title: New"))
    var discard = try #require(CLIEntry.parseAsRoot(["index", "draft", "discard", id] + common) as? CLIEntry.Index.Draft.Discard)
    try await discard.run()
    #expect(try service.draftIDs().isEmpty)
  }

  @Test func CLIRequiresExactlyOneEditInput() async throws {
    var add = try #require(CLIEntry.parseAsRoot(["index", "draft", "add", "one.md", "--resource", "notes", "--revision", "hash"])
      as? CLIEntry.Index.Draft.Add)
    await #expect(throws: ValidationError.self) { try await add.run() }
  }
}
