//
//  WikilinkResolver.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilitiesCore
import PathKit
import Parsing

/// The result of resolving a wikilink target to a file on disk.
public enum WikilinkResolution: @unchecked Sendable, Equatable {
  /// The target resolved to exactly one file.
  case resolved(Path)

  /// The target could not be matched to any file.
  case unresolved

  /// The target matched multiple files (ambiguous).
  case ambiguous([Path])
}

/// Resolves wikilink targets to files within a vault (root directory).
///
/// Resolution priority:
/// Bare names use case-insensitive collection-wide filename matching. Targets
/// containing `/` are vault-root-relative, except explicit `./` and `../`
/// prefixes, which resolve from the source directory. Paths never fall back to
/// another base directory or a filename match, and must belong to the vault snapshot.
///
/// When a target has no extension, only `.md` and `.markdown` files are matched.
/// When a target has an explicit extension, it is matched exactly.
public struct WikilinkResolver: @unchecked Sendable {

  /// The root directory of the vault.
  public let root: Path

  /// All files discovered under root, as absolute paths.
  public let allFiles: [Path]

  /// Markdown files discovered under root (absolute paths).
  public let markdownFiles: [Path]

  /// Index mapping lowercased file stems to their absolute paths.
  private let stemIndex: [String: [Path]]

  /// Exact snapshot membership also prevents traversal outside the collection.
  private let exactPaths: Set<Path>

  /// Markdown extensions considered for no-extension targets.
  private static let markdownExtensions: Set<String> = ["md", "markdown"]

  /// Creates a resolver by scanning the given root directory.
  ///
  /// - Parameter root: The vault root directory. Must exist and be a directory.
  /// - Throws: If the root path does not exist or is not a directory.
  public init(root: Path) throws {
    guard root.exists else {
      throw WikilinkResolverError.rootDoesNotExist(root.string)
    }
    guard root.isDirectory else {
      throw WikilinkResolverError.rootIsNotDirectory(root.string)
    }

    let normalizedRoot = root.absolute()
    self.root = normalizedRoot

    var discovered: [Path] = []
    var mdFiles: [Path] = []
    var index: [String: [Path]] = [:]

    try WikilinkResolver.collectFiles(
      in: normalizedRoot,
      root: normalizedRoot,
      discovered: &discovered,
      mdFiles: &mdFiles,
      index: &index
    )

    self.allFiles = discovered
    self.exactPaths = Set(discovered)
    self.markdownFiles = mdFiles
    self.stemIndex = index
  }

  /// Resolves a wikilink to a file path.
  ///
  /// - Parameters:
  ///   - wikilink: The wikilink to resolve.
  ///   - sourceFile: The file containing the wikilink (used for relative resolution).
  /// - Returns: The resolution result.
  public func resolve(_ wikilink: Wikilink, from sourceFile: Path) -> WikilinkResolution {
    resolve(target: wikilink.target, from: sourceFile)
  }

  /// Resolves a wikilink target string to a file path.
  ///
  /// - Parameters:
  ///   - target: The wikilink target (e.g. "MyPage", "subfolder/MyPage", "image.png").
  ///   - sourceFile: The file containing the wikilink (used for relative resolution).
  /// - Returns: The resolution result.
  public func resolve(target: String, from sourceFile: Path) -> WikilinkResolution {
    // Empty target (self-referencing anchor like [[#heading]]) resolves to source file
    if target.isEmpty {
      return .resolved(sourceFile.absolute())
    }

    let hasExtension = Path(target).extension != nil
    let targetPath = Path(target)

    // Parse explicit relative prefixes before PathKit normalizes away `./`.
    if target.contains("/") {
      var input = target[...]
      let relativePrefix = OneOf { "./"; "../" }
      let isSourceRelative = (try? relativePrefix.parse(&input)) != nil
      let base = isSourceRelative ? sourceFile.absolute().parent() : root
      return tryResolveExact(base + targetPath, hasExtension: hasExtension) ?? .unresolved
    }

    // Bare names retain collection-wide matching, including ambiguity.
    let stem = targetPath.lastComponentWithoutExtension.lowercased()
    if let candidates = stemIndex[stem] {
      let filtered: [Path]
      if hasExtension {
        // Explicit extension: match exactly
        let targetExt = Path(target).extension ?? ""
        filtered = candidates.filter { ($0.extension ?? "") == targetExt }
      } else {
        // No extension: only match markdown files
        filtered = candidates.filter { ext in
          guard let fileExt = ext.extension else { return false }
          return Self.markdownExtensions.contains(fileExt)
        }
      }

      if filtered.count == 1 {
        return .resolved(filtered[0])
      } else if filtered.count > 1 {
        return .ambiguous(filtered.sorted { $0.string < $1.string })
      }
    }

    return .unresolved
  }
  // MARK: - Private Helpers

  /// Tries to resolve a path, appending markdown extensions if needed.
  private func tryResolveExact(_ path: Path, hasExtension: Bool) -> WikilinkResolution? {
    if hasExtension {
      let normalized = path.absolute()
      if exactPaths.contains(normalized) {
        return .resolved(normalized)
      }
    } else {
      // Both Markdown extensions can exist; do not arbitrarily select one.
      var matches: [Path] = []
      for ext in Self.markdownExtensions.sorted() {
        let withExt = Path(path.string + ".\(ext)")
        let normalized = withExt.absolute()
        if exactPaths.contains(normalized) { matches.append(normalized) }
      }
      if matches.count > 1 { return .ambiguous(matches) }
      if let match = matches.first { return .resolved(match) }
    }
    return nil
  }

  /// Recursively collects files from a directory, skipping hidden files.
  private static func collectFiles(
    in directory: Path,
    root: Path,
    discovered: inout [Path],
    mdFiles: inout [Path],
    index: inout [String: [Path]]
  ) throws {
    let children = try directory.children()
    for child in children.sorted(by: { $0.string < $1.string }) {
      // Do not escape the collection or recurse through symlink cycles.
      if child.isSymlink { continue }
      // Skip hidden files and directories
      if child.lastComponent.hasPrefix(".") {
        continue
      }

      if child.isDirectory {
        try collectFiles(
          in: child,
          root: root,
          discovered: &discovered,
          mdFiles: &mdFiles,
          index: &index
        )
      } else if child.isFile {
        let absolute = child.absolute()
        discovered.append(absolute)

        let stem = child.lastComponentWithoutExtension.lowercased()
        index[stem, default: []].append(absolute)

        if let ext = child.extension, markdownExtensions.contains(ext) {
          mdFiles.append(absolute)
        }
      }
    }
  }
}

/// Errors that can occur when creating a ``WikilinkResolver``.
public enum WikilinkResolverError: Error, Sendable, CustomStringConvertible {
  case rootDoesNotExist(String)
  case rootIsNotDirectory(String)

  public var description: String {
    switch self {
    case .rootDoesNotExist(let path):
      "Root path does not exist: \(path)"
    case .rootIsNotDirectory(let path):
      "Root path is not a directory: \(path)"
    }
  }
}
