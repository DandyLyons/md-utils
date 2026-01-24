//
//  Search.swift
//  md-utils
//

import ArgumentParser
import Foundation
import JMESPath
import MarkdownUtilities
import PathKit
import Yams

extension CLIEntry.FrontMatterCommands {
  /// Search for files matching a JMESPath query
  struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "search",
      abstract: "Search for files matching a JMESPath query",
      discussion: """
        Search for files whose frontmatter matches a JMESPath expression.

        The query is evaluated against each file's YAML frontmatter.
        Files where the expression evaluates to true (or truthy) are included.

        Directories are searched recursively.

        EXAMPLES:
          # Find all draft files
          md-utils fm search 'draft == `true`' .

          # Find files with specific tag
          md-utils fm search 'contains(tags, `"swift"`)' ./posts

          # Complex query with multiple conditions
          md-utils fm search 'draft == `false` && author == `"John"`' .

        JMESPATH SYNTAX:
          Use backticks for ALL literal values:
          - Booleans: `true`, `false`
          - Strings: `"text"`
          - Numbers: `42`, `3.14`
          - Null: `null`
          - Comparisons: ==, !=, <, <=, >, >=
          - Functions: contains(), length(), starts_with(), etc.
          - Logical: &&, ||, !
          - See https://jmespath.org for full syntax

        SHELL QUOTING:
          Always wrap your entire query in single quotes to prevent shell interpretation:

          ✓ Correct:   md-utils fm search 'draft == `true`' .
          ✓ Correct:   md-utils fm search 'contains(tags, `"swift"`)' .
          ✓ Correct:   md-utils fm search 'draft == `false` && author == `"Jane"`' .

          ✗ Wrong:     md-utils fm search "draft == `true`" .
                       (backticks will be interpreted by shell as command substitution)
          ✗ Wrong:     md-utils fm search 'draft == true' .
                       (missing backticks - JMESPath treats "true" as a field name!)
          ✗ Wrong:     md-utils fm search 'contains(tags, "swift")' .
                       (missing backticks - "swift" is a field reference, not a string!)

        PIPING TO OTHER COMMANDS:
          The search command outputs file paths (one per line), making it perfect
          for piping into other commands:

          # Bulk update: mark all drafts as published
          md-utils fm search 'draft == `true`' ./posts | xargs md-utils fm set --key draft --value false

          # Chain operations: publish posts and add date
          md-utils fm search 'ready == `true`' . | while read -r file; do
            md-utils fm set "$file" --key published --value true
            md-utils fm set "$file" --key date --value "$(date +%Y-%m-%d)"
          done

          # Remove a key from matching files
          md-utils fm search 'deprecated == `true`' . | xargs md-utils fm remove --key temporary
        """
    )

    @Argument(help: "JMESPath expression to filter files")
    var query: String

    @Argument(
      help: "Path(s) to the file(s)/directory(ies) to search",
      completion: .file()
    )
    var pathStrings: [String] = []

    @Option(name: [.short, .long], help: "Output format")
    var format: OutputFormat = .raw

    @Option(
      name: [.short, .long],
      help: "File extensions to process (comma-separated, no spaces)"
    )
    var extensions: String = "md,markdown"

    mutating func run() async throws {
      // Convert path strings to Path objects
      let paths = pathStrings.isEmpty ? [Path.current] : pathStrings.map { Path($0) }
      // Compile the JMESPath expression once
      let expression: JMESExpression
      do {
        expression = try JMESExpression.compile(query)
      } catch {
        // Extract the actual error message from JMESPathError
        let errorDescription = String(describing: error)
        let errorMessage: String

        // Try to extract the message from patterns like: compileTime("message") or runtime("message")
        let patterns = [
          #"compileTime\("([^"]+)"\)"#,
          #"runtime\("([^"]+)"\)"#,
        ]

        var extractedMessage: String?
        for pattern in patterns {
          if let match = errorDescription.range(of: pattern, options: .regularExpression),
            let captureRange = errorDescription.range(
              of: #""([^"]+)""#, options: .regularExpression, range: match)
          {
            extractedMessage = String(errorDescription[captureRange].dropFirst().dropLast())
            break
          }
        }

        errorMessage = extractedMessage ?? error.localizedDescription

        throw ValidationError("""
          Invalid JMESPath expression: "\(query)"
          \(errorMessage)

          See https://jmespath.org for syntax reference
          """)
      }

      let processedPaths = try expandPaths(paths: paths)

      // Process files in batches of 500
      let matchingFiles = processBatches(
        processedPaths,
        batchSize: 500,
        using: expression
      )

      // Output results based on format
      if matchingFiles.isEmpty {
        // Print helpful message to stderr (doesn't interfere with piping stdout)
        fputs("No files matched the query: \"\(query)\"\n", stderr)
        fputs("Searched \(processedPaths.count) file(s)\n", stderr)
      } else {
        switch format {
        case .json:
          try printAny(matchingFiles, format: .json)
        case .yaml:
          try printAny(matchingFiles, format: .yaml)
        case .raw:
          // Plain text: one file path per line
          print(matchingFiles.joined(separator: "\n"))
        case .plist:
          // For search results (file paths), use plist format
          try printAny(matchingFiles, format: .plist)
        }
      }
    }

    /// Expand paths with recursive directory traversal and extension filtering
    /// Search command is always recursive
    private func expandPaths(paths: [Path]) throws -> [Path] {
      var allPaths: [Path] = []

      for path in paths {
        if path.isDirectory {
          // Always search recursively
          let recursiveChildren = try path.recursiveChildren()
          allPaths.append(contentsOf: recursiveChildren)
        } else {
          allPaths.append(path)
        }
      }

      // Filter by extensions
      let exts: [String] = self.extensions
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }

      if !exts.isEmpty {
        allPaths = allPaths.filter { path in
          guard let fileExt = path.extension?.lowercased() else { return false }
          return exts.contains(fileExt)
        }
      }

      return allPaths
    }

    /// Process file paths in batches to avoid memory pressure and provide progress feedback
    private func processBatches(
      _ paths: [Path],
      batchSize: Int = 500,
      using expression: JMESExpression
    ) -> [String] {
      var allMatches: [String] = []
      let totalBatches = (paths.count + batchSize - 1) / batchSize

      for (batchIndex, batch) in paths.chunked(into: batchSize).enumerated() {
        let batchNumber = batchIndex + 1

        // Show progress to stderr (only for multi-batch operations)
        if paths.count > batchSize {
          fputs("Processing batch \(batchNumber)/\(totalBatches)...\n", stderr)
        }

        let batchMatches = processBatch(batch, using: expression)
        allMatches.append(contentsOf: batchMatches)
      }

      return allMatches
    }

    /// Process a single batch of files
    private func processBatch(_ paths: [Path], using expression: JMESExpression) -> [String] {
      var matches: [String] = []
      let constructor = Yams.Constructor.default

      for path in paths {
        // Parse the file
        let content: String
        let doc: MarkdownDocument
        do {
          content = try path.read(.utf8)
          doc = try MarkdownDocument(content: content)
        } catch {
          // Silently skip files that can't be parsed
          continue
        }

        // Convert Yams.Node.Mapping to Swift dictionary for JMESPath
        // Validate that all keys can be converted to strings to avoid Yams crashes
        if !isValidMapping(doc.frontMatter) {
          // Skip files with non-string keys
          continue
        }

        let frontMatterDict: Any = constructor.any(from: .mapping(doc.frontMatter))

        // Evaluate the JMESPath expression
        do {
          let result = try expression.search(object: frontMatterDict)

          if isTruthy(result) {
            matches.append(path.absolute().string)
          }
        } catch {
          // Silently skip files where query evaluation fails
          continue
        }
      }

      return matches
    }

    /// Validates that a YAML mapping has only string keys (recursively)
    /// This prevents crashes in Yams.Constructor.any() which force-unwraps string keys
    private func isValidMapping(_ mapping: Yams.Node.Mapping) -> Bool {
      for (key, value) in mapping {
        // Check if key can be constructed as a string
        guard case .scalar = key else {
          return false
        }
        guard String.construct(from: key) != nil else {
          return false
        }

        // Recursively validate nested mappings
        if case .mapping(let nestedMapping) = value {
          if !isValidMapping(nestedMapping) {
            return false
          }
        }

        // Recursively validate sequences containing mappings
        if case .sequence(let sequence) = value {
          // Iterate using index since .nodes is private
          for i in 0..<sequence.count {
            if case .mapping(let nestedMapping) = sequence[i] {
              if !isValidMapping(nestedMapping) {
                return false
              }
            }
          }
        }
      }
      return true
    }

    /// Determines if a value is "truthy" for the purposes of filtering
    /// - JMESPath returns various types; we treat non-false, non-nil, non-empty as truthy
    private func isTruthy(_ value: Any?) -> Bool {
      guard let value = value else {
        return false
      }

      // Handle various types
      if let bool = value as? Bool {
        return bool
      }
      if let string = value as? String {
        return !string.isEmpty
      }
      if let array = value as? [Any] {
        return !array.isEmpty
      }
      if let dict = value as? [String: Any] {
        return !dict.isEmpty
      }

      // For other types (numbers, objects), consider them truthy if non-nil
      return true
    }
  }
}

// MARK: - Array Utilities

private extension Array {
  /// Split array into chunks of specified size
  func chunked(into size: Int) -> [[Element]] {
    guard size > 0 else { return [self] }
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
