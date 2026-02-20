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

  /// Disable alphabetical sorting of file paths.
  @Flag(
    name: .customLong("no-sort"),
    help: "Disable alphabetical sorting of file paths"
  )
  var noSort: Bool = false

  /// Paths or glob patterns to exclude from processing.
  @Option(
    name: .customLong("exclude"),
    help: "Paths or glob patterns to exclude from processing (can be repeated)",
    completion: .file(),
    transform: { Path($0) }
  )
  var exclude: [Path] = []

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
    let excludePatterns = exclude.map { $0.absolute().string }

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
          extensions: allowedExtensions,
          excludePatterns: excludePatterns
        )
        resolvedFiles.append(contentsOf: files)
      } else {
        // Single file - check extension filter and exclusions
        if matchesExtension(path, allowedExtensions: allowedExtensions)
          && !isExcluded(path, excludePatterns: excludePatterns)
        {
          resolvedFiles.append(path)
        }
      }
    }

    // Sort alphabetically by full path (unless disabled)
    if !noSort {
      resolvedFiles.sort { $0.string < $1.string }
    }

    return resolvedFiles
  }

  /// Expand a directory to files matching criteria.
  private func expandDirectory(
    _ directory: Path,
    recursive: Bool,
    includeHidden: Bool,
    extensions: Set<String>,
    excludePatterns: [String]
  ) throws -> [Path] {
    var files: [Path] = []

    let children = try directory.children()

    for child in children {
      // Skip hidden files/directories if not included
      if !includeHidden && child.lastComponent.hasPrefix(".") {
        continue
      }

      // Skip excluded paths
      if isExcluded(child, excludePatterns: excludePatterns) {
        continue
      }

      if child.isDirectory {
        // Recurse into subdirectory if recursive
        if recursive {
          let subdirFiles = try expandDirectory(
            child,
            recursive: recursive,
            includeHidden: includeHidden,
            extensions: extensions,
            excludePatterns: excludePatterns
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

  /// Returns true if the path should be excluded based on the exclude patterns.
  ///
  /// Non-glob patterns use prefix matching, so a directory path excludes all its contents.
  /// Glob patterns support `*` (within a path component), `**` (across path components),
  /// `?` (single character), and `[...]` character classes.
  private func isExcluded(_ path: Path, excludePatterns: [String]) -> Bool {
    guard !excludePatterns.isEmpty else { return false }
    let absolutePathString = path.absolute().string

    for pattern in excludePatterns {
      let isGlob = pattern.contains("*") || pattern.contains("?") || pattern.contains("[")
      if isGlob {
        if matchesGlobPattern(absolutePathString, glob: pattern) {
          return true
        }
      } else {
        // Normalize trailing slash for directory patterns
        let normalizedPattern =
          pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
        // Match exact path or any path nested inside the excluded directory
        if absolutePathString == normalizedPattern
          || absolutePathString.hasPrefix(normalizedPattern + "/")
        {
          return true
        }
      }
    }

    return false
  }

  /// Returns true if the path string matches the glob pattern.
  ///
  /// Supports:
  /// - `*` — any characters within a single path component
  /// - `**/` — zero or more complete path components
  /// - `**` — any characters including path separators (when not followed by `/`)
  /// - `?` — any single character within a path component
  /// - `[...]` — character classes (use `!` after `[` to negate)
  private func matchesGlobPattern(_ pathString: String, glob: String) -> Bool {
    let pattern = globToRegex(glob)
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return false
    }
    let range = NSRange(pathString.startIndex..., in: pathString)
    return regex.firstMatch(in: pathString, range: range) != nil
  }

  /// Converts a glob pattern to a regular expression string.
  private func globToRegex(_ glob: String) -> String {
    var result = "^"
    var i = glob.startIndex

    while i < glob.endIndex {
      let ch = glob[i]
      let nextIdx = glob.index(after: i)

      switch ch {
      case "*":
        if nextIdx < glob.endIndex && glob[nextIdx] == "*" {
          // Double star: "**"
          let afterStars = glob.index(after: nextIdx)
          if afterStars < glob.endIndex && glob[afterStars] == "/" {
            // "**/" matches zero or more complete path components
            result += "([^/]+/)*"
            i = glob.index(after: afterStars)
          } else {
            // "**" at end or before non-"/": match any characters including separators
            result += ".*"
            i = afterStars
          }
        } else {
          // Single "*": match any characters within a path component
          result += "[^/]*"
          i = nextIdx
        }
      case "?":
        result += "[^/]"
        i = nextIdx
      case "[":
        var charClass = "["
        i = nextIdx
        // Handle negation
        if i < glob.endIndex && glob[i] == "!" {
          charClass += "^"
          i = glob.index(after: i)
        }
        while i < glob.endIndex && glob[i] != "]" {
          charClass += NSRegularExpression.escapedPattern(for: String(glob[i]))
          i = glob.index(after: i)
        }
        charClass += "]"
        result += charClass
        if i < glob.endIndex {
          i = glob.index(after: i)  // consume "]"
        }
      default:
        result += NSRegularExpression.escapedPattern(for: String(ch))
        i = nextIdx
      }
    }

    result += "$"
    return result
  }
}
