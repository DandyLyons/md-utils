import Foundation

/// A location in one immutable UTF-8 source snapshot.
///
/// Offsets are zero-based. Lines and columns are one-based, and columns count UTF-8 bytes.
/// See <doc:FMVarModels> for the complete source-coordinate contract.
public struct FMVarSourcePosition: Codable, Equatable, Sendable, Comparable {
  /// Zero-based byte offset in the source snapshot's UTF-8 representation.
  public let utf8Offset: Int
  /// One-based line containing the offset.
  public let line: Int
  /// One-based UTF-8 byte column within ``line``.
  public let column: Int

  /// Creates a validated position in a UTF-8 source snapshot.
  ///
  /// This initializer validates the coordinate components individually. Use
  /// ``FMVarSourceMap/position(atUTF8Offset:)`` to confirm that an offset exists in a specific
  /// snapshot and to derive its matching line and column.
  ///
  /// - Parameters:
  ///   - utf8Offset: Zero-based UTF-8 byte offset.
  ///   - line: One-based line number.
  ///   - column: One-based UTF-8 byte column.
  /// - Throws: ``FMVarSourceLocationError`` when any component is outside its basic domain.
  public init(utf8Offset: Int, line: Int, column: Int) throws {
    guard utf8Offset >= 0 else { throw FMVarSourceLocationError.negativeOffset(utf8Offset) }
    guard line >= 1 else { throw FMVarSourceLocationError.invalidLine(line) }
    guard column >= 1 else { throw FMVarSourceLocationError.invalidColumn(column) }
    self.utf8Offset = utf8Offset
    self.line = line
    self.column = column
  }

  /// Orders positions by byte offset, then line and column as deterministic tie-breakers.
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

  /// Decodes and validates a position from its structured-output representation.
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
///
/// The start position is included and the end position is excluded. An empty range has equal
/// start and end offsets, and the end may identify the snapshot's end-of-file position.
public struct FMVarSourceRange: Codable, Equatable, Sendable, Comparable {
  /// Inclusive start of the range.
  public let start: FMVarSourcePosition
  /// Exclusive end of the range.
  public let end: FMVarSourcePosition

  /// Creates a half-open range whose start does not follow its end.
  ///
  /// - Throws: ``FMVarSourceLocationError/reversedRange(start:end:)`` when `start` follows `end`.
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

  /// Orders ranges by their start and then their end position.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.start != rhs.start { return lhs.start < rhs.start }
    return lhs.end < rhs.end
  }

  private enum CodingKeys: String, CodingKey {
    case start
    case end
  }

  /// Decodes a range and validates its half-open ordering invariant.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      start: container.decode(FMVarSourcePosition.self, forKey: .start),
      end: container.decode(FMVarSourcePosition.self, forKey: .end)
    )
  }
}

/// Converts between UTF-8 offsets and stable line/column diagnostics for one source snapshot.
///
/// The map retains only UTF-8 bytes and line starts. LF begins a new line; a preceding CR remains
/// part of the previous line's byte columns. See <doc:FMVarModels> for examples.
public struct FMVarSourceMap: Equatable, Sendable {
  private let utf8Bytes: [UInt8]
  private let lineStarts: [Int]

  /// Creates a coordinate map for an immutable source snapshot.
  ///
  /// - Parameter source: Source text whose UTF-8 representation defines all returned offsets.
  public init(source: String) {
    let utf8Bytes = Array(source.utf8)
    self.utf8Bytes = utf8Bytes
    var lineStarts = [0]
    for (offset, byte) in utf8Bytes.enumerated() where byte == 0x0A {
      lineStarts.append(offset + 1)
    }
    self.lineStarts = lineStarts
  }

  /// Number of UTF-8 bytes in the mapped source snapshot.
  public var utf8Count: Int { utf8Bytes.count }
  /// Number of source lines, including the single empty line in an empty snapshot.
  public var lineCount: Int { lineStarts.count }

  /// Returns the position at an offset from zero through the end-of-file offset, inclusive.
  ///
  /// - Parameter offset: Zero-based UTF-8 byte offset.
  /// - Returns: The offset paired with its one-based line and UTF-8 byte column.
  /// - Throws: ``FMVarSourceLocationError/offsetOutOfBounds(_:utf8Count:)`` when the offset is
  ///   outside the snapshot.
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
  ///
  /// - Parameters:
  ///   - line: Existing one-based source line.
  ///   - column: One-based UTF-8 byte column, including the line-ending byte position.
  /// - Returns: The corresponding zero-based UTF-8 offset.
  /// - Throws: ``FMVarSourceLocationError`` when the coordinate is outside the snapshot.
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

  /// Creates a validated half-open range from two UTF-8 offsets in this snapshot.
  ///
  /// - Parameters:
  ///   - start: Included zero-based UTF-8 offset.
  ///   - end: Excluded zero-based UTF-8 offset.
  /// - Returns: A range with derived line and column positions.
  /// - Throws: ``FMVarSourceLocationError`` when an offset is outside the snapshot or the range
  ///   is reversed.
  public func range(fromUTF8Offset start: Int, toUTF8Offset end: Int) throws -> FMVarSourceRange {
    try FMVarSourceRange(
      start: position(atUTF8Offset: start),
      end: position(atUTF8Offset: end)
    )
  }
}

/// Errors produced while creating or translating fm-var source locations.
public enum FMVarSourceLocationError: Error, Equatable, Sendable, CustomStringConvertible {
  /// A standalone position used a negative UTF-8 offset.
  case negativeOffset(Int)
  /// A line was not a valid one-based line in the relevant context.
  case invalidLine(Int)
  /// A column was less than one.
  case invalidColumn(Int)
  /// An offset fell outside a mapped source snapshot.
  case offsetOutOfBounds(Int, utf8Count: Int)
  /// A line and column pair fell outside a mapped source snapshot.
  case positionOutOfBounds(line: Int, column: Int)
  /// A half-open range started after its end.
  case reversedRange(start: Int, end: Int)

  /// Human-readable explanation of the invalid coordinate or range.
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
