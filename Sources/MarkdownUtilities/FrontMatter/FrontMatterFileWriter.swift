import Foundation
import PathKit

/// Errors produced while safely replacing a frontmatter-bearing text file.
public enum FrontMatterFileWriteError: LocalizedError, Sendable {
  /// The file no longer matches the source snapshot used to construct the edit.
  case revisionMismatch

  /// The updated Swift string could not be represented as UTF-8.
  case invalidUTF8

  /// A user-facing explanation of the failed safety check.
  public var errorDescription: String? {
    switch self {
    case .revisionMismatch:
      return "file changed since it was read; retry the command"
    case .invalidUTF8:
      return "updated content is not valid UTF-8"
    }
  }
}

/// Performs revision-checked atomic replacement for frontmatter text mutations.
///
/// The writer compares the latest text with the exact snapshot used to construct
/// an edit. A mismatch is never retried implicitly. A successful comparison is
/// followed by an atomic replacement, though uncoordinated external writers can
/// still race between the final comparison and replacement.
public enum FrontMatterFileWriter {
  /// Reads one exact UTF-8 snapshot without discarding a leading byte-order mark.
  public static func readSnapshot(from path: Path) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path.absolute().string))
    guard String(data: data, encoding: .utf8) != nil else {
      throw FrontMatterFileWriteError.invalidUTF8
    }
    return String(decoding: data, as: UTF8.self)
  }

  /// Replaces a file only if it still matches the snapshot used to build the edit.
  ///
  /// - Parameters:
  ///   - content: The complete updated UTF-8 text.
  ///   - path: The native filesystem path to replace.
  ///   - expectedSource: The exact source snapshot used to construct `content`.
  /// - Throws: ``FrontMatterFileWriteError/revisionMismatch`` if the latest text
  ///   differs, ``FrontMatterFileWriteError/invalidUTF8`` if conversion fails, or
  ///   an underlying filesystem error if the read or atomic replacement fails.
  public static func write(
    _ content: String,
    to path: Path,
    expectedSource: String
  ) throws {
    let latest = try readSnapshot(from: path)
    guard latest == expectedSource else {
      throw FrontMatterFileWriteError.revisionMismatch
    }
    guard let data = content.data(using: .utf8) else {
      throw FrontMatterFileWriteError.invalidUTF8
    }
    try data.write(to: URL(fileURLWithPath: path.absolute().string), options: .atomic)
  }
}
