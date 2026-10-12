import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  struct ConvertLinks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "convert",
      abstract: "Convert wikilink targets between wiki-path and wiki-link styles",
      discussion: """
        Preview by default; --in-place explicitly writes changes. --root is required.
        wiki-path emits collection-root-relative paths with extensions; wiki-link
        emits unique names. --markdown-extension overrides Markdown suffix spelling;
        non-Markdown extensions are always retained. Missing, ambiguous,
        or destination-changing conversions are skipped with diagnostics.
        Self-heading links are preserved. Body scanning includes literal wikilinks
        in code. Frontmatter selection processes strings and arrays, not objects.
        Metadata edits preserve values but may reformat YAML/TOML and remove comments.
        Example: md-utils links convert --to wiki-path notes/ --root vault/
        """,
    )

    @OptionGroup var options: GlobalOptions
    @Option(name: .long, help: "Required collection root directory (vault/)", transform: { Path($0) })
    var root: Path
    @Option(name: .long, help: "Target style: wiki-path or wiki-link")
    var to: String
    @Option(name: .long, help: "Markdown extensions: auto (include for wiki-path, omit for wiki-link), include, omit; other extensions are always retained")
    var markdownExtension = "auto"
    @Option(name: .long, help: "Occurrences to select: all, body, frontmatter")
    var scope = "all"
    @Option(name: .long, help: "Literal top-level key; repeatable, requires --scope frontmatter")
    var key: [String] = []
    @Flag(name: .long, help: "Write changes instead of only previewing them")
    var inPlace = false
    @Flag(name: .long, help: "Emit a structured JSON report")
    var json = false

    mutating func run() async throws {
      guard let style = WikilinkTargetStyle(rawValue: to) else {
        throw ValidationError("--to must be wiki-path or wiki-link")
      }
      guard let selection = WikilinkConversionScope(rawValue: scope) else {
        throw ValidationError("--scope must be all, body, or frontmatter")
      }
      guard let extensionPolicy = WikilinkMarkdownExtension(rawValue: markdownExtension) else {
        throw ValidationError("--markdown-extension must be auto, include, or omit")
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
  }
}

private struct LinkConversionFileReport: Encodable {
  let file: String
  let status: String
  let changes: [WikilinkConversionChange]
  let error: String?
}
