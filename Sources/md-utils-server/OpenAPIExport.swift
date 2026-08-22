import ArgumentParser
import Foundation
import MarkdownUtilitiesServer
import PathKit

extension ServerEntry {
  /// CLI-facing OpenAPI output formats.
  enum OpenAPIOutputFormat: String, ExpressibleByArgument {
    case json
    case yaml

    var libraryValue: MarkdownServerOpenAPIFormat {
      switch self {
      case .json: .json
      case .yaml: .yaml
      }
    }
  }

  /// Exports the configured plan's OpenAPI contract without importing Markdown records.
  struct OpenAPIExport: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "openapi",
      abstract: "Export the generated OpenAPI 3.1 contract without starting the server."
    )

    @Option(
      name: .long,
      help: "Project directory containing Markdown records and .md-utils/."
    )
    var projectRoot = "."

    @Option(
      name: .long,
      help: "Server YAML path relative to --project-root (default: .md-utils/server/server.yaml)."
    )
    var config: String?

    @Option(name: .long, help: "Output format: json or yaml.")
    var format: OpenAPIOutputFormat

    @Option(name: .long, help: "File path to write. Existing files are replaced.")
    var output: String

    mutating func run() throws {
      let loader = MarkdownServerProjectLoader(
        projectRoot: Path(projectRoot),
        configurationFile: config.map { Path($0) }
      )
      let runtime = try loader.loadPlan()
      let document = try MarkdownServerOpenAPIGenerator.generate(from: runtime.plan)
      let data = try document.serialized(format: format.libraryValue)
      try data.write(to: URL(fileURLWithPath: Path(output).absolute().string), options: .atomic)
    }
  }
}
