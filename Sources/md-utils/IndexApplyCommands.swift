import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer
import MarkdownUtilitiesServerNative

extension CLIEntry.Index {
  /// Applies independently persisted drafts through the shared native mutation service.
  struct Apply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Apply revision-checked pending edits, or preview without writes")
    @Argument(help: "Optional draft UUIDs; omit to select all pending drafts") var ids: [String] = []
    @OptionGroup var options: DraftOptions
    @Flag(help: "Show concrete source changes and diagnostics without persistent writes") var dryRun = false
    @Option(help: "Output format: text or jsonl") var format: DraftOutputFormat = .text

    mutating func run() async throws {
      let format = format
      let success = try await options.service.apply(ids: ids, dryRun: dryRun) { result in
        try DraftOutput.report(result, format: format)
      }
      if !success { throw ExitCode.failure }
    }
  }

  /// Manages explicit edit intent independently of disposable SQLite rows.
  struct Draft: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stage, inspect, discard, and resolve pending source edits",
      subcommands: [Add.self, List.self, Show.self, Discard.self, Resolve.self,])

    struct Add: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Stage an explicit JSON patch or replacement against a source SHA-256")
      @Argument(help: "Collection-relative Markdown source path") var path: String
      @Option(help: "Configured resource name") var resource: String
      @Option(help: "Expected raw canonical source SHA-256") var revision: String
      @Option(help: "File containing the shared JSON patch envelope") var patchFile: String?
      @Option(help: "File containing the shared JSON replacement envelope") var replaceFile: String?
      @OptionGroup var options: DraftOptions

      mutating func run() async throws {
        guard (patchFile != nil) != (replaceFile != nil), let file = patchFile ?? replaceFile else {
          throw ValidationError("Supply exactly one of --patch-file or --replace-file.")
        }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file)); defer { try? handle.close() }
        let data = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
        let request = try MarkdownMutationRequest(operation: patchFile != nil ? .patch : .replace, data: data)
        let draft = try await options.service.stage(path: MarkdownRecordPath(path), resource: resource,
          revision: .init(rawValue: revision), request: request)
        try DraftOutput.json(draft)
      }
    }

    struct List: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "List durable drafts without refreshing the index")
      @OptionGroup var options: DraftOptions
      mutating func run() async throws {
        let service = options.service
        for id in try service.draftIDs() { try DraftOutput.json(service.draft(id)) }
      }
    }

    struct Show: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Read one durable draft without changing it")
      @Argument(help: "Draft UUID") var id: String
      @OptionGroup var options: DraftOptions
      mutating func run() async throws { try DraftOutput.json(options.service.draft(id)) }
    }

    struct Discard: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Discard an unsubmitted or completed draft")
      @Argument(help: "Draft UUID") var id: String
      @OptionGroup var options: DraftOptions
      mutating func run() async throws { try await options.service.discard(id) }
    }

    struct Resolve: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Explicitly resolve a submitted draft's mutation outcome")
      @Argument(help: "Draft UUID") var id: String
      @Option(help: "Operator assertion: confirmCommitted or confirmNotCommitted") var decision: String
      @OptionGroup var options: DraftOptions
      mutating func run() async throws {
        guard let decision = MarkdownRecoveryDecision(rawValue: decision) else {
          throw ValidationError("--decision must be confirmCommitted or confirmNotCommitted.")
        }
        try DraftOutput.json(try await options.service.resolve(id, decision: decision))
      }
    }
  }
}

/// Explicit project/resource configuration for offline draft operations.
struct DraftOptions: ParsableArguments {
  @Option(help: "Project root directory") var projectRoot: String = "."
  @Option(help: "Optional server resource configuration file") var serverConfig: String?
  var service: MarkdownDraftService { .init(projectRoot: projectRoot, configurationFile: serverConfig) }
}

enum DraftOutputFormat: String, ExpressibleByArgument { case text, jsonl }

enum DraftOutput {
  static func json<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
  }

  static func report(_ result: MarkdownDraftReport, format: DraftOutputFormat) throws {
    if format == .jsonl { try json(result); return }
    print("Draft \(result.draftID): \(result.state.rawValue)")
    if let path = result.path { print("Path: \(path.rawValue)") }
    if let resolution = result.resolution { print(resolution) }
    if let original = result.originalSource, let proposed = result.proposedSource {
      if original == proposed { print("Source unchanged (semantic no-op).") }
      else {
        print("--- Original source\n\(original)\n+++ Proposed source\n\(proposed)\n--- End source preview")
      }
    }
    for diagnostic in result.diagnostics { print("\(diagnostic.severity.rawValue): \(diagnostic.code): \(diagnostic.message)") }
    for change in result.conformanceChanges where (change.previouslyPassed && !change.passes)
      || (change.previouslySelected && !change.selected) {
      print("\(change.kind.rawValue).\(change.name): passes=\(change.passes), selected=\(change.selected)")
    }
    if let receipt = result.receipt { print("Receipt: \(receipt.id), state: \(receipt.state.rawValue), source committed: \(receipt.sourceCommitted)") }
    if let code = result.failureCode { print("\(code): \(result.failureMessage ?? "")") }
  }
}
