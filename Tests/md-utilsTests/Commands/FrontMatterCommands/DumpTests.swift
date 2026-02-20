//
//  DumpTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils
import MarkdownUtilities
import ArgumentParser

@Suite("fm dump command")
struct DumpTests {

  @Test
  func `single file outputs directly without array or path`() async throws {
    let tempFile = try createTempFile(content: """
    ---
    title: Hello
    tags: [a, b]
    ---
    Body
    """, name: "single.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Should succeed without throwing
    try await command.run()
  }

  @Test
  func `multi-file default outputs collection with path`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-dump-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "alpha.md"
    let file2 = tempDir + "beta.md"

    try file1.write("""
    ---
    title: Alpha
    ---
    Body
    """)
    try file2.write("""
    ---
    title: Beta
    ---
    Body
    """)

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Should succeed — outputs JSON array with $path
    try await command.run()
  }

  @Test
  func `multi-file with cat-headers outputs cat-style headers`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-dump-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "one.md"
    let file2 = tempDir + "two.md"

    try file1.write("""
    ---
    title: One
    ---
    Body
    """)
    try file2.write("""
    ---
    title: Two
    ---
    Body
    """)

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      "--cat-headers",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Should succeed — outputs cat-style headers
    try await command.run()
  }

  @Test
  func `collection mode with yaml format`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-dump-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "a.md"
    let file2 = tempDir + "b.md"

    try file1.write("""
    ---
    title: A
    ---
    Body
    """)
    try file2.write("""
    ---
    title: B
    ---
    Body
    """)

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      "--format", "yaml",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Should succeed — outputs YAML sequence with $path
    try await command.run()
  }

  @Test
  func `collection mode with plist format`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-dump-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let file1 = tempDir + "x.md"
    let file2 = tempDir + "y.md"

    try file1.write("""
    ---
    title: X
    ---
    Body
    """)
    try file2.write("""
    ---
    title: Y
    ---
    Body
    """)

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      "--format", "plist",
      tempDir.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Should succeed — outputs plist array with $path
    try await command.run()
  }

  @Test
  func `single file ignores cat-headers flag`() async throws {
    let tempFile = try createTempFile(content: """
    ---
    title: Solo
    ---
    Body
    """, name: "solo.md")
    defer { try? tempFile.delete() }

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      "--cat-headers",
      tempFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Single file always outputs directly regardless of --cat-headers
    try await command.run()
  }

  // MARK: - Invalid YAML Error Handling Tests

  @Test
  func `batch dump skips file with invalid YAML and exits with failure`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-invalid-yaml-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let goodFile = tempDir + "good.md"
    let badFile = tempDir + "bad.md"

    try goodFile.write("""
    ---
    title: Good File
    ---
    Body
    """)
    // Invalid YAML: unclosed array bracket
    try badFile.write("""
    ---
    key: [unclosed
    ---
    Body
    """)

    let command_ = try CLIEntry.FrontMatterCommands.Dump.parseAsRoot([
      goodFile.string, badFile.string
    ])
    var command = try #require(command_ as? CLIEntry.FrontMatterCommands.Dump)

    // Should skip the bad file and exit with failure, not propagate the raw YAML error
    do {
      try await command.run()
      Issue.record("Expected ExitCode.failure to be thrown")
    } catch let code as ExitCode {
      #expect(code == ExitCode.failure)
    } catch {
      Issue.record("Expected ExitCode, got: \(error)")
    }
  }

  // MARK: - Test Helpers

  private func createTempFile(content: String, name: String) throws -> Path {
    let tempDir = Path(NSTemporaryDirectory())
    let tempFile = tempDir + "md-utils-test-\(UUID().uuidString)-\(name)"
    try tempFile.write(content)
    return tempFile
  }
}
