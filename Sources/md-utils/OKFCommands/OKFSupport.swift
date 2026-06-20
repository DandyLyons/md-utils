//
//  OKFSupport.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit
import Yams

enum OKFConstants {
  static let specURL = "https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md"
  static let reservedFilenames = Set(["index.md", "log.md"])
}

struct OKFValidationIssue {
  enum Severity {
    case error
    case warning
  }

  var severity: Severity
  var filePath: String
  var path: String
  var message: String
}

struct OKFValidationSummary {
  var bundlePath: Path
  var filesScanned: Int
  var conceptDocuments: Int
  var reservedFiles: Int
  var issues: [OKFValidationIssue]

  var errorCount: Int { issues.filter { $0.severity == .error }.count }
  var warningCount: Int { issues.filter { $0.severity == .warning }.count }
  var hasErrors: Bool { errorCount > 0 }
}

enum OKFValidator {
  static func validate(bundlePath: Path) throws -> OKFValidationSummary {
    guard bundlePath.exists else {
      throw ValidationError("OKF bundle directory does not exist: \(bundlePath.string)")
    }
    guard bundlePath.isDirectory else {
      throw ValidationError("OKF bundle path must be a directory: \(bundlePath.string)")
    }

    let files = try OKFFileScanner.markdownFiles(root: bundlePath)
    var issues: [OKFValidationIssue] = []
    var conceptDocuments = 0
    var reservedFiles = 0

    for file in files {
      let relativePath = relativePath(from: bundlePath, to: file)
      if isReserved(file) {
        reservedFiles += 1
        issues.append(contentsOf: validateReservedFile(file, relativePath: relativePath))
      } else {
        conceptDocuments += 1
        issues.append(contentsOf: validateConceptFile(file, relativePath: relativePath))
      }
    }

    return OKFValidationSummary(
      bundlePath: bundlePath,
      filesScanned: files.count,
      conceptDocuments: conceptDocuments,
      reservedFiles: reservedFiles,
      issues: issues
    )
  }

  private static func validateConceptFile(_ file: Path, relativePath: String) -> [OKFValidationIssue] {
    do {
      let content: String = try file.read()
      let presence = frontmatterPresence(in: content)
      guard presence.hasFrontmatter else {
        let message = content.hasPrefix("---\n")
          ? "frontmatter block is not closed with ---"
          : "required by OKF v0.1 draft concept documents"
        return [issueError(relativePath, path: "frontmatter", message: message)]
      }

      let document: MarkdownDocument
      do {
        document = try MarkdownDocument(content: content)
      } catch {
        return [issueError(relativePath, path: "frontmatter", message: "invalid YAML: \(error.localizedDescription)")]
      }

      guard let typeNode = document.frontMatter[Yams.Node("type")] else {
        return [issueError(relativePath, path: "frontmatter.type", message: "missing required field \"type\"")]
      }
      guard let typeValue = typeNode.string else {
        return [issueError(relativePath, path: "frontmatter.type", message: "must be a string")]
      }
      guard !typeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return [issueError(relativePath, path: "frontmatter.type", message: "must not be empty")]
      }

      return []
    } catch {
      return [issueError(relativePath, path: "file", message: error.localizedDescription)]
    }
  }

  private static func validateReservedFile(_ file: Path, relativePath: String) -> [OKFValidationIssue] {
    guard file.lastComponent == "log.md" else { return [] }
    do {
      let content: String = try file.read()
      let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
      var issues: [OKFValidationIssue] = []
      for (index, line) in lines.enumerated() {
        guard line.hasPrefix("## ") else { continue }
        let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        if !isISODateHeading(heading) {
          issues.append(issueError(
            relativePath,
            path: "line \(index + 1)",
            message: "expected ISO date heading like \"## 2026-06-20\""
          ))
        }
      }
      return issues
    } catch {
      return [issueError(relativePath, path: "file", message: error.localizedDescription)]
    }
  }

  private static func isISODateHeading(_ value: String) -> Bool {
    guard value.count == 10 else { return false }
    let pattern = #"^\d{4}-\d{2}-\d{2}$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(value.startIndex..., in: value)
    return regex.firstMatch(in: value, range: range) != nil
  }

  private static func isReserved(_ file: Path) -> Bool {
    OKFConstants.reservedFilenames.contains(file.lastComponent)
  }

  private static func issueError(_ filePath: String, path: String, message: String) -> OKFValidationIssue {
    OKFValidationIssue(severity: .error, filePath: filePath, path: path, message: message)
  }
}

enum OKFFileScanner {
  static func markdownFiles(root: Path) throws -> [Path] {
    let manager = FileManager.default
    let rootURL = URL(fileURLWithPath: root.absolute().string)
    guard let enumerator = manager.enumerator(
      at: rootURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var files: [Path] = []
    for case let url as URL in enumerator {
      let path = Path(url.path)
      guard !path.isDirectory else { continue }
      guard let ext = path.extension?.lowercased(), ["md", "markdown"].contains(ext) else { continue }
      files.append(path)
    }
    files.sort { $0.string < $1.string }
    return files
  }
}

enum OKFValidationFormatter {
  static func render(_ summary: OKFValidationSummary) -> String {
    var lines: [String] = []
    lines.append("\(CLIStyle.metadata("Validated OKF bundle:")) \(CLIStyle.path(directoryDisplayPath(summary.bundlePath)))")
    lines.append("\(CLIStyle.metadata("Files scanned:")) \(summary.filesScanned)")
    lines.append("\(CLIStyle.metadata("Concept documents:")) \(summary.conceptDocuments)")
    lines.append("\(CLIStyle.metadata("Reserved files:")) \(summary.reservedFiles)")
    lines.append("\(CLIStyle.metadata("Errors:")) \(summary.errorCount)")
    lines.append("\(CLIStyle.metadata("Warnings:")) \(summary.warningCount)")

    if summary.issues.isEmpty {
      lines.append("")
      lines.append(CLIStyle.success("OKF v0.1 draft conformance checks passed."))
      return lines.joined(separator: "\n")
    }

    lines.append("")
    for issue in summary.issues {
      let label: String
      switch issue.severity {
      case .error:
        label = CLIStyle.error("ERROR")
      case .warning:
        label = CLIStyle.warning("WARN")
      }
      lines.append("\(label) \(CLIStyle.path(issue.filePath))")
      lines.append("  \(CLIStyle.metadata(issue.path + ":")) \(issue.message)")
    }
    return lines.joined(separator: "\n")
  }
}

struct OKFTypeSetOptions {
  var directory: Path
  var type: String
  var arrayKey: String?
  var arrayContains: String?
}

struct OKFTypeSetSummary {
  var directory: Path
  var scannedFiles: Int
  var matchedFiles: [String]
  var updatedFiles: [String]
  var skippedReservedFiles: [String]
}

enum OKFTypeSetter {
  static func setType(options: OKFTypeSetOptions) throws -> OKFTypeSetSummary {
    let trimmedType = options.type.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedType.isEmpty else {
      throw ValidationError("--type must not be empty")
    }
    guard (options.arrayKey == nil) == (options.arrayContains == nil) else {
      throw ValidationError("--array-key and --array-contains must be provided together")
    }
    guard options.directory.exists else {
      throw ValidationError("Directory does not exist: \(options.directory.string)")
    }
    guard options.directory.isDirectory else {
      throw ValidationError("--dir must refer to a directory: \(options.directory.string)")
    }

    let files = try OKFFileScanner.markdownFiles(root: options.directory)
    var matchedFiles: [String] = []
    var updatedFiles: [String] = []
    var skippedReservedFiles: [String] = []

    for file in files {
      let relative = relativePath(from: options.directory, to: file)
      guard !OKFConstants.reservedFilenames.contains(file.lastComponent) else {
        skippedReservedFiles.append(relative)
        continue
      }

      let content: String = try file.read()
      let document = try MarkdownDocument(content: content)
      guard matchesFilter(document: document, key: options.arrayKey, contains: options.arrayContains) else {
        continue
      }

      matchedFiles.append(relative)
      var updatedDocument = document
      updatedDocument.setValue(trimmedType, forKey: "type")
      let updated = try updatedDocument.render()
      try file.write(updated)
      updatedFiles.append(relative)
    }

    return OKFTypeSetSummary(
      directory: options.directory,
      scannedFiles: files.count,
      matchedFiles: matchedFiles,
      updatedFiles: updatedFiles,
      skippedReservedFiles: skippedReservedFiles
    )
  }

  private static func matchesFilter(document: MarkdownDocument, key: String?, contains value: String?) -> Bool {
    guard let key, let value else { return true }
    guard let node = document.frontMatter[Yams.Node(key)] else { return false }
    guard case .sequence(let sequence) = node else { return false }
    return sequence.contains { $0.string == value }
  }
}

enum OKFTypeSetFormatter {
  static func render(_ summary: OKFTypeSetSummary) -> String {
    var lines: [String] = []
    lines.append("\(CLIStyle.success("Set OKF type")) in \(summary.updatedFiles.count) file(s).")
    lines.append("\(CLIStyle.metadata("Directory:")) \(CLIStyle.path(directoryDisplayPath(summary.directory)))")
    lines.append("\(CLIStyle.metadata("Files scanned:")) \(summary.scannedFiles)")
    lines.append("\(CLIStyle.metadata("Files matched:")) \(summary.matchedFiles.count)")
    if !summary.updatedFiles.isEmpty {
      lines.append("")
      for file in summary.updatedFiles {
        lines.append("  \(CLIStyle.success("OK")) \(CLIStyle.path(file))")
      }
    }
    if !summary.skippedReservedFiles.isEmpty {
      lines.append("")
      lines.append(CLIStyle.muted("Skipped reserved OKF files: \(summary.skippedReservedFiles.count)"))
    }
    return lines.joined(separator: "\n")
  }
}

func relativePath(from root: Path, to path: Path) -> String {
  let rootString = root.absolute().string
  let pathString = path.absolute().string
  let normalizedRoot = rootString.hasSuffix("/") ? rootString : rootString + "/"
  if pathString.hasPrefix(normalizedRoot) {
    return String(pathString.dropFirst(normalizedRoot.count))
  }
  return path.string
}

func directoryDisplayPath(_ path: Path) -> String {
  if path == .current { return "." }
  let string = path.string
  guard ![".", "..", "~"].contains(string) else { return string }
  return string.hasSuffix("/") ? string : string + "/"
}
