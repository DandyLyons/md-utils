//
//  ReadMetadata.swift
//  md-utils
//

import ArgumentParser
import Foundation
import MarkdownUtilities
import PathKit

extension CLIEntry.FileMetadataCommands {
  /// Read metadata from files
  struct ReadMetadata: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "read",
      abstract: "Read file metadata including standard attributes and extended attributes (xattr)",
      discussion: """
        Reads file metadata including:
        - Size, creation date, modification date, access date
        - POSIX permissions, owner, group
        - Extended attributes (xattr) - included by default

        Output formats:
        - json-pretty: Pretty-printed JSON (default)
        - json: Compact JSON
        - md-table: Markdown table
        - csv: CSV format for spreadsheet import

        By default, processes directories recursively.
        """
    )

    @OptionGroup var options: GlobalOptions

    @Option(
      name: .long,
      help: "Output format: md-table, csv, json, json-pretty (default: json-pretty)"
    )
    var format: OutputFormat = .jsonPretty

    @Flag(
      name: .long,
      help: "Exclude extended attributes (xattr) from output"
    )
    var excludeXattr: Bool = false

    @Flag(
      name: .long,
      help: "Ignore errors when reading extended attributes and continue processing"
    )
    var ignoreXattrErrors: Bool = false

    enum OutputFormat: String, ExpressibleByArgument {
      case mdTable = "md-table"
      case csv
      case json
      case jsonPretty = "json-pretty"
    }

    mutating func run() async throws {
      let files = try options.resolvedPaths()

      guard !files.isEmpty else {
        throw ValidationError("No files found to process")
      }

      let reader = FileMetadataReader()
      var metadata: [FileMetadata] = []
      var hasErrors = false

      for file in files {
        do {
          let fileMeta = try reader.readMetadata(
            at: file.string,
            includeExtendedAttributes: !excludeXattr
          )
          metadata.append(fileMeta)
        } catch let error as FileMetadataError {
          // Check if this is an xattr-related error
          let isXattrError: Bool
          switch error {
          case .xattrReadFailed, .xattrUnsupported:
            isXattrError = true
          default:
            isXattrError = false
          }

          if isXattrError && ignoreXattrErrors && !excludeXattr {
            // Show warning and retry without xattr
            FileHandle.standardError.write(
              "Warning: Failed to read extended attributes for \(file): \(error)\n")
            FileHandle.standardError.write("         Continuing without extended attributes...\n")

            do {
              let fileMeta = try reader.readMetadata(
                at: file.string,
                includeExtendedAttributes: false
              )
              metadata.append(fileMeta)
            } catch {
              // If it fails again without xattr, show error and mark as failed
              FileHandle.standardError.write("Error reading \(file): \(error)\n")
              hasErrors = true
            }
          } else {
            // Show error for non-xattr errors or when flag not set
            FileHandle.standardError.write("Error reading \(file): \(error)\n")
            hasErrors = true
          }
        } catch {
          // Handle non-FileMetadataError errors
          FileHandle.standardError.write("Error reading \(file): \(error)\n")
          hasErrors = true
        }
      }

      // Output formatted results
      if !metadata.isEmpty {
        let output = try formatOutput(metadata)
        print(output)
      }

      // Exit with failure if any errors occurred
      if hasErrors {
        throw ExitCode.failure
      }
    }

    /// Format metadata according to the selected output format
    private func formatOutput(_ metadata: [FileMetadata]) throws -> String {
      switch format {
      case .mdTable:
        return formatAsMDTable(metadata)
      case .csv:
        return formatAsCSV(metadata)
      case .json:
        return try formatAsJSON(metadata, prettyPrint: false)
      case .jsonPretty:
        return try formatAsJSON(metadata, prettyPrint: true)
      }
    }

    /// Format metadata as Markdown table
    private func formatAsMDTable(_ metadata: [FileMetadata]) -> String {
      var lines: [String] = []

      // Header
      lines.append(
        "| Path | Size | Created | Modified | Permissions | Owner | Group |")
      lines.append(
        "|------|------|---------|----------|-------------|-------|-------|")

      // Rows
      for meta in metadata {
        let path = meta.path
        let size = meta.formattedSize
        let created = meta.formattedCreationDate ?? "-"
        let modified = meta.formattedModificationDate ?? "-"
        let perms = meta.permissionString ?? "-"
        let owner = meta.ownerAccount ?? "-"
        let group = meta.groupOwnerAccount ?? "-"

        lines.append("| \(path) | \(size) | \(created) | \(modified) | \(perms) | \(owner) | \(group) |")
      }

      return lines.joined(separator: "\n")
    }

    /// Format metadata as CSV
    private func formatAsCSV(_ metadata: [FileMetadata]) -> String {
      var lines: [String] = []

      // Header
      lines.append(
        "Path,Size,Created,Modified,Access Date,Permissions,Owner,Group,File Type,Is Directory,Is Symbolic Link"
      )

      // Rows
      for meta in metadata {
        let fields: [String] = [
          escapeCSVField(meta.path),
          String(meta.size),
          escapeCSVField(meta.formattedCreationDate ?? ""),
          escapeCSVField(meta.formattedModificationDate ?? ""),
          escapeCSVField(meta.formattedAccessDate ?? ""),
          escapeCSVField(meta.permissionString ?? ""),
          escapeCSVField(meta.ownerAccount ?? ""),
          escapeCSVField(meta.groupOwnerAccount ?? ""),
          escapeCSVField(meta.fileType ?? ""),
          String(meta.isDirectory),
          String(meta.isSymbolicLink),
        ]
        lines.append(fields.joined(separator: ","))
      }

      return lines.joined(separator: "\n")
    }

    /// Escape a CSV field according to RFC 4180
    /// Fields containing commas, quotes, or newlines must be wrapped in double quotes
    /// Double quotes are escaped by doubling them
    private func escapeCSVField(_ field: String) -> String {
      // If field contains comma, quote, or newline, wrap in quotes
      if field.contains(",") || field.contains("\"") || field.contains("\n") {
        // Escape quotes by doubling them
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
      }
      return field
    }

    /// Format metadata as JSON
    private func formatAsJSON(_ metadata: [FileMetadata], prettyPrint: Bool) throws -> String {
      let encoder = JSONEncoder()
      if prettyPrint {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      }

      let data = try encoder.encode(metadata)
      guard let json = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode JSON")
      }
      return json
    }
  }
}

extension FileHandle {
  /// Write a string to this file handle
  func write(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    self.write(data)
  }
}
