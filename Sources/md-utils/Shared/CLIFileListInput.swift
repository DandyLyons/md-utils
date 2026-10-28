import ArgumentParser
import Foundation
import MarkdownUtilitiesCore

/// Reads complete file-list input, including short pipe reads, without allocating
/// an unbounded stdin/file buffer before applying the shared input budget.
enum CLIFileListInput {
  static func read(_ path: String) throws -> Data {
    let handle = path == "-" ? FileHandle.standardInput : try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { if path != "-" { try? handle.close() } }
    var data = Data()
    while true {
      try Task.checkCancellation()
      let remaining = DocumentReadBudgets.sourceBytes - data.count
      let chunk = try handle.read(upToCount: min(65_536, remaining + 1)) ?? Data()
      if chunk.isEmpty { return data }
      guard chunk.count <= remaining else { throw ValidationError("File list exceeds the 64 MiB input budget") }
      data.append(chunk)
    }
  }
}
