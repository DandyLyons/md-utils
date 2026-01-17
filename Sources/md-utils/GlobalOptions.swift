//
//  GlobalOptions.swift
//  md-utils
//

import ArgumentParser
import Foundation
import PathKit

/// Global options shared across all subcommands.
struct GlobalOptions: ParsableArguments {
  /// Paths to files or directories to process.
  @Argument(
    help: "Paths to Markdown files or directories to process",
    completion: .file(),
    transform: { Path($0) }
  )
  var paths: [Path] = []

  /// Process directories recursively (default: true).
  @Flag(
    name: [.customLong("recursive"), .customShort("r")],
    inversion: .prefixedNo,
    help: "Process directories recursively (use --no-recursive to disable)"
  )
  var recursive: Bool = true

  /// Include hidden files and directories.
  @Flag(
    name: [.customLong("include-hidden"), .customShort("i")],
    help: "Include hidden files and directories (starting with '.')"
  )
  var includeHidden: Bool = false

  /// File extensions to process (comma-separated).
  @Option(
    name: .long,
    help: "File extensions to process (comma-separated, default: md,markdown)"
  )
  var extensions: String = "md,markdown"

  /// Resolve paths to actual Markdown files to process.
  ///
  /// Expands directories to their children, applies recursion and hidden file filters,
  /// and filters by extension.
  ///
  /// - Returns: Array of file paths to process
  /// - Throws: If a specified path doesn't exist
  func resolvedPaths() throws -> [Path] {
    // If no paths specified, use current directory
    let pathsToProcess = paths.isEmpty ? [Path.current] : paths

    var resolvedFiles: [Path] = []
    let allowedExtensions = Set(extensions.split(separator: ",").map(String.init))

    for path in pathsToProcess {
      guard path.exists else {
        throw ValidationError("Path does not exist: \(path)")
      }

      if path.isDirectory {
        // Expand directory to files
        let files = try expandDirectory(
          path,
          recursive: recursive,
          includeHidden: includeHidden,
          extensions: allowedExtensions
        )
        resolvedFiles.append(contentsOf: files)
      } else {
        // Single file - check if it matches extension filter
        if matchesExtension(path, allowedExtensions: allowedExtensions) {
          resolvedFiles.append(path)
        }
      }
    }

    return resolvedFiles
  }

  /// Expand a directory to files matching criteria.
  private func expandDirectory(
    _ directory: Path,
    recursive: Bool,
    includeHidden: Bool,
    extensions: Set<String>
  ) throws -> [Path] {
    var files: [Path] = []

    let children = try directory.children()

    for child in children {
      // Skip hidden files/directories if not included
      if !includeHidden && child.lastComponent.hasPrefix(".") {
        continue
      }

      if child.isDirectory {
        // Recurse into subdirectory if recursive
        if recursive {
          let subdirFiles = try expandDirectory(
            child,
            recursive: recursive,
            includeHidden: includeHidden,
            extensions: extensions
          )
          files.append(contentsOf: subdirFiles)
        }
      } else {
        // Check if file matches extension filter
        if matchesExtension(child, allowedExtensions: extensions) {
          files.append(child)
        }
      }
    }

    return files
  }

  /// Check if a file matches the allowed extensions.
  private func matchesExtension(_ path: Path, allowedExtensions: Set<String>) -> Bool {
    guard let ext = path.extension else {
      return false
    }
    return allowedExtensions.contains(ext)
  }
}
