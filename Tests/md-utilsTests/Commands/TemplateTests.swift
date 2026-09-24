import Foundation
import Testing
@testable import md_utils

@Suite("template render command")
struct TemplateTests {
  @Test
  func `warnings go to stderr while stdout contains only Markdown`() throws {
    let directory = URL(fileURLWithPath: "tmp/template-warnings-\(UUID().uuidString)/", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let template = directory.appendingPathComponent("body.knap")
    let input = directory.appendingPathComponent("input.json")
    try "{{ data | date:'YYYY' }}".write(to: template, atomically: true, encoding: .utf8)
    try #"{"data":"not-a-date"}"#.write(to: input, atomically: true, encoding: .utf8)
    let result = try CLIProcessTestHelper.run([
      "template", "render", "--template", template.path, "--data", input.path,
    ])
    #expect(result.status == 0)
    #expect(result.standardOutput == "not-a-date")
    #expect(result.standardError.contains("template.knap.INVALID_FILTER_INPUT"))
    #expect(result.standardError.contains("template:1:"))
  }

  @Test(arguments: ["output.swift", "output.py", "output.txt", "output", "output.md.swift"])
  func `unsupported outputs fail before reading or writing`(output: String) async throws {
    var command = try #require(CLIEntry.parseAsRoot(["template", "render",
      "--template", "nonexistent.knap", "--data", "nonexistent.json", "--output", output])
      as? CLIEntry.TemplateCommands.Render)
    do {
      try await command.run()
      Issue.record("Expected unsupported output error")
    } catch {
      #expect(String(describing: error).contains("Non-Markdown generation is unsupported"))
    }
  }

  @Test
  func `renders output and leaves existing bytes untouched on failure`() async throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("tmp/template-tests-\(UUID().uuidString)/", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let template = directory.appendingPathComponent("body.knap")
    let data = directory.appendingPathComponent("input.json")
    let output = directory.appendingPathComponent("output.md")
    try "{{ frontmatter.title | h1 }}\n{{ data }}".write(to: template, atomically: true, encoding: .utf8)
    try #"{"frontmatter":{"title":"Sales: September"},"data":"Hello"}"#
      .write(to: data, atomically: true, encoding: .utf8)
    let arguments = ["template", "render", "--template", template.path,
      "--data", data.path, "--output", output.path]
    var command = try #require(CLIEntry.parseAsRoot(arguments) as? CLIEntry.TemplateCommands.Render)
    try await command.run()
    let expected = try Data(contentsOf: output)
    #expect(String(decoding: expected, as: UTF8.self).hasSuffix("# Sales: September\nHello"))
    try "{{ data | nonexistent_filter }}".write(to: template, atomically: true, encoding: .utf8)
    await #expect(throws: (any Error).self) { try await command.run() }
    #expect(try Data(contentsOf: output) == expected)
  }
}
