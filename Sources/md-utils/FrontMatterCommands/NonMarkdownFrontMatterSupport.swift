import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit

/// Explicit-file override for fixed hash-comment frontmatter.
struct LineCommentFrontMatterOptions: ParsableArguments {
  @Flag(
    name: .long,
    help: "Treat explicitly supplied regular files as fixed # line-comment frontmatter."
  )
  var lineCommentFrontmatter = false
}

/// Shared generated-help content for commands that support non-Markdown frontmatter.
enum NonMarkdownFrontMatterHelp {
  /// Appends the non-Markdown frontmatter contract to a command discussion.
  ///
  /// - Parameter discussion: The command-specific discussion text.
  /// - Returns: The discussion followed by the shared wrapped-frontmatter section.
  static func appending(to discussion: String) -> String {
    discussion + "\n\n" + section
  }

  /// Appends the non-Markdown frontmatter contract used by `fm dump`.
  ///
  /// Dump is read-only, so it discovers every shipped syntax without requiring
  /// the opt-in used by batch mutation commands.
  static func appendingForDump(to discussion: String) -> String {
    discussion + "\n\n" + dumpSection
  }

  /// The syntax contract shared by frontmatter command help pages.
  private static let syntaxContract = """
    FRONTMATTER ON NON-MD FILES
      A supported non-Markdown file uses the representation mapped from its
      complete basename or extension. Exact basename mappings take precedence.
      A complete wrapped frontmatter block must contain, on separate complete LF
      lines: the mapped opening wrapper, matching YAML --- or TOML +++ delimiter
      lines, a mapping, and the matching mapped closing wrapper. For example:

        /*
        ---
        title: Example
        ---
        */

        /*
        +++
        title = "Example"
        +++
        */

      The block may occur anywhere, though placement near the beginning is
      recommended. Incomplete blocks are treated as absent; multiple complete
      blocks are invalid. Plain .txt uses ordinary Markdown-style frontmatter.

      Hash-comment mappings use an exact # --- or # +++ delimiter at the legal
      file prologue. Every nonempty metadata line begins with exactly # ; bare #
      and physically empty lines represent empty logical lines. A block may begin
      at line 1, immediately after a shebang, or after one empty post-shebang line.
      These blocks follow the package's existing LF-only frontmatter policy.
    """

  /// The exact opt-in selection contract shown on relevant help pages.
  private static let section = syntaxContract + """


      Plain .txt only participates with --include-non-md.

      A sole explicit mapped file is selected automatically. Multi-file and
      directory operations require --include-non-md for mapped files.

      --line-comment-frontmatter opts explicitly supplied regular files into the
      hash-comment representation. It cannot be used for implicit input,
      directories, or traversal, and never overrides Markdown or wrapped mappings.
    """

  /// The exact syntax and automatic-selection contract shown by `fm dump`.
  private static let dumpSection = syntaxContract + """


      Dump automatically selects Markdown, plain-text, and mapped non-Markdown
      files in explicit file lists and directory operations.
    """
}

/// Describes how a selected file represents frontmatter.
///
/// Markdown and opted-in plain-text files use ordinary leading format markers.
/// Other supported text files use the shipped wrapper mapped from their extension.
enum FrontMatterFileSyntax: Equatable {
  /// Ordinary Markdown-style frontmatter.
  case markdown

  /// YAML or TOML frontmatter enclosed by a host-language wrapper.
  case wrapped(FrontMatterSyntax)

  /// YAML or TOML represented by one fixed hash comment per physical line.
  case lineComment

  /// Resolves the frontmatter representation for a selected file.
  ///
  /// - Parameters:
  ///   - path: The file whose extension determines the representation.
  ///   - includeNonMarkdown: Whether `.txt` is opted into Markdown-style parsing.
  /// - Returns: The resolved representation, or `nil` when `.txt` is not opted in
  ///   or the extension has no shipped mapping.
  static func resolve(
    for path: Path,
    includeNonMarkdown: Bool,
    lineCommentFrontmatter: Bool = false
  ) -> FrontMatterFileSyntax? {
    let fileExtension = path.extension?.lowercased() ?? ""
    if fileExtension == "md" || fileExtension == "markdown" {
      return .markdown
    }
    if let shipped = NonMarkdownFrontMatterSyntax.shippedSyntax(
      forFileName: path.lastComponent,
      fileExtension: fileExtension
    ) {
      switch shipped {
      case .wrapped(let syntax): return .wrapped(syntax)
      case .lineComment: return .lineComment
      }
    }
    if fileExtension == "txt" {
      return includeNonMarkdown ? .markdown : nil
    }
    return lineCommentFrontmatter ? .lineComment : nil
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

  /// The fixed-prefix line-comment block in the parsed snapshot.
  let lineCommentFrontMatter: LineCommentFrontMatter?

  /// Creation placement derived from the line-comment parser's prologue scan.
  let lineCommentPlacement: LineCommentFrontMatterPlacement?

  /// The 1-based opening lines of complete wrapped blocks after the first.
  let additionalOpeningLines: [Int]

  /// Whether the source contains a complete frontmatter block.
  var hasFrontMatterBlock: Bool {
    switch syntax {
    case .markdown:
      return document.frontMatterFormat != nil
    case .wrapped:
      return wrappedBlock != nil
    case .lineComment:
      return lineCommentFrontMatter != nil
    }
  }

  /// Parses frontmatter from a source snapshot using its selected representation.
  ///
  /// Later wrapped blocks are located but their frontmatter is never converted or merged.
  ///
  /// - Parameters:
  ///   - source: The complete LF text snapshot.
  ///   - syntax: The representation selected for the file.
  /// - Returns: Parsed frontmatter tied to `source`.
  /// - Throws: A conversion error when the first complete block is invalid.
  static func parse(source: String, syntax: FrontMatterFileSyntax) throws -> ParsedFrontMatterFile {
    switch syntax {
    case .markdown:
      return ParsedFrontMatterFile(
        source: source,
        syntax: syntax,
        document: try MarkdownDocument(content: source),
        wrappedBlock: nil,
        lineCommentFrontMatter: nil,
        lineCommentPlacement: nil,
        additionalOpeningLines: []
      )
    case .wrapped(let wrapper):
      let scan = WrappedFrontMatterParser(syntax: wrapper).parse(source)
      let format = scan.firstBlock?.format
      let frontMatter = try format.map {
        try FrontMatterConversion.parse(scan.firstBlock?.rawFrontMatter ?? "", format: $0)
      } ?? FrontMatter()
      return ParsedFrontMatterFile(
        source: source,
        syntax: syntax,
        document: MarkdownDocument(
          frontMatter: frontMatter,
          body: source,
          frontMatterFormat: format
        ),
        wrappedBlock: scan.firstBlock,
        lineCommentFrontMatter: nil,
        lineCommentPlacement: nil,
        additionalOpeningLines: scan.additionalOpeningLines
      )
    case .lineComment:
      let scan = LineCommentFrontMatterParser().parse(source)
      if let diagnostic = scan.diagnostic { throw diagnostic }
      let format = scan.frontMatter?.format
      let frontMatter = try format.map {
        try FrontMatterConversion.parse(scan.frontMatter?.rawFrontMatter ?? "", format: $0)
      } ?? FrontMatter()
      return ParsedFrontMatterFile(
        source: source,
        syntax: syntax,
        document: MarkdownDocument(
          frontMatter: frontMatter,
          body: source,
          frontMatterFormat: format
        ),
        wrappedBlock: nil,
        lineCommentFrontMatter: scan.frontMatter,
        lineCommentPlacement: scan.placement,
        additionalOpeningLines: []
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
  /// - Throws: A frontmatter serialization error.
  func rendering(_ updatedDocument: MarkdownDocument) throws -> String {
    switch syntax {
    case .markdown:
      return try updatedDocument.render()
    case .wrapped(let wrapper):
      let format = updatedDocument.frontMatterFormat ?? .yaml
      let serialized = try FrontMatterConversion.serialize(updatedDocument.frontMatter, format: format)
      let renderedBlock = "\(wrapper.openingWrapper)\n\(format.delimiter)\n\(serialized)\(format.delimiter)\n\(wrapper.closingWrapper)"
      guard let wrappedBlock else {
        return "\(renderedBlock)\n\n\(source)"
      }
      var result = source
      result.replaceSubrange(wrappedBlock.range, with: renderedBlock)
      return result
    case .lineComment:
      let format = updatedDocument.frontMatterFormat ?? .yaml
      let lineEnding = lineCommentFrontMatter?.lineEnding
        ?? lineCommentPlacement?.lineEnding
        ?? "\n"
      let renderedBlock = try Self.renderLineCommentBlock(
        updatedDocument.frontMatter,
        format: format,
        lineEnding: lineEnding
      )
      if let lineCommentFrontMatter {
        var result = source
        result.replaceSubrange(lineCommentFrontMatter.range, with: renderedBlock)
        return result
      }
      guard let placement = lineCommentPlacement else { return source }
      var insertion = placement.needsLeadingLineEnding ? lineEnding : ""
      insertion += renderedBlock
      insertion += lineEnding
      if placement.reusesFollowingEmptyLine == false,
        placement.insertionIndex < source.endIndex
      {
        insertion += lineEnding
      }
      var result = source
      result.insert(contentsOf: insertion, at: placement.insertionIndex)
      return result
    }
  }

  private static func renderLineCommentBlock(
    _ frontMatter: FrontMatter,
    format: FrontMatterFormat,
    lineEnding: String
  ) throws -> String {
    var serialized = try FrontMatterConversion.serialize(frontMatter, format: format)
    if serialized.hasSuffix("\n") { serialized.removeLast() }
    if serialized.hasSuffix("\r") { serialized.removeLast() }
    let payloadLines = serialized.split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).map(String.init)
    let physicalPayload = payloadLines.map { $0.isEmpty ? "#" : "# \($0)" }
    return (["# \(format.delimiter)"] + physicalPayload + ["# \(format.delimiter)"])
      .joined(separator: lineEnding)
  }

  /// Removes the complete frontmatter envelope from the original source snapshot.
  ///
  /// Markdown parsing already preserves the exact body after consuming the closing
  /// delimiter and its optional newline. Wrapped blocks consume that same single
  /// trailing newline here so both representations have matching removal semantics.
  func renderingWithoutFrontMatter() -> String {
    switch syntax {
    case .markdown:
      return document.body
    case .wrapped:
      guard let wrappedBlock else { return source }
      let removalEnd = endAfterOneLineEnding(from: wrappedBlock.range.upperBound)
      var result = source
      result.removeSubrange(wrappedBlock.range.lowerBound..<removalEnd)
      return result
    case .lineComment:
      guard let lineCommentFrontMatter else { return source }
      let removalEnd = endAfterOneLineEnding(from: lineCommentFrontMatter.range.upperBound)
      var result = source
      result.removeSubrange(lineCommentFrontMatter.range.lowerBound..<removalEnd)
      return result
    }
  }

  private func endAfterOneLineEnding(from index: String.Index) -> String.Index {
    guard index < source.endIndex else { return index }
    if source[index] == "\r" {
      let afterCarriageReturn = source.index(after: index)
      if afterCarriageReturn < source.endIndex, source[afterCarriageReturn] == "\n" {
        return source.index(after: afterCarriageReturn)
      }
      return afterCarriageReturn
    }
    return source[index] == "\n" ? source.index(after: index) : index
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
  static func document(
    at path: Path,
    includeNonMarkdown: Bool,
    lineCommentFrontmatter: Bool = false
  ) throws -> MarkdownDocument {
    try FrontMatterCLIMutator.parsedFile(
      at: path,
      includeNonMarkdown: includeNonMarkdown,
      lineCommentFrontmatter: lineCommentFrontmatter
    ).document
  }
}

/// Shared snapshot-safe loading, creation authorization, and writing for CLI mutations.
enum FrontMatterCLIMutator {
  /// Loads one file from a single source snapshot and rejects repeated wrapped blocks.
  static func parsedFile(
    at path: Path,
    includeNonMarkdown: Bool,
    lineCommentFrontmatter: Bool = false
  ) throws -> ParsedFrontMatterFile {
    let source = try FrontMatterFileWriter.readSnapshot(from: path)
    guard let syntax = FrontMatterFileSyntax.resolve(
      for: path,
      includeNonMarkdown: includeNonMarkdown,
      lineCommentFrontmatter: lineCommentFrontmatter
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
    guard parsed.hasFrontMatterBlock == false, createFrontmatter == false else { return }
    let prompt: String
    switch parsed.syntax {
    case .markdown:
      return
    case .wrapped(let wrapper):
      prompt = "Create wrapped frontmatter using \(wrapper.name) (\(wrapper.openingWrapper) … \(wrapper.closingWrapper))? [y/N]"
    case .lineComment:
      prompt = "Create line-comment frontmatter using # prefixes? [y/N]"
    }

    let isSingleExplicitFile = options.paths.count == 1 && options.paths[0].isFile
    guard isSingleExplicitFile else {
      throw FrontMatterCommandError(
        message: "missing non-Markdown frontmatter requires --create-frontmatter"
      )
    }

    CLIStyle.writeStderr(prompt)
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

  /// Removes a complete frontmatter block using the parsed source snapshot.
  static func removeFrontMatter(parsed: ParsedFrontMatterFile, from path: Path) throws {
    try FrontMatterFileWriter.write(
      parsed.renderingWithoutFrontMatter(),
      to: path,
      expectedSource: parsed.source
    )
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
  func resolvedFrontMatterPaths(
    includeNonMarkdown: Bool,
    lineCommentFrontmatter: Bool = false
  ) throws -> [Path] {
    if lineCommentFrontmatter {
      guard paths.isEmpty == false,
        paths.allSatisfy({ $0.exists && $0.isFile })
      else {
        throw ValidationError(
          "--line-comment-frontmatter requires explicitly supplied regular files"
        )
      }
    }
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

      let shippedSyntax = NonMarkdownFrontMatterSyntax.shippedSyntax(
        forFileName: path.lastComponent,
        fileExtension: fileExtension
      )
      if fileExtension == "md" || fileExtension == "markdown" {
        selected.append(path)
      } else if shippedSyntax == .lineComment {
        if includeNonMarkdown || explicitSingleFile || lineCommentFrontmatter {
          selected.append(path)
        } else {
          writeIgnoredHint(for: path)
        }
      } else if fileExtension == "txt" {
        if includeNonMarkdown {
          selected.append(path)
        } else {
          writeIgnoredHint(for: path)
        }
      } else if shippedSyntax != nil {
        if includeNonMarkdown || explicitSingleFile {
          selected.append(path)
        } else {
          writeIgnoredHint(for: path)
        }
      } else if lineCommentFrontmatter {
        selected.append(path)
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
      let shippedSyntax = NonMarkdownFrontMatterSyntax.shippedSyntax(
        forFileName: child.lastComponent,
        fileExtension: fileExtension
      )
      if fileExtension == "md" || fileExtension == "markdown" {
        result.append(child)
      } else if includeNonMarkdown && shippedSyntax == .lineComment {
        result.append(child)
      } else if includeNonMarkdown && fileExtension == "txt" {
        result.append(child)
      } else if includeNonMarkdown && shippedSyntax != nil {
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
