import ArgumentParser
import Foundation
import MarkdownUtilitiesCore

/// Reads bounded file-list input and applies the CLI's shared encoding rules.
enum CLIFileListInput {
  static func parse(_ data: Data, from path: String, nulDelimited: Bool) throws -> [String] {
    let source = path == "-" ? "stdin" : path
    guard let text = UTF8Text.decode(data) else {
      throw ValidationError("File list from \(source) is not valid UTF-8")
    }
    var input = Substring(text)
    do {
      return try MarkdownQueryFileListParser(nulDelimited: nulDelimited).parse(&input)
    } catch {
      throw ValidationError("File list from \(source): \(error.localizedDescription)")
    }
  }

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
