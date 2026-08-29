import Foundation

/// A location in one immutable UTF-8 source snapshot.
///
/// Offsets are zero-based. Lines and columns are one-based, and columns count UTF-8 bytes.
public struct FMVarSourcePosition: Codable, Equatable, Sendable, Comparable {
  public let utf8Offset: Int
  public let line: Int
  public let column: Int

  public init(utf8Offset: Int, line: Int, column: Int) throws {
    guard utf8Offset >= 0 else { throw FMVarSourceLocationError.negativeOffset(utf8Offset) }
    guard line >= 1 else { throw FMVarSourceLocationError.invalidLine(line) }
    guard column >= 1 else { throw FMVarSourceLocationError.invalidColumn(column) }
    self.utf8Offset = utf8Offset
    self.line = line
    self.column = column
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.utf8Offset != rhs.utf8Offset { return lhs.utf8Offset < rhs.utf8Offset }
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.column < rhs.column
  }

  private enum CodingKeys: String, CodingKey {
    case utf8Offset = "utf8-offset"
    case line
    case column
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      utf8Offset: container.decode(Int.self, forKey: .utf8Offset),
      line: container.decode(Int.self, forKey: .line),
      column: container.decode(Int.self, forKey: .column)
    )
  }
}

/// A half-open range in one immutable UTF-8 source snapshot.
public struct FMVarSourceRange: Codable, Equatable, Sendable, Comparable {
  public let start: FMVarSourcePosition
  public let end: FMVarSourcePosition

  public init(start: FMVarSourcePosition, end: FMVarSourcePosition) throws {
    guard start.utf8Offset <= end.utf8Offset else {
      throw FMVarSourceLocationError.reversedRange(
        start: start.utf8Offset,
        end: end.utf8Offset
      )
    }
    self.start = start
    self.end = end
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.start != rhs.start { return lhs.start < rhs.start }
    return lhs.end < rhs.end
  }

  private enum CodingKeys: String, CodingKey {
    case start
    case end
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      start: container.decode(FMVarSourcePosition.self, forKey: .start),
      end: container.decode(FMVarSourcePosition.self, forKey: .end)
    )
  }
}

/// Converts between UTF-8 offsets and stable line/column diagnostics for one source snapshot.
public struct FMVarSourceMap: Equatable, Sendable {
  private let utf8Bytes: [UInt8]
  private let lineStarts: [Int]

  public init(source: String) {
    let utf8Bytes = Array(source.utf8)
    self.utf8Bytes = utf8Bytes
    var lineStarts = [0]
    for (offset, byte) in utf8Bytes.enumerated() where byte == 0x0A {
      lineStarts.append(offset + 1)
    }
    self.lineStarts = lineStarts
  }

  public var utf8Count: Int { utf8Bytes.count }
  public var lineCount: Int { lineStarts.count }

  /// Returns the position at an offset from zero through the end-of-file offset, inclusive.
  public func position(atUTF8Offset offset: Int) throws -> FMVarSourcePosition {
    guard offset >= 0, offset <= utf8Bytes.count else {
      throw FMVarSourceLocationError.offsetOutOfBounds(offset, utf8Count: utf8Bytes.count)
    }

    var lowerBound = 0
    var upperBound = lineStarts.count
    while lowerBound + 1 < upperBound {
      let middle = (lowerBound + upperBound) / 2
      if lineStarts[middle] <= offset {
        lowerBound = middle
      } else {
        upperBound = middle
      }
    }

    let lineStart = lineStarts[lowerBound]
    return try FMVarSourcePosition(
      utf8Offset: offset,
      line: lowerBound + 1,
      column: offset - lineStart + 1
    )
  }

  /// Returns the UTF-8 offset for a one-based line and UTF-8 byte column.
  public func utf8Offset(line: Int, column: Int) throws -> Int {
    guard line >= 1, line <= lineStarts.count else {
      throw FMVarSourceLocationError.invalidLine(line)
    }
    guard column >= 1 else { throw FMVarSourceLocationError.invalidColumn(column) }

    let lineStart = lineStarts[line - 1]
    let candidate = lineStart + column - 1
    let exclusiveLineEnd = line < lineStarts.count ? lineStarts[line] : utf8Bytes.count + 1
    guard candidate < exclusiveLineEnd, candidate <= utf8Bytes.count else {
      throw FMVarSourceLocationError.positionOutOfBounds(line: line, column: column)
    }
    return candidate
  }

  public func range(fromUTF8Offset start: Int, toUTF8Offset end: Int) throws -> FMVarSourceRange {
    try FMVarSourceRange(
      start: position(atUTF8Offset: start),
      end: position(atUTF8Offset: end)
    )
  }
}

/// Errors produced while creating or translating fm-var source locations.
public enum FMVarSourceLocationError: Error, Equatable, Sendable, CustomStringConvertible {
  case negativeOffset(Int)
  case invalidLine(Int)
  case invalidColumn(Int)
  case offsetOutOfBounds(Int, utf8Count: Int)
  case positionOutOfBounds(line: Int, column: Int)
  case reversedRange(start: Int, end: Int)

  public var description: String {
    switch self {
    case .negativeOffset(let offset):
      return "UTF-8 offset must be non-negative: \(offset)"
    case .invalidLine(let line):
      return "Line must identify an existing one-based source line: \(line)"
    case .invalidColumn(let column):
      return "Column must be one-based: \(column)"
    case .offsetOutOfBounds(let offset, let utf8Count):
      return "UTF-8 offset \(offset) is outside 0...\(utf8Count)"
    case .positionOutOfBounds(let line, let column):
      return "Line \(line), column \(column) is outside the source"
    case .reversedRange(let start, let end):
      return "Half-open source range is reversed: \(start)..<\(end)"
    }
  }
}
