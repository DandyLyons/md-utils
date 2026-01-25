//
//  Body.swift
//  md-utils
//
//  Extract the body content (without frontmatter) from Markdown files
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry {
  struct Body: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "body",
      abstract: "Extract the body content without frontmatter",
      discussion: """
        Extract the body content from Markdown files, excluding YAML frontmatter.

        Output can be in Markdown format (preserves formatting) or plain text
        (strips all Markdown formatting).

        EXAMPLES:

        Extract body as Markdown (default):
          md-utils body README.md
          md-utils body README.md --format markdown

        Extract body as plain text:
          md-utils body README.md --format plain-text

        Process multiple files:
          md-utils body docs/*.md
          md-utils body docs/

        From stdin:
          cat README.md | md-utils body
          cat README.md | md-utils body --format plain-text
        """,
      aliases: ["b"]
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: [.short, .long],
      help: "Output format: 'markdown' (default) or 'plain-text'"
    )
    var format: BodyFormat = .markdown

    mutating func run() async throws {
      // Determine input mode
      let inputMode = try determineInputMode()

      // Process based on input mode
      switch inputMode {
      case .stdin:
        try await processStdin()

      case .singleFile(let file):
        try await processSingleFile(file)

      case .multipleFiles(let files):
        try await processMultipleFiles(files)
      }
    }

    // MARK: - Input Mode Detection

    enum InputMode {
      case stdin
      case singleFile(Path)
      case multipleFiles([Path])
    }

    func determineInputMode() throws -> InputMode {
      // Check for stdin (when no paths provided and stdin has data)
      if options.paths.isEmpty {
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

    // MARK: - Processing Methods

    func processStdin() async throws {
      // Read from stdin
      var stdinContent = ""
      while let line = readLine(strippingNewline: false) {
        stdinContent += line
      }

      guard !stdinContent.isEmpty else {
        throw ValidationError("No input received from stdin")
      }

      // Extract and print body
      let doc = try MarkdownDocument(content: stdinContent)
      let output = try await extractBody(from: doc)
      print(output, terminator: "")
    }

    func processSingleFile(_ file: Path) async throws {
      let content: String = try file.read()
      let doc = try MarkdownDocument(content: content)
      let output = try await extractBody(from: doc)
      print(output, terminator: "")
    }

    func processMultipleFiles(_ files: [Path]) async throws {
      for file in files {
        let content: String = try file.read()
        let doc = try MarkdownDocument(content: content)
        let output = try await extractBody(from: doc)

        // Print separator with filename for multiple files
        print("--- \(file) ---")
        print(output, terminator: "")
        print()  // Extra newline between files
      }
    }

    // MARK: - Helper Methods

    /// Extract the body content from a MarkdownDocument based on the selected format.
    func extractBody(from doc: MarkdownDocument) async throws -> String {
      switch format {
      case .markdown:
        return doc.body

      case .plainText:
        // Use toPlainText which excludes frontmatter by default
        let plainTextOptions = PlainTextOptions(
          includeFrontmatter: false,
          blockSeparator: 2,
          preserveLineBreaks: true,
          extractImageAltText: true,
          indentLists: true,
          indentSpaces: 2,
          preserveCodeBlocks: true
        )
        return try await doc.toPlainText(options: plainTextOptions)
      }
    }
  }
}

// MARK: - Body Format Enum

enum BodyFormat: String, CaseIterable, ExpressibleByArgument {
  case markdown
  case plainText = "plain-text"

  var defaultValueDescription: String {
    switch self {
    case .markdown: return "markdown (default)"
    case .plainText: return "plain-text"
    }
  }
}
