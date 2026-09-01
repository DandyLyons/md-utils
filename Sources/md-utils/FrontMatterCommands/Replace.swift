//
//  Replace.swift
//  md-utils
//
//  Replace entire frontmatter with new data
//

import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit
import Yams
/// Adds Markdown document behavior to ``CLIEntry.FrontMatterCommands``.
///
/// See <doc:FrontmatterCommands> for workflow details.
extension CLIEntry.FrontMatterCommands {
  /// Replace entire frontmatter with new data
  struct Replace: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "replace",
      abstract: "Replace entire frontmatter with new data",
      discussion: NonMarkdownFrontMatterHelp.appending(to: """
        Replace the complete frontmatter in files with new structured data.

        This is a DESTRUCTIVE operation - the entire frontmatter will be replaced.
        You will be prompted for confirmation before changes are made.

        INPUT METHODS:
          Provide data either inline or from a file (but not both):

          --data: Inline data string
            md-utils fm replace post.md --data '{"title": "New", "draft": false}' --format json

          --from-file: Read from file
            md-utils fm replace post.md --from-file new-frontmatter.json --format json

          TIP: When passing inline data that starts with -, use --data= syntax:
            md-utils fm replace post.md --data='- item1' --format yaml
            This prevents the argument parser from treating - as a flag.

        SUPPORTED FORMATS:
          - json: JavaScript Object Notation
          - yaml: YAML Ain't Markup Language
          - toml: Tom's Obvious, Minimal Language
          - plist: Apple PropertyList XML

        VALIDATION:
          Frontmatter must be a dictionary/mapping. Arrays and scalars will be rejected.

        CONFIRMATION:
          You will be prompted to confirm before replacing. Use this carefully!

        Examples:
          # Replace with inline JSON
          md-utils fm replace post.md --data '{"title": "New Title", "draft": false}' --format json

          # Replace from YAML file
          md-utils fm replace post.md --from-file metadata.yaml --format yaml

          # Replace from plist
          md-utils fm replace post.md --from-file metadata.plist --format plist

          # Process multiple files (prompted once per file)
          md-utils fm replace post1.md post2.md --data '{"status": "published"}' --format json
        """),
      aliases: ["r"]
    )

    @OptionGroup var options: GlobalOptions
    @OptionGroup var lineCommentOptions: LineCommentFrontMatterOptions

    @Option(name: .long, help: "Inline data to use as new frontmatter")
    var data: String?

    @Option(name: .long, help: "Path to file containing new frontmatter")
    var fromFile: String?

    @Option(name: [.short, .long], help: "Data format (json, yaml, toml, plist)")
    var format: OutputFormat = .json

    @Option(name: .long, help: "Frontmatter format to create or convert to (yaml, toml)")
    var frontmatterFormat: FrontMatterFormat?

    @Flag(name: [.customShort("y"), .long], help: "Skip confirmation prompt")
    var yes: Bool = false

    @Flag(name: .long, help: "Process mapped non-Markdown files")
    var includeNonMD = false

    @Flag(name: .long, help: "Authorize frontmatter creation in non-Markdown files")
    var createFrontmatter = false
    /// Runs the command using the parsed command-line arguments.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    mutating func run() async throws {
      // Validate input options
      guard data != nil || fromFile != nil else {
        throw ValidationError("Must specify either --data or --from-file")
      }

      guard !(data != nil && fromFile != nil) else {
        throw ValidationError("Cannot use both --data and --from-file")
      }

      // Get the data string
      let dataString: String
      if let inlineData = data {
        dataString = inlineData
      } else if let filePath = fromFile {
        dataString = try Path(filePath).read(.utf8)
      } else {
        throw ValidationError("Must specify either --data or --from-file")
      }

      // Parse to mapping based on format
      let newFrontMatter: FrontMatter
      do {
        switch format {
          case .json:
            newFrontMatter = try FrontMatterConversion.fromYAMLMapping(
              YAMLConversion.parseJSON(dataString)
            )
          case .yaml, .raw:
            newFrontMatter = try FrontMatterConversion.parse(dataString, format: .yaml)
          case .toml:
            newFrontMatter = try FrontMatterConversion.parse(dataString, format: .toml)
          case .plist:
            newFrontMatter = try FrontMatterConversion.fromYAMLMapping(
              YAMLConversion.parsePlist(dataString)
            )
        }
      } catch {
        throw ValidationError(error.localizedDescription)
      }

      // Process each file
      let files = try options.resolvedFrontMatterPaths(
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
        do {
          try replaceInFile(path: file, newFrontMatter: newFrontMatter)
        } catch {
          CLIStyle.writeError("\(CLIStyle.path(file.string)): \(error.localizedDescription)")
          hasErrors = true
          continue
        }
      }

      if hasErrors { throw ExitCode.failure }
    }
    /// Replaces frontmatter in one Markdown file.
    ///
    /// See <doc:FrontmatterCommands> for workflow details.
    private func replaceInFile(path: Path, newFrontMatter: FrontMatter) throws {
      let parsed = try FrontMatterCLIMutator.parsedFile(
        at: path,
        includeNonMarkdown: includeNonMD,
        lineCommentFrontmatter: lineCommentOptions.lineCommentFrontmatter
      )
      try FrontMatterCLIMutator.authorizeCreationIfNeeded(
        for: parsed,
        options: options,
        createFrontmatter: createFrontmatter
      )

      // Prompt for confirmation (unless --yes flag is used)
      if !yes {
        print(
          "\(CLIStyle.warning("⚠️"))  This will REPLACE the entire frontmatter in '\(CLIStyle.path(path.string))'. Continue? (y/n): ",
          terminator: ""
        )
        fflush(stdout)

        guard let response = readLine()?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
          print(CLIStyle.muted("Cancelled (no input)."))
          return
        }

        guard response == "y" || response == "yes" else {
          print(CLIStyle.muted("Cancelled."))
          return
        }
      }

      var doc = parsed.document
      if let frontmatterFormat { doc.frontMatterFormat = frontmatterFormat }

      // Replace frontmatter (direct assignment)
      doc.frontMatter = newFrontMatter

      // Render and write back
      try FrontMatterCLIMutator.write(doc, parsed: parsed, to: path)

      print("\(CLIStyle.success("✓")) Replaced frontmatter in '\(CLIStyle.path(path.string))'")
    }

  }
}
