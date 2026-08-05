import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Selects wrapped-frontmatter discovery for the read-only frontmatter commands.
struct FrontMatterSourceOptions: ParsableArguments {
  @Flag(
    name: .customLong("include-non-md"),
    help: "Also scan non-Markdown text files for comment-wrapped YAML frontmatter"
  )
  var includeNonMarkdown = false

  @Option(
    name: .customLong("frontmatter-syntax"),
    help: "Use a built-in or project-defined wrapped-frontmatter syntax"
  )
  var syntaxName: String?

  @Option(
    name: .customLong("frontmatter-comment-open"),
    help: "Use this opening comment delimiter for wrapped frontmatter"
  )
  var commentOpen: String?

  @Option(
    name: .customLong("frontmatter-comment-close"),
    help: "Use this closing comment delimiter for wrapped frontmatter"
  )
  var commentClose: String?

  @Flag(
    name: .customLong("no-frontmatter-presets"),
    help: "Disable built-in extension-to-syntax inference"
  )
  var noPresets = false

  func makeReader(root: Path = .current) throws -> FrontMatterFileReader {
    guard (commentOpen == nil) == (commentClose == nil) else {
      throw ValidationError(
        "--frontmatter-comment-open and --frontmatter-comment-close must be provided together"
      )
    }
    guard syntaxName == nil || commentOpen == nil else {
      throw ValidationError(
        "--frontmatter-syntax cannot be combined with raw frontmatter comment delimiters"
      )
    }
    guard includeNonMarkdown || syntaxName == nil && commentOpen == nil && noPresets == false else {
      throw ValidationError(
        "Wrapped-frontmatter syntax options require --include-non-md"
      )
    }

    let configPath = root + ".md-utils/md-utils.json"
    let projectConfiguration: WrappedFrontMatterProjectConfiguration
    if configPath.exists {
      projectConfiguration = try MdUtilsConfig.load(from: configPath).frontmatter
        ?? WrappedFrontMatterProjectConfiguration()
    } else {
      projectConfiguration = try WrappedFrontMatterProjectConfiguration()
    }

    let rawSyntax: WrappedFrontMatterSyntax?
    if let commentOpen, let commentClose {
      do {
        rawSyntax = try WrappedFrontMatterSyntax(
          openingCommentDelimiter: commentOpen,
          closingCommentDelimiter: commentClose
        )
      } catch {
        throw ValidationError(error.localizedDescription)
      }
    } else {
      rawSyntax = nil
    }

    let namedSyntax: WrappedFrontMatterSyntax?
    if let syntaxName {
      guard let syntax = projectConfiguration.syntax(named: syntaxName) else {
        throw ValidationError("Unknown wrapped frontmatter syntax \"\(syntaxName)\"")
      }
      namedSyntax = syntax
    } else {
      namedSyntax = nil
    }

    return FrontMatterFileReader(
      includeNonMarkdown: includeNonMarkdown,
      rawSyntax: rawSyntax,
      namedSyntax: namedSyntax,
      projectConfiguration: projectConfiguration,
      useBuiltInPresets: noPresets == false
    )
  }
}

/// Reads Markdown frontmatter normally and wrapped frontmatter from opted-in non-Markdown files.
struct FrontMatterFileReader {
  let includeNonMarkdown: Bool
  let rawSyntax: WrappedFrontMatterSyntax?
  let namedSyntax: WrappedFrontMatterSyntax?
  let projectConfiguration: WrappedFrontMatterProjectConfiguration
  let useBuiltInPresets: Bool

  func document(at path: Path) throws -> MarkdownDocument {
    let content: String = try path.read(.utf8)
    guard isMarkdown(path) == false else {
      return try MarkdownDocument(content: content)
    }
    guard includeNonMarkdown else {
      return try MarkdownDocument(content: content)
    }

    guard let syntax = syntax(for: path) else {
      return MarkdownDocument(frontMatter: .init(), body: content)
    }
    let scan = WrappedFrontMatterScanner(syntax: syntax).scan(content)
    let mapping = try scan.rawFrontMatter.map(YAMLConversion.parse) ?? .init()
    if scan.hasMultipleBlocks {
      throw FrontMatterReadError.multipleBlocks(
        path: path.string,
        openingLines: scan.additionalBlocks.map(\.openingLine)
      )
    }
    return MarkdownDocument(frontMatter: mapping, body: content)
  }

  private func syntax(for path: Path) -> WrappedFrontMatterSyntax? {
    if let rawSyntax { return rawSyntax }
    if let namedSyntax { return namedSyntax }
    guard let pathExtension = path.extension else { return nil }
    let normalized = pathExtension.lowercased()
    if let mappedName = projectConfiguration.extensionMappings[normalized] {
      return projectConfiguration.syntax(named: mappedName)
    }
    guard useBuiltInPresets, projectConfiguration.useBuiltInPresets else { return nil }
    return WrappedFrontMatterPreset.inferred(forExtension: normalized)?.syntax
  }

  private func isMarkdown(_ path: Path) -> Bool {
    guard let pathExtension = path.extension?.lowercased() else { return false }
    return pathExtension == "md" || pathExtension == "markdown"
  }
}

enum FrontMatterReadError: LocalizedError {
  case multipleBlocks(path: String, openingLines: [Int])

  var errorDescription: String? {
    switch self {
    case .multipleBlocks(let path, let openingLines):
      let lines = openingLines.map(String.init).joined(separator: ", ")
      return "Invalid wrapped frontmatter in \(path): additional blocks begin on line(s) \(lines); only one block is allowed"
    }
  }
}
