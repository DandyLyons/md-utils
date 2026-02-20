//
//  ToRTF.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.ConvertCommands {
  /// Convert Markdown to RTF
  struct ToRTF: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "to-rtf",
      abstract: "Convert Markdown files to RTF",
      discussion: """
        Converts Markdown files to RTF (Rich Text Format) with formatted
        text including headings, bold, italic, code, and links.

        EXAMPLES:
          # Single file to stdout (raw RTF data)
          md-utils convert to-rtf README.md

          # Single file to specific file
          md-utils convert to-rtf README.md -o output.rtf

          # Single file to directory
          md-utils convert to-rtf src/README.md -o output/

          # Batch conversion
          md-utils convert to-rtf docs/ -o output/
          md-utils convert to-rtf *.md -o output/

          # In-place conversion (.md → .rtf)
          md-utils convert to-rtf docs/ --in-place
          md-utils convert to-rtf file.md --in-place

          # From stdin
          cat README.md | md-utils convert to-rtf -o output.rtf

          # With custom font options
          md-utils convert to-rtf file.md -o out.rtf --font-name "Georgia" --font-size 16

        By default:
        - Single file outputs raw RTF to stdout
        - Uses Helvetica 14pt for body text
        - Uses Menlo for code
        - Preserves hyperlinks
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: [.short, .long],
      help: """
        Output file or directory. For single file: writes to this file or \
        dir/basename.rtf. For multiple files: must be a directory. \
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
        Convert .md files to .rtf in their original locations. \
        Cannot be used with --output.
        """
    )
    var inPlace: Bool = false

    @Flag(
      name: .long,
      help: "Include YAML frontmatter in the RTF output"
    )
    var includeFrontmatter: Bool = false

    @Option(
      name: .long,
      help: "Base font name for body text (default: Helvetica)"
    )
    var fontName: String = "Helvetica"

    @Option(
      name: .long,
      help: "Base font size in points (default: 14)"
    )
    var fontSize: Double = 14

    @Option(
      name: .long,
      help: "Monospace font name for code elements (default: Menlo)"
    )
    var monoFont: String = "Menlo"

    @Flag(
      name: .long,
      inversion: .prefixedNo,
      help: "Preserve hyperlinks in RTF output (use --no-preserve-links to disable)"
    )
    var preserveLinks: Bool = true

    mutating func run() async throws {
      try validateFlags()
      let inputMode = try determineInputMode()

      let conversionOptions = RTFOptions(
        includeFrontmatter: includeFrontmatter,
        baseFontName: fontName,
        baseFontSize: CGFloat(fontSize),
        monospaceFontName: monoFont,
        preserveLinks: preserveLinks
      )

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
      if options.paths.isEmpty {
        if isatty(STDIN_FILENO) == 0 {
          return .stdin
        } else {
          throw ValidationError("No input specified. Provide file paths or pipe input to stdin.")
        }
      }

      let files = try options.resolvedPaths()

      if files.isEmpty {
        throw ValidationError("No Markdown files found to process")
      }

      if files.count == 1 {
        return .singleFile(files[0])
      } else {
        return .multipleFiles(files)
      }
    }

    // MARK: - Validation

    func validateFlags() throws {
      if output != nil && inPlace {
        throw ValidationError("Cannot use both --output and --in-place")
      }
    }

    // MARK: - Processing Methods

    func processStdin(options conversionOptions: RTFOptions) async throws {
      var stdinContent = ""
      while let line = readLine(strippingNewline: false) {
        stdinContent += line
      }

      guard !stdinContent.isEmpty else {
        throw ValidationError("No input received from stdin")
      }

      let doc = try MarkdownDocument(content: stdinContent)
      let rtfData = try await doc.toRTF(options: conversionOptions)

      if let outputPath = output {
        try outputPath.write(rtfData)
      } else {
        FileHandle.standardOutput.write(rtfData)
      }
    }

    func processSingleFile(_ file: Path, options conversionOptions: RTFOptions) async throws {
      let content: String = try file.read()
      let doc = try MarkdownDocument(content: content)
      let rtfData = try await doc.toRTF(options: conversionOptions)

      if let outputPath = output {
        let finalPath = resolveOutputPath(outputPath, for: file)
        if !finalPath.parent().exists {
          try finalPath.parent().mkpath()
        }
        try finalPath.write(rtfData)
      } else if inPlace {
        let rtfPath = file.parent() + "\(file.lastComponentWithoutExtension).rtf"
        try rtfPath.write(rtfData)
      } else {
        FileHandle.standardOutput.write(rtfData)
      }
    }

    func processMultipleFiles(_ files: [Path], options conversionOptions: RTFOptions) async throws {
      if output == nil && !inPlace {
        throw ValidationError(
          "Multiple input files require --output <directory> or --in-place"
        )
      }

      if let outputPath = output {
        if outputPath.exists && !outputPath.isDirectory {
          throw ValidationError(
            "Batch conversion requires output directory, not file: \(outputPath)"
          )
        }
        if !outputPath.exists {
          try outputPath.mkpath()
        }
      }

      var successCount = 0
      var errorCount = 0

      for file in files {
        do {
          let content: String = try file.read()
          let doc = try MarkdownDocument(content: content)
          let rtfData = try await doc.toRTF(options: conversionOptions)

          let finalPath: Path
          if inPlace {
            finalPath = file.parent() + "\(file.lastComponentWithoutExtension).rtf"
          } else if let outputDir = output {
            finalPath = outputDir + "\(file.lastComponentWithoutExtension).rtf"
          } else {
            fatalError("Unreachable: validation should have caught this")
          }

          if !finalPath.parent().exists {
            try finalPath.parent().mkpath()
          }

          try finalPath.write(rtfData)

          FileHandle.standardError.write(
            "✓ Converted: \(file) → \(finalPath)\n".data(using: .utf8) ?? Data()
          )
          successCount += 1
        } catch {
          FileHandle.standardError.write(
            "✗ Error converting \(file): \(error.localizedDescription)\n".data(using: .utf8) ?? Data()
          )
          errorCount += 1
        }
      }

      FileHandle.standardError.write(
        "\nConversion complete:\n".data(using: .utf8) ?? Data()
      )
      FileHandle.standardError.write(
        "  Success: \(successCount)\n".data(using: .utf8) ?? Data()
      )
      if errorCount > 0 {
        FileHandle.standardError.write(
          "  Errors: \(errorCount)\n".data(using: .utf8) ?? Data()
        )
        throw ExitCode.failure
      }
    }

    // MARK: - Helper Methods

    func resolveOutputPath(_ outputPath: Path, for inputFile: Path) -> Path {
      if outputPath.isDirectory {
        return outputPath + "\(inputFile.lastComponentWithoutExtension).rtf"
      }

      if outputPath.string.hasSuffix("/") {
        let dirPath = Path(String(outputPath.string.dropLast()))
        return dirPath + "\(inputFile.lastComponentWithoutExtension).rtf"
      }

      return outputPath
    }
  }
}
