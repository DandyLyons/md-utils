//
//  WikilinkResolver.swift
//  MarkdownUtilities
//

import Foundation
import MarkdownUtilitiesCore
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

  /// Shared portable lookup semantics over this native discovery snapshot.
  private let collectionResolver: CollectionWikilinkResolver

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

    try WikilinkResolver.collectFiles(
      in: normalizedRoot,
      root: normalizedRoot,
      discovered: &discovered,
      mdFiles: &mdFiles,
    )

    self.allFiles = discovered
    self.markdownFiles = mdFiles
    let prefix = normalizedRoot.string.hasSuffix("/") ? normalizedRoot.string : normalizedRoot.string + "/"
    self.collectionResolver = CollectionWikilinkResolver(
      paths: Set(discovered.map { String($0.string.dropFirst(prefix.count)) }), namespaceComplete: true)
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
    let prefix = root.string.hasSuffix("/") ? root.string : root.string + "/"
    let source = sourceFile.absolute().string
    guard source.hasPrefix(prefix) else { return .unresolved }
    let result = collectionResolver.resolve(target: target, from: String(source.dropFirst(prefix.count)))
    switch result.status {
    case .resolved:
      guard let destination = result.destination else { return .unresolved }
      return .resolved(root + Path(destination))
    case .ambiguous: return .ambiguous(result.candidates.map { root + Path($0) })
    case .unresolved, .unavailable: return .unresolved
    }
  }
  // MARK: - Private Helpers

  /// Recursively collects files from a directory, skipping hidden files.
  private static func collectFiles(
    in directory: Path,
    root: Path,
    discovered: inout [Path],
    mdFiles: inout [Path],
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
        )
      } else if child.isFile {
        let absolute = child.absolute()
        discovered.append(absolute)

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
