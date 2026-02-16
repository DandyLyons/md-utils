//
//  FromRTF.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.ConvertCommands {
  /// Convert RTF to Markdown
  struct FromRTF: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "from-rtf",
      abstract: "Convert RTF files to Markdown",
      discussion: """
        Converts RTF (Rich Text Format) files to Markdown by detecting
        headings, bold, italic, code, links, and lists from text attributes.

        EXAMPLES:
          # Single file to stdout
          md-utils convert from-rtf document.rtf

          # Single file to specific file
          md-utils convert from-rtf document.rtf -o output.md

          # Single file to directory
          md-utils convert from-rtf src/document.rtf -o output/

          # Batch conversion
          md-utils convert from-rtf docs/ -o output/

          # In-place conversion (.rtf → .md)
          md-utils convert from-rtf docs/ --in-place

          # From stdin
          cat document.rtf | md-utils convert from-rtf -o output.md

          # Disable detection heuristics
          md-utils convert from-rtf file.rtf --no-detect-headings
          md-utils convert from-rtf file.rtf --no-detect-lists
          md-utils convert from-rtf file.rtf --no-detect-code-blocks

        By default:
        - Single file outputs to stdout
        - Detects headings from font size and weight
        - Detects lists from bullet/number prefixes
        - Detects code blocks from monospace fonts
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: [.short, .long],
      help: """
        Output file or directory. For single file: writes to this file or \
        dir/basename.md. For multiple files: must be a directory. \
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
        Convert .rtf files to .md in their original locations. \
        Cannot be used with --output.
        """
    )
    var inPlace: Bool = false

    @Flag(
      name: .long,
      inversion: .prefixedNo,
      help: "Detect headings from font size and weight (use --no-detect-headings to disable)"
    )
    var detectHeadings: Bool = true

    @Flag(
      name: .long,
      inversion: .prefixedNo,
      help: "Detect lists from bullet/number prefixes (use --no-detect-lists to disable)"
    )
    var detectLists: Bool = true

    @Flag(
      name: .long,
      inversion: .prefixedNo,
      help: "Detect code blocks from monospace fonts (use --no-detect-code-blocks to disable)"
    )
    var detectCodeBlocks: Bool = true

    mutating func run() async throws {
      try validateFlags()
      let inputMode = try determineInputMode()

      let generatorOptions = RTFGeneratorOptions(
        detectHeadings: detectHeadings,
        detectLists: detectLists,
        detectCodeBlocks: detectCodeBlocks
      )

      switch inputMode {
      case .stdin:
        try await processStdin(options: generatorOptions)
      case .singleFile(let file):
        try await processSingleFile(file, options: generatorOptions)
      case .multipleFiles(let files):
        try await processMultipleFiles(files, options: generatorOptions)
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

      let files = try options.resolvedPaths(defaultExtensions: "rtf")

      if files.isEmpty {
        throw ValidationError("No RTF files found to process")
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

    func processStdin(options generatorOptions: RTFGeneratorOptions) async throws {
      let stdinData = FileHandle.standardInput.readDataToEndOfFile()

      guard !stdinData.isEmpty else {
        throw ValidationError("No input received from stdin")
      }

      let markdown = try await MarkdownDocument.fromRTF(data: stdinData, options: generatorOptions)

      if let outputPath = output {
        try outputPath.write(markdown)
      } else {
        print(markdown, terminator: "")
      }
    }

    func processSingleFile(_ file: Path, options generatorOptions: RTFGeneratorOptions) async throws {
      let data: Data = try file.read()
      let markdown = try await MarkdownDocument.fromRTF(data: data, options: generatorOptions)

      if let outputPath = output {
        let finalPath = resolveOutputPath(outputPath, for: file)
        if !finalPath.parent().exists {
          try finalPath.parent().mkpath()
        }
        try finalPath.write(markdown)
      } else if inPlace {
        let mdPath = file.parent() + "\(file.lastComponentWithoutExtension).md"
        try mdPath.write(markdown)
      } else {
        print(markdown, terminator: "")
      }
    }

    func processMultipleFiles(_ files: [Path], options generatorOptions: RTFGeneratorOptions) async throws {
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
          let data: Data = try file.read()
          let markdown = try await MarkdownDocument.fromRTF(data: data, options: generatorOptions)

          let finalPath: Path
          if inPlace {
            finalPath = file.parent() + "\(file.lastComponentWithoutExtension).md"
          } else if let outputDir = output {
            finalPath = outputDir + "\(file.lastComponentWithoutExtension).md"
          } else {
            fatalError("Unreachable: validation should have caught this")
          }

          if !finalPath.parent().exists {
            try finalPath.parent().mkpath()
          }

          try finalPath.write(markdown)

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
        return outputPath + "\(inputFile.lastComponentWithoutExtension).md"
      }

      if outputPath.string.hasSuffix("/") {
        let dirPath = Path(String(outputPath.string.dropLast()))
        return dirPath + "\(inputFile.lastComponentWithoutExtension).md"
      }

      return outputPath
    }
  }
}
