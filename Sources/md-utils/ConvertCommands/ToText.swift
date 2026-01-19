//
//  ToText.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.ConvertCommands {
  /// Convert Markdown to plain text
  struct ToText: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "to-text",
      abstract: "Convert Markdown files to plain text",
      discussion: """
        Converts Markdown files to plain text by stripping all formatting
        while preserving content and readability.

        Examples:
          # Convert single file (creates file.txt next to file.md)
          md-utils convert to-text file.md

          # Convert entire directory recursively
          md-utils convert to-text docs/

          # Convert with custom output directory
          md-utils convert to-text docs/ --output output/

          # Include frontmatter in output
          md-utils convert to-text file.md --include-frontmatter

          # Use single-spacing between blocks
          md-utils convert to-text file.md --block-separator 1

          # Disable list indentation
          md-utils convert to-text file.md --no-indent-lists

        By default:
        - Processes directories recursively
        - Excludes frontmatter from output
        - Uses double-spacing between blocks
        - Indents nested lists
        - Preserves code blocks
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Output directory for converted files (default: same directory as source)",
      completion: .directory,
      transform: { Path($0) }
    )
    var output: Path?

    @Flag(
      name: .long,
      help: "Include YAML frontmatter in the plain text output"
    )
    var includeFrontmatter: Bool = false

    @Option(
      name: .long,
      help: "Number of newlines between block elements (default: 2)"
    )
    var blockSeparator: Int = 2

    @Flag(
      name: .long,
      inversion: .prefixedNo,
      help: "Indent nested list items (use --no-indent-lists to disable)"
    )
    var indentLists: Bool = true

    @Option(
      name: .long,
      help: "Number of spaces per indentation level (default: 2)"
    )
    var indentSpaces: Int = 2

    @Flag(
      name: .long,
      inversion: .prefixedNo,
      help: "Preserve code blocks in output (use --no-preserve-code to disable)"
    )
    var preserveCode: Bool = true

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No Markdown files found to process")
      }

      // Validate output directory if specified
      if let outputDir = output {
        if !outputDir.exists {
          try outputDir.mkpath()
        } else if !outputDir.isDirectory {
          throw ValidationError("Output path exists but is not a directory: \(outputDir)")
        }
      }

      // Create conversion options
      let conversionOptions = PlainTextOptions(
        includeFrontmatter: includeFrontmatter,
        blockSeparator: blockSeparator,
        preserveLineBreaks: true,
        extractImageAltText: true,
        indentLists: indentLists,
        indentSpaces: indentSpaces,
        preserveCodeBlocks: preserveCode
      )

      // Process each file
      var successCount = 0
      var errorCount = 0

      for file in files {
        do {
          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)
          let plainText = try await doc.toPlainText(options: conversionOptions)

          // Determine output path
          let outputPath = determineOutputPath(for: file)

          // Write the output
          try outputPath.write(plainText)

          print("✓ Converted: \(file) → \(outputPath)")
          successCount += 1
        } catch {
          print("✗ Error converting \(file): \(error.localizedDescription)")
          errorCount += 1
        }
      }

      // Print summary
      print("\nConversion complete:")
      print("  Success: \(successCount)")
      if errorCount > 0 {
        print("  Errors: \(errorCount)")
        throw ExitCode.failure
      }
    }

    /// Determines the output path for a converted file.
    ///
    /// - Parameter inputPath: The path to the source Markdown file
    /// - Returns: The path where the converted text file should be written
    private func determineOutputPath(for inputPath: Path) -> Path {
      // Get the filename without extension
      let basename = inputPath.lastComponentWithoutExtension

      if let outputDir = output {
        // Output to specified directory
        return outputDir + "\(basename).txt"
      } else {
        // Output to same directory as input
        return inputPath.parent() + "\(basename).txt"
      }
    }
  }
}
