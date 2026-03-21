//
//  Replace.swift
//  md-utils
//
//  Replace entire frontmatter with new data
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands {
  /// Replace entire frontmatter with new data
  struct Replace: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "replace",
      abstract: "Replace entire frontmatter with new data",
      discussion: """
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
        """,
      aliases: ["r"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Inline data to use as new frontmatter")
    var data: String?

    @Option(name: .long, help: "Path to file containing new frontmatter")
    var fromFile: String?

    @Option(name: [.short, .long], help: "Data format (json, yaml, plist)")
    var format: OutputFormat = .json

    @Flag(name: [.customShort("y"), .long], help: "Skip confirmation prompt")
    var yes: Bool = false

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
      let newFrontMatter: Yams.Node.Mapping
      do {
        switch format {
          case .json:
            newFrontMatter = try YAMLConversion.parseJSON(dataString)
          case .yaml, .raw:
            newFrontMatter = try YAMLConversion.parse(dataString)
          case .plist:
            newFrontMatter = try YAMLConversion.parsePlist(dataString)
        }
      } catch let error as YAMLConversionError {
        throw ValidationError(error.localizedDescription)
      }

      // Process each file
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      var hasErrors = false

      for file in files {
        do {
          try replaceInFile(path: file, newFrontMatter: newFrontMatter)
        } catch {
          fputs("error: \(file): \(error.localizedDescription)\n", stderr)
          hasErrors = true
          continue
        }
      }

      if hasErrors { throw ExitCode.failure }
    }

    private func replaceInFile(path: Path, newFrontMatter: Yams.Node.Mapping) throws {
      // Prompt for confirmation (unless --yes flag is used)
      if !yes {
        print("⚠️  This will REPLACE the entire frontmatter in '\(path)'. Continue? (y/n): ", terminator: "")
        fflush(stdout)

        guard let response = readLine()?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
          print("Cancelled (no input).")
          return
        }

        guard response == "y" || response == "yes" else {
          print("Cancelled.")
          return
        }
      }

      // Read and parse document
      let content: String = try path.read()
      var doc = try MarkdownDocument(content: content)

      if doc.containsYAMLComments {
        fputs("warning: \(path): frontmatter contains YAML comments which will be lost\n", stderr)
      }

      // Replace frontmatter (direct assignment)
      doc.frontMatter = newFrontMatter

      // Render and write back
      let updatedContent = try doc.render()
      try path.write(updatedContent)

      print("✓ Replaced frontmatter in '\(path)'")
    }

  }
}
