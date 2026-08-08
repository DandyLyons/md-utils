import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit

/// Shared generated-help content for commands that support wrapped frontmatter.
enum NonMarkdownFrontMatterHelp {
  /// Appends the non-Markdown frontmatter contract to a command discussion.
  ///
  /// - Parameter discussion: The command-specific discussion text.
  /// - Returns: The discussion followed by the shared wrapped-frontmatter section.
  static func appending(to discussion: String) -> String {
    discussion + "\n\n" + section
  }

  /// The exact syntax and selection contract shown on relevant help pages.
  private static let section = """
    FRONTMATTER ON NON-MD FILES
      A supported non-Markdown file uses the wrapper mapped from its extension.
      A complete wrapped frontmatter block must contain, on separate complete LF
      lines: the mapped opening wrapper, an opening ---, a YAML mapping, a closing
      ---, and the matching mapped closing wrapper. For example:

        /*
        ---
        title: Example
        ---
        */

      The block may occur anywhere, though placement near the beginning is
      recommended. Incomplete blocks are treated as absent; multiple complete
      blocks are invalid. Plain .txt uses ordinary Markdown-style frontmatter and
      only participates with --include-non-md.

      A sole explicit mapped file is selected automatically. Multi-file and
      directory operations require --include-non-md for mapped files.
    """
}

/// Describes how a selected file represents frontmatter.
///
/// Markdown and opted-in plain-text files use ordinary leading `---` markers.
/// Other supported text files use the shipped wrapper mapped from their extension.
enum FrontMatterFileSyntax: Equatable {
  /// Ordinary Markdown-style frontmatter.
  case markdown

  /// YAML frontmatter enclosed by a host-language wrapper.
  case wrapped(FrontMatterSyntax)

  /// Resolves the frontmatter representation for a selected file.
  ///
  /// - Parameters:
  ///   - path: The file whose extension determines the representation.
  ///   - includeNonMarkdown: Whether `.txt` is opted into Markdown-style parsing.
  /// - Returns: The resolved representation, or `nil` when `.txt` is not opted in
  ///   or the extension has no shipped mapping.
  static func resolve(for path: Path, includeNonMarkdown: Bool) -> FrontMatterFileSyntax? {
    let fileExtension = path.extension?.lowercased() ?? ""
    if fileExtension == "md" || fileExtension == "markdown" {
      return .markdown
    }
    if fileExtension == "txt" {
      return includeNonMarkdown ? .markdown : nil
    }
    return FrontMatterSyntax.shippedSyntax(forExtension: fileExtension).map(Self.wrapped)
  }
}

/// A stable, user-facing failure produced by frontmatter command support.
struct FrontMatterCommandError: LocalizedError {
  /// The diagnostic displayed by the command.
  let message: String

  /// The localized diagnostic displayed by CLI error handling.
  var errorDescription: String? { message }
}

/// Frontmatter parsed from one exact source snapshot.
///
/// Wrapped block ranges remain valid only while `source` is unchanged.
struct ParsedFrontMatterFile {
  /// The complete source snapshot used to derive all ranges.
  let source: String

  /// The frontmatter representation selected for the file.
  let syntax: FrontMatterFileSyntax

  /// The first frontmatter block converted to the existing document representation.
  let document: MarkdownDocument

  /// The first complete wrapped block and its snapshot-relative range.
  let wrappedBlock: WrappedFrontMatterBlock?

  /// The 1-based opening lines of complete wrapped blocks after the first.
  let additionalOpeningLines: [Int]

  /// Parses frontmatter from a source snapshot using its selected representation.
  ///
  /// Later wrapped blocks are located but their YAML is never converted or merged.
  ///
  /// - Parameters:
  ///   - source: The complete LF text snapshot.
  ///   - syntax: The representation selected for the file.
  /// - Returns: Parsed frontmatter tied to `source`.
  /// - Throws: A YAML conversion error when the first complete block is invalid.
  static func parse(source: String, syntax: FrontMatterFileSyntax) throws -> ParsedFrontMatterFile {
    switch syntax {
    case .markdown:
      return ParsedFrontMatterFile(
        source: source,
        syntax: syntax,
        document: try MarkdownDocument(content: source),
        wrappedBlock: nil,
        additionalOpeningLines: []
      )
    case .wrapped(let wrapper):
      let scan = WrappedFrontMatterParser(syntax: wrapper).parse(source)
      let mapping = try YAMLConversion.parse(scan.firstBlock?.rawYAML ?? "")
      return ParsedFrontMatterFile(
        source: source,
        syntax: syntax,
        document: MarkdownDocument(frontMatter: mapping, body: source),
        wrappedBlock: scan.firstBlock,
        additionalOpeningLines: scan.additionalOpeningLines
      )
    }
  }

  /// Renders an updated document into the original source snapshot.
  ///
  /// Markdown uses the existing document renderer. Wrapped frontmatter replaces
  /// only the first block range, or is inserted at line 1 followed by one blank line.
  ///
  /// - Parameter updatedDocument: The document containing the updated mapping.
  /// - Returns: Complete updated file text.
  /// - Throws: A YAML serialization error.
  func rendering(_ updatedDocument: MarkdownDocument) throws -> String {
    switch syntax {
    case .markdown:
      return try updatedDocument.render()
    case .wrapped(let wrapper):
      let yaml = try YAMLConversion.serialize(updatedDocument.frontMatter)
      let renderedBlock = "\(wrapper.openingWrapper)\n---\n\(yaml)---\n\(wrapper.closingWrapper)"
      guard let wrappedBlock else {
        return "\(renderedBlock)\n\n\(source)"
      }
      var result = source
      result.replaceSubrange(wrappedBlock.range, with: renderedBlock)
      return result
    }
  }
}

/// Loads frontmatter for read-only CLI commands using shipped syntax mappings.
enum FrontMatterCLIReader {
  /// Reads and parses a file, rejecting unsupported syntax and repeated blocks.
  ///
  /// - Parameters:
  ///   - path: The selected file to read.
  ///   - includeNonMarkdown: Whether `.txt` is opted into Markdown-style parsing.
  /// - Returns: The first frontmatter block in the existing document representation.
  /// - Throws: A filesystem, syntax-mapping, multiplicity, or YAML conversion error.
  static func document(at path: Path, includeNonMarkdown: Bool) throws -> MarkdownDocument {
    try FrontMatterCLIMutator.parsedFile(
      at: path,
      includeNonMarkdown: includeNonMarkdown
    ).document
  }
}

/// Shared snapshot-safe loading, creation authorization, and writing for CLI mutations.
enum FrontMatterCLIMutator {
  /// Loads one file from a single source snapshot and rejects repeated wrapped blocks.
  static func parsedFile(
    at path: Path,
    includeNonMarkdown: Bool
  ) throws -> ParsedFrontMatterFile {
    let source: String = try path.read()
    guard let syntax = FrontMatterFileSyntax.resolve(
      for: path,
      includeNonMarkdown: includeNonMarkdown
    ) else {
      throw FrontMatterCommandError(
        message: "no frontmatter syntax mapping for extension \"\(path.extension ?? "")\""
      )
    }
    let parsed = try ParsedFrontMatterFile.parse(source: source, syntax: syntax)
    if let secondLine = parsed.additionalOpeningLines.first {
      throw FrontMatterCommandError(
        message: "multiple frontmatter blocks; additional block opens at line \(secondLine)"
      )
    }
    return parsed
  }

  /// Requires explicit authorization before a mutation creates a wrapped block.
  ///
  /// Markdown creation remains silent. A sole explicit mapped file may prompt;
  /// batch operations require `--create-frontmatter` and never prompt.
  static func authorizeCreationIfNeeded(
    for parsed: ParsedFrontMatterFile,
    options: GlobalOptions,
    createFrontmatter: Bool
  ) throws {
    guard case .wrapped(let wrapper) = parsed.syntax,
      parsed.wrappedBlock == nil,
      createFrontmatter == false
    else {
      return
    }

    let isSingleExplicitFile = options.paths.count == 1 && options.paths[0].isFile
    guard isSingleExplicitFile else {
      throw FrontMatterCommandError(
        message: "missing non-Markdown frontmatter requires --create-frontmatter"
      )
    }

    CLIStyle.writeStderr(
      "Create wrapped frontmatter using \(wrapper.name) (\(wrapper.openingWrapper) … \(wrapper.closingWrapper))? [y/N]"
    )
    let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard response == "y" || response == "yes" else {
      throw FrontMatterCommandError(message: "frontmatter creation declined")
    }
  }

  /// Renders against the parsed snapshot and atomically writes after a revision check.
  static func write(
    _ document: MarkdownDocument,
    parsed: ParsedFrontMatterFile,
    to path: Path
  ) throws {
    let updated = try parsed.rendering(document)
    try FrontMatterFileWriter.write(updated, to: path, expectedSource: parsed.source)
  }
}

extension GlobalOptions {
  /// Resolves paths according to frontmatter-specific non-Markdown selection rules.
  ///
  /// A single explicit mapped file is accepted without opt-in. Explicit file lists
  /// and directory traversal remain Markdown-only unless `includeNonMarkdown` is
  /// true. Explicit ignored files emit an opt-in hint; directory-discovered files
  /// are ignored silently.
  ///
  /// - Parameter includeNonMarkdown: Whether mapped non-Markdown files and `.txt`
  ///   participate in batch selection.
  /// - Returns: Selected files after extension, hidden-file, exclusion, recursion,
  ///   and sorting rules are applied.
  /// - Throws: A validation error for missing paths or explicitly selected unmapped files.
  func resolvedFrontMatterPaths(includeNonMarkdown: Bool) throws -> [Path] {
    let requestedPaths = paths.isEmpty ? [Path.current] : paths
    let explicitSingleFile = requestedPaths.count == 1 && requestedPaths[0].exists && requestedPaths[0].isFile
    let explicitlyNarrowedExtensions = extensions != "md,markdown"
    let requestedExtensions = Set(
      extensions.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { $0.isEmpty == false }
    )

    var selected: [Path] = []
    for path in requestedPaths {
      guard path.exists else {
        throw ValidationError("Path does not exist: \(path)")
      }

      if path.isDirectory {
        selected.append(contentsOf: try frontMatterFiles(
          in: path,
          includeNonMarkdown: includeNonMarkdown,
          requestedExtensions: requestedExtensions,
          explicitlyNarrowedExtensions: explicitlyNarrowedExtensions
        ))
        continue
      }

      let fileExtension = path.extension?.lowercased() ?? ""
      if explicitlyNarrowedExtensions && requestedExtensions.contains(fileExtension) == false {
        continue
      }

      if fileExtension == "md" || fileExtension == "markdown" {
        selected.append(path)
      } else if fileExtension == "txt" {
        if includeNonMarkdown {
          selected.append(path)
        } else {
          writeIgnoredHint(for: path)
        }
      } else if FrontMatterSyntax.shippedSyntax(forExtension: fileExtension) != nil {
        if includeNonMarkdown || explicitSingleFile {
          selected.append(path)
        } else {
          writeIgnoredHint(for: path)
        }
      } else if explicitSingleFile || includeNonMarkdown {
        throw ValidationError("No frontmatter syntax mapping for extension \"\(fileExtension)\"")
      } else {
        writeIgnoredHint(for: path)
      }
    }

    let excluded = exclude.map { $0.absolute().string }
    selected = selected.filter { isExcluded($0, excludePatterns: excluded) == false }

    if noSort == false {
      selected.sort { $0.string < $1.string }
    }
    return selected
  }

  /// Recursively discovers files eligible for a directory-based operation.
  private func frontMatterFiles(
    in directory: Path,
    includeNonMarkdown: Bool,
    requestedExtensions: Set<String>,
    explicitlyNarrowedExtensions: Bool
  ) throws -> [Path] {
    var result: [Path] = []
    for child in try directory.children() {
      if includeHidden == false && child.lastComponent.hasPrefix(".") { continue }
      if child.isDirectory {
        if recursive {
          result.append(contentsOf: try frontMatterFiles(
            in: child,
            includeNonMarkdown: includeNonMarkdown,
            requestedExtensions: requestedExtensions,
            explicitlyNarrowedExtensions: explicitlyNarrowedExtensions
          ))
        }
        continue
      }

      let fileExtension = child.extension?.lowercased() ?? ""
      if explicitlyNarrowedExtensions && requestedExtensions.contains(fileExtension) == false {
        continue
      }
      if fileExtension == "md" || fileExtension == "markdown" {
        result.append(child)
      } else if includeNonMarkdown && fileExtension == "txt" {
        result.append(child)
      } else if includeNonMarkdown && FrontMatterSyntax.shippedSyntax(forExtension: fileExtension) != nil {
        result.append(child)
      }
    }
    return result
  }

  /// Reports why an explicitly listed non-Markdown file was not selected.
  private func writeIgnoredHint(for path: Path) {
    CLIStyle.writeStderr(
      "ignored non-Markdown file \(path.string); use --include-non-md to process mapped non-Markdown files"
    )
  }
}
