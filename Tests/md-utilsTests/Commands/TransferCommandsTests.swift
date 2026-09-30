import ArgumentParser
import Foundation
import MarkdownUtilitiesIndex
import PathKit
import Testing
@testable import md_utils

@Suite struct TransferCommandsTests {
  @Test func CLITransfersUseSharedRevisionCheckedCoordinator() async throws {
    let root = Path.current.absolute() + "tmp/transfer-cli-\(UUID().uuidString)/"
    try (root + ".md-utils/server/").mkpath()
    try (root + "notes/").mkpath()
    defer { try? root.delete() }
    try (root + ".md-utils/md-utils.json").write(#"{"configVersion":"0.2.0","rules":[{"name":"notes","match":{"paths":["notes/**"]},"checks":[{"type":"requiredHeading","heading":"Note"}]}]}"#)
    try (root + ".md-utils/server/server.yaml").write("""
      serverConfigVersion: "3"
      persistentIdentity: {path: [uuid]}
      resources:
        - name: notes
          route: /notes
          operations: [list, get]
          selection: {mode: rule, rule: notes}
          identityPolicy: {source: logicalPath}
          writable:
            codec: {frontmatterFields: [title], bodyWritable: true}
          mutations:
            operations: [copy, move]
            creation: {directory: notes/}
      """)
    let source = "---\ntitle: Note\nuuid: 123e4567-e89b-12d3-a456-426614174000\n---\n# Note\nBody\n"
    try (root + "notes/original.md").write(source)
    let common = ["--resource", "notes", "--project-root", root.string]
    var copy = try #require(CLIEntry.parseAsRoot(["copy", "notes/original.md", "Copy.md",
      "--revision", IndexFingerprint.hash(Data(source.utf8)), "--idempotency-key", "copy",
    ] + common) as? CLIEntry.Copy)
    try await copy.run()
    let copied = try (root + "notes/Copy.md").read(.utf8)
    #expect(copied != source)
    #expect(copied.hasSuffix("Body\n"))
    var move = try #require(CLIEntry.parseAsRoot(["move", "notes/Copy.md", "Moved.md",
      "--revision", IndexFingerprint.hash(Data(copied.utf8)), "--idempotency-key", "move",
    ] + common) as? CLIEntry.Move)
    try await move.run()
    try await move.run()
    #expect(!(root + "notes/Copy.md").exists)
    #expect(try (root + "notes/Moved.md").read(.utf8) == copied)
    #expect(try (root + "notes/original.md").read(.utf8) == source)
  }
}
