//
//  WikilinkResolver.swift
//  MarkdownUtilities
//

import Foundation
import PathKit

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
/// 1. **Filename match** — search index for files whose stem matches target (case-insensitive)
/// 2. **Relative path** — resolve from source file's parent directory
/// 3. **Absolute path** — resolve from root directory
///
/// When a target has no extension, only `.md` and `.markdown` files are matched.
/// When a target has an explicit extension, it is matched exactly.
public struct WikilinkResolver: @unchecked Sendable {

  /// The root directory of the vault.
  public let root: Path

  /// All files discovered under root, relative to root.
  public let allFiles: [Path]

  /// Markdown files discovered under root (absolute paths).
  public let markdownFiles: [Path]

  /// Index mapping lowercased file stems to their absolute paths.
  private let stemIndex: [String: [Path]]

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

    // Strategy 1: Filename match (search by stem)
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

    // Strategy 2: Relative path (from source file's parent)
    let sourceDir = sourceFile.absolute().parent()
    let relativePath = sourceDir + targetPath
    if let found = tryResolveExact(relativePath, hasExtension: hasExtension) {
      return found
    }

    // Strategy 3: Absolute path (from root)
    let absolutePath = root + targetPath
    if let found = tryResolveExact(absolutePath, hasExtension: hasExtension) {
      return found
    }

    return .unresolved
  }

  // MARK: - Private Helpers

  /// Tries to resolve a path, appending markdown extensions if needed.
  private func tryResolveExact(_ path: Path, hasExtension: Bool) -> WikilinkResolution? {
    if hasExtension {
      let normalized = path.absolute()
      if normalized.exists && normalized.isFile {
        return .resolved(normalized)
      }
    } else {
      // Try markdown extensions
      for ext in Self.markdownExtensions.sorted() {
        let withExt = Path(path.string + ".\(ext)")
        let normalized = withExt.absolute()
        if normalized.exists && normalized.isFile {
          return .resolved(normalized)
        }
      }
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
