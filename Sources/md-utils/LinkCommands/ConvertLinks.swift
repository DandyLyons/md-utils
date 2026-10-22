import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import PathKit

extension CLIEntry {
  struct ConvertLinks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "convert",
      abstract: "Convert wikilink targets to a style or loaded type's constraints",
      discussion: """
        Preview by default; --in-place explicitly writes changes. --root is required.
        Supply exactly one of --to or --type. Input paths are relative to the
        working directory and must be inside --root (they are not root-relative).
        wiki-path emits collection-root-relative paths with extensions; wiki-link
        emits unique names. --markdown-extension overrides Markdown suffix spelling;
        non-Markdown extensions are always retained. Missing, ambiguous,
        or destination-changing conversions are skipped with diagnostics.
        Self-heading links are preserved. Body scanning includes literal wikilinks
        in code. --to frontmatter selection processes strings and arrays, not objects.
        Metadata edits preserve values but may reformat YAML/TOML and remove comments.
        Alternatively, --type selects declared whole-value frontmatter wikilinks,
        including nested objects/arrays. Preferences only disambiguate permitted
        repairs; conforming values stay unchanged. Unresolved repairs exit nonzero.
        Contract preview reads bounded collection evidence without refreshing an index.
        --to defaults to --scope all; --type selects frontmatter only. With --to,
        auto includes Markdown extensions for wiki-path and omits them for wiki-link.
        With --type, auto expresses no extension preference. --prefer-style and
        --include-recommendations require --type. Lexical repairs do not establish
        whole-type conformance; inspect the separate assessment in the report.
        Example: md-utils links convert --to wiki-path vault/notes/ --root vault/
        Example: md-utils links convert vault/notes/ --root vault/ --type Article --prefer-style relative-path
        """,
    )

    @OptionGroup var options: GlobalOptions
    @Option(name: .long, help: "Required collection root directory (vault/)", transform: { Path($0) })
    var root: Path
    @Option(name: .long, help: "Target style: wiki-path or wiki-link")
    var to: String?
    @Option(name: .long, help: "Loaded mdtype v2 name; mutually exclusive with --to; selects declared frontmatter values")
    var type: String?
    @Option(name: .long, help: "Requires --type; repair preference: name, vault-path, relative-path, self-anchor")
    var preferStyle: String?
    @Flag(name: .long, help: "Requires --type; include recommended schemas in contract repairs")
    var includeRecommendations = false
    @Option(name: .long, help: "Markdown extensions: auto (style default, or no preference with --type), include, omit; never overrides a contract")
    var markdownExtension = "auto"
    @Option(name: .long, help: "Occurrences: all (default with --to), body, frontmatter (only scope with --type)")
    var scope: String?
    @Option(name: .long, help: "Literal top-level key/subtree; repeatable, requires --scope frontmatter with --to")
    var key: [String] = []
    @Flag(name: .long, help: "Write changes instead of only previewing them")
    var inPlace = false
    @Flag(name: .long, help: "Emit a structured JSON report")
    var json = false

    mutating func run() async throws {
      guard (type == nil) != (to == nil) else { throw ValidationError("Specify exactly one of --to or --type") }
      guard let extensionPolicy = WikilinkMarkdownExtension(rawValue: markdownExtension) else {
        throw ValidationError("--markdown-extension must be auto, include, or omit")
      }
      if let type {
        guard scope == nil || scope == "frontmatter" else { throw ValidationError("--type selects frontmatter; --scope must be frontmatter if supplied") }
        guard preferStyle.map({ ["name", "vault-path", "relative-path", "self-anchor"].contains($0) }) ?? true else {
          throw ValidationError("--prefer-style must be name, vault-path, relative-path, or self-anchor")
        }
        try await runContract(type: type)
        return
      }
      guard preferStyle == nil && !includeRecommendations else { throw ValidationError("--prefer-style and --include-recommendations require --type") }
      guard let to, let style = WikilinkTargetStyle(rawValue: to) else {
        throw ValidationError("--to must be wiki-path or wiki-link")
      }
      guard let selection = WikilinkConversionScope(rawValue: scope ?? "all") else {
        throw ValidationError("--scope must be all, body, or frontmatter")
      }
      guard key.isEmpty || selection == .frontmatter else {
        throw ValidationError("--key requires --scope frontmatter")
      }
      let files = try options.resolvedPaths(skipSymlinks: true)
      guard !files.isEmpty else { throw ValidationError("No Markdown files found") }
      var resolver = try WikilinkResolver(root: root)
      var results: [LinkConversionFileReport] = []
      var stopped = false
      for file in files {
        if stopped {
          results.append(.init(file: file.string, status: "unprocessed", changes: [], error: nil))
          continue
        }
        do {
          let absolute = file.absolute()
          let rootPrefix = resolver.root.string.hasSuffix("/") ? resolver.root.string : resolver.root.string + "/"
          guard absolute.string.hasPrefix(rootPrefix) else {
            throw ValidationError("Input file must be inside --root")
          }
          let url = URL(fileURLWithPath: absolute.string)
          guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
            throw ValidationError("Symlink input paths are not supported")
          }
          // Refresh resolution evidence immediately before each planned write.
          if inPlace { resolver = try WikilinkResolver(root: root) }
          let source = try FrontMatterFileWriter.readSnapshot(from: file)
          let plan = try WikilinkConversion.plan(
            source: source, file: file, resolver: resolver,
            style: style, markdownExtension: extensionPolicy, scope: selection, keys: key,
          )
          if inPlace && plan.hasChanges {
            try FrontMatterFileWriter.write(plan.proposed, to: file, expectedSource: plan.source)
          }
          results.append(.init(
            file: file.string,
            status: plan.hasChanges ? (inPlace ? "changed" : "would-change") : "unchanged",
            changes: plan.changes, error: nil,
          ))
        } catch {
          results.append(.init(file: file.string, status: "failed", changes: [], error: error.localizedDescription))
          stopped = true
        }
      }
      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(results), as: UTF8.self))
      } else {
        for result in results {
          print("\(result.file): \(result.status)")
          for change in result.changes {
            print("  \(change.location): \(change.original) → \(change.replacement ?? "unchanged: " + (change.diagnostic ?? ""))")
          }
          if let error = result.error { print("  \(error)") }
        }
        for status in ["would-change", "changed", "unchanged", "failed", "unprocessed"] {
          print("\(status): \(results.filter { $0.status == status }.count)")
        }
        if !inPlace { print("Preview only. Use --in-place to write changes.") }
      }
      if stopped { throw ExitCode.failure }
    }

    private func runContract(type: String) async throws {
      let files = try options.resolvedPaths(skipSymlinks: true)
      guard !files.isEmpty else { throw ValidationError("No Markdown files found") }
      let preferences = WikilinkContractPreferences(style: preferStyle,
        markdownExtension: markdownExtension == "auto" ? nil : markdownExtension,
        keys: key, includeRecommendations: includeRecommendations)
      var reports: [ContractConversionFileReport] = []
      var stopped = false
      var cancelled = false
      for file in files {
        if stopped {
          reports.append(.init(file: file.string, status: "unprocessed", changes: [], assessment: nil, error: nil))
          continue
        }
        do {
          try Task.checkCancellation()
          let result = try await WikilinkContractConversionSession.run(file: file, root: root, type: type,
            preferences: preferences, apply: inPlace)
          var changes = result.plan.changes
          if result.applied {
            for index in changes.indices where changes[index].status == "would-change" { changes[index].status = "changed" }
          }
          reports.append(.init(file: file.string,
            status: result.plan.hasChanges ? (result.applied ? "changed" : "would-change") : (result.plan.unresolved ? "unresolved" : "unchanged"),
            changes: changes, assessment: result.assessment, error: nil))
        } catch {
          reports.append(.init(file: file.string, status: "failed", changes: [], assessment: nil, error: error.localizedDescription))
          stopped = true
          cancelled = error is CancellationError
        }
      }
      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(reports), as: UTF8.self))
      } else {
        for report in reports {
          print("\(report.file): \(report.status)")
          for change in report.changes {
            let path = change.path.map { component in
              switch component { case .key(let key): "[\(key)]"; case .index(let index): "[\(index)]" }
            }.joined()
            print("  frontmatter\(path): \(change.status)\(change.replacement.map { " → " + $0 } ?? "")\(change.reason.map { ": " + $0 } ?? "")")
          }
          if let assessment = report.assessment {
            print("  Whole type \(type): \(assessment.outcome.rawValue)")
            for diagnostic in assessment.diagnostics { print("    \(diagnostic.location): \(diagnostic.message)") }
          }
          if let error = report.error { print("  \(error)") }
        }
        if !inPlace { print("Preview only. Use --in-place to write changes.") }
      }
      if cancelled { throw CancellationError() }
      if stopped || reports.contains(where: { $0.changes.contains { $0.status == "unresolved" } }) { throw ExitCode.failure }
    }
  }
}

private struct ContractConversionFileReport: Encodable {
  let file: String
  let status: String
  let changes: [WikilinkContractChange]
  let assessment: MarkdownTypeAssessment?
  let error: String?
}

private struct LinkConversionFileReport: Encodable {
  let file: String
  let status: String
  let changes: [WikilinkConversionChange]
  let error: String?
}
