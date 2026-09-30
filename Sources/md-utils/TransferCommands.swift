import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer
import MarkdownUtilitiesServerNative

extension CLIEntry {
  struct Copy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Copy a configured resource record with a fresh UUID")
    @OptionGroup var options: TransferOptions
    @Option(help: "JSON object of configured creation identifiers, such as a new slug") var identifiers: String = "{}"
    mutating func run() async throws { try await options.run(.copy, identifiers: identifiers) }
  }
  struct Move: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Move or rename a configured resource record, preserving its UUID")
    @OptionGroup var options: TransferOptions
    mutating func run() async throws { try await options.run(.move) }
  }
}

struct TransferOptions: ParsableArguments {
  @Argument(help: "Collection-relative source Markdown path") var source: String
  @Argument(help: "Destination filename inside the resource's configured allocation directory") var filename: String
  @Option(help: "Configured resource name; copy/move must be explicitly enabled") var resource: String
  @Option(help: "Project root directory") var projectRoot: String = "."
  @Option(help: "Optional server configuration file") var serverConfig: String?
  @Option(help: "Idempotency key; reuse the same key only for an exact retry") var idempotencyKey: String
  @Option(help: "Expected canonical source SHA-256; retain it for exact idempotent retries") var revision: String

  func run(_ operation: MarkdownMutationOperation, identifiers: String? = nil) async throws {
    let repository = try IndexedMarkdownRepository(projectRoot: projectRoot, configurationFile: serverConfig)
    let path = try MarkdownRecordPath(source)
    let expected = MarkdownRecordRevision(rawValue: revision)
    var payload: [String: JSONValue] = ["filename": .string(filename)]
    if let identifiers {
      payload["identifiers"] = .object(try JSONDecoder().decode([String: JSONValue].self, from: Data(identifiers.utf8)))
    }
    let receipt = try await repository.mutate(resource: resource, identity: nil, path: path,
      request: .init(operation: operation, data: JSONEncoder().encode(payload)), revision: expected, idempotencyKey: idempotencyKey)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(receipt), as: UTF8.self))
    if receipt.state != .completed { throw ExitCode.failure }
  }
}
