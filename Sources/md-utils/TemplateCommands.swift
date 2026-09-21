import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates

extension CLIEntry {
  struct TemplateCommands: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "template",
      abstract: "Render a Stencil body with explicit YAML frontmatter (prototype).",
      subcommands: [Render.self]
    )

    struct Render: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Render and validate one document before writing it."
      )

      @Option(help: "Self-contained Stencil body template file.")
      var template: String

      @Option(help: "JSON envelope containing data and an optional frontmatter object.")
      var data: String

      @Option(help: "Optional JSON Schema file validating the entire input envelope.")
      var schema: String?

      @Option(help: "Markdown output file (.md or .markdown); omit to write Markdown to stdout.")
      var output: String?

      mutating func run() async throws {
        if let output {
          let fileExtension = URL(fileURLWithPath: output).pathExtension.lowercased()
          guard ["md", "markdown"].contains(fileExtension) else {
            throw ValidationError("Template output must use .md or .markdown. Non-Markdown generation is unsupported; future support depends on issue #134.")
          }
        }
        let limits = MarkdownTemplateLimits()
        let templateBytes = try Self.read(template, limit: limits.templateBytes)
        guard let source = String(data: templateBytes, encoding: .utf8) else {
          throw ValidationError("Template must be UTF-8: \(template)")
        }
        let input = try JSONDecoder().decode(MarkdownTemplateInput.self,
          from: Self.read(data, limit: limits.inputBytes))
        let inputSchema = try schema.map {
          try JSONDecoder().decode(JSONValue.self, from: Self.read($0, limit: limits.inputBytes))
        }
        let result = try await MarkdownTemplateRenderer(limits: limits)
          .render(template: source, input: input, schema: inputSchema)
        if let output {
          try result.source.write(toFile: output, atomically: true, encoding: .utf8)
        } else {
          try FileHandle.standardOutput.write(contentsOf: Data(result.source.utf8))
        }
      }

      private static func read(_ path: String, limit: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? file.close() }
        var bytes = Data()
        while let chunk = try file.read(upToCount: min(64 * 1_024, limit + 1 - bytes.count)),
              chunk.isEmpty == false {
          bytes.append(chunk)
          guard bytes.count <= limit else {
            throw ValidationError("File exceeds the \(limit)-byte limit: \(path)")
          }
        }
        return bytes
      }
    }
  }
}
