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

        EXAMPLES:
          # Single file to stdout
          md-utils convert to-text README.md
          md-utils convert to-text README.md | less

          # Single file to specific file
          md-utils convert to-text README.md -o output.txt

          # Single file to directory
          md-utils convert to-text src/README.md -o output/

          # Batch conversion
          md-utils convert to-text docs/ -o output/
          md-utils convert to-text *.md -o output/

          # In-place conversion (.md → .txt)
          md-utils convert to-text docs/ --in-place
          md-utils convert to-text file.md --in-place

          # From stdin
          cat README.md | md-utils convert to-text
          cat README.md | md-utils convert to-text -o output.txt

          # With conversion options
          md-utils convert to-text file.md --include-frontmatter
          md-utils convert to-text docs/ -o out/ --block-separator 1

        By default:
        - Single file outputs to stdout
        - Excludes frontmatter from output
        - Uses double-spacing between blocks
        - Indents nested lists
        - Preserves code blocks
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: [.short, .long],
      help: """
        Output file or directory. For single file: writes to this file or \
        dir/basename.txt. For multiple files: must be a directory. \
        If not specified, writes to stdout (single file) or requires \
        --in-place (batch).
        """,
      completion: .file(),
      transform: { Path($0) }
    )
    var output: Path?

    @Flag(
      name: .long,
      help: """
        Convert .md files to .txt in their original locations. \
        Cannot be used with --output.
        """
    )
    var inPlace: Bool = false

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
      // Validate flags
      try validateFlags()

      // Determine input source
      let inputMode = try determineInputMode()

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

      // Process based on input mode
      switch inputMode {
      case .stdin:
        try await processStdin(options: conversionOptions)

      case .singleFile(let file):
        try await processSingleFile(file, options: conversionOptions)

      case .multipleFiles(let files):
        try await processMultipleFiles(files, options: conversionOptions)
      }
    }

    // MARK: - Input Mode Detection

    enum InputMode {
      case stdin
      case singleFile(Path)
      case multipleFiles([Path])
    }

    func determineInputMode() throws -> InputMode {
      // Check for stdin BEFORE resolving paths (stdin detection when no paths provided)
      if options.paths.isEmpty {
        // Check if stdin has data
        if isatty(STDIN_FILENO) == 0 {
          return .stdin
        } else {
          throw ValidationError("No input specified. Provide file paths or pipe input to stdin.")
        }
      }

      // Resolve paths for file inputs
      let files = try options.resolvedPaths()

      if files.isEmpty {
        throw ValidationError("No Markdown files found to process")
      }

      // Single file or multiple files
      if files.count == 1 {
        return .singleFile(files[0])
      } else {
        return .multipleFiles(files)
      }
    }

    // MARK: - Validation

    func validateFlags() throws {
      // Cannot use both --output and --in-place
      if output != nil && inPlace {
        throw ValidationError("Cannot use both --output and --in-place")
      }
    }

    // MARK: - Processing Methods

    func processStdin(options conversionOptions: PlainTextOptions) async throws {
      // Read from stdin
      var stdinContent = ""
      while let line = readLine(strippingNewline: false) {
        stdinContent += line
      }

      guard !stdinContent.isEmpty else {
        throw ValidationError("No input received from stdin")
      }

      // Convert
      let doc = try MarkdownDocument(content: stdinContent)
      let plainText = try await doc.toPlainText(options: conversionOptions)

      // Output
      if let outputPath = output {
        // Write to file
        try outputPath.write(plainText)
      } else {
        // Write to stdout
        print(plainText, terminator: "")
      }
    }

    func processSingleFile(_ file: Path, options conversionOptions: PlainTextOptions) async throws {
      // Read and convert
      let content: String = try file.read()
      let doc = try MarkdownDocument(content: content)
      let plainText = try await doc.toPlainText(options: conversionOptions)

      // Determine output destination
      if let outputPath = output {
        // Output to file or directory
        let finalPath = resolveOutputPath(outputPath, for: file)
        try finalPath.write(plainText)
      } else if inPlace {
        // Replace .md with .txt in same location
        let txtPath = file.parent() + "\(file.lastComponentWithoutExtension).txt"
        try txtPath.write(plainText)
      } else {
        // Default: write to stdout
        print(plainText, terminator: "")
      }
    }

    func processMultipleFiles(_ files: [Path], options conversionOptions: PlainTextOptions) async throws {
      // Validate: must have --output DIR or --in-place
      if output == nil && !inPlace {
        throw ValidationError(
          "Multiple input files require --output <directory> or --in-place"
        )
      }

      // If using --output, ensure it's a directory
      if let outputPath = output {
        if outputPath.exists && !outputPath.isDirectory {
          throw ValidationError(
            "Batch conversion requires output directory, not file: \(outputPath)"
          )
        }
        // Create directory if it doesn't exist
        if !outputPath.exists {
          try outputPath.mkpath()
        }
      }

      // Process each file
      var successCount = 0
      var errorCount = 0

      for file in files {
        do {
          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)
          let plainText = try await doc.toPlainText(options: conversionOptions)

          // Determine output path
          let finalPath: Path
          if inPlace {
            finalPath = file.parent() + "\(file.lastComponentWithoutExtension).txt"
          } else if let outputDir = output {
            // Preserve directory structure relative to base
            finalPath = outputDir + "\(file.lastComponentWithoutExtension).txt"
          } else {
            fatalError("Unreachable: validation should have caught this")
          }

          // Ensure parent directory exists
          if !finalPath.parent().exists {
            try finalPath.parent().mkpath()
          }

          // Write output
          try finalPath.write(plainText)

          FileHandle.standardError.write("✓ Converted: \(file) → \(finalPath)\n".data(using: .utf8)!)
          successCount += 1
        } catch {
          FileHandle.standardError.write("✗ Error converting \(file): \(error.localizedDescription)\n".data(using: .utf8)!)
          errorCount += 1
        }
      }

      // Print summary to stderr
      FileHandle.standardError.write("\nConversion complete:\n".data(using: .utf8)!)
      FileHandle.standardError.write("  Success: \(successCount)\n".data(using: .utf8)!)
      if errorCount > 0 {
        FileHandle.standardError.write("  Errors: \(errorCount)\n".data(using: .utf8)!)
        throw ExitCode.failure
      }
    }

    // MARK: - Helper Methods

    /// Resolves the output path for a single file.
    ///
    /// If outputPath is a directory (or ends with /), returns outputPath/basename.txt.
    /// Otherwise, returns outputPath as-is (treat as file).
    func resolveOutputPath(_ outputPath: Path, for inputFile: Path) -> Path {
      // Check if it's a directory
      if outputPath.isDirectory {
        return outputPath + "\(inputFile.lastComponentWithoutExtension).txt"
      }

      // Check if it ends with / (treat as directory even if it doesn't exist yet)
      if outputPath.string.hasSuffix("/") {
        // Create directory if needed
        let dirPath = Path(String(outputPath.string.dropLast()))
        return dirPath + "\(inputFile.lastComponentWithoutExtension).txt"
      }

      // Otherwise, treat as file
      return outputPath
    }
  }
}
