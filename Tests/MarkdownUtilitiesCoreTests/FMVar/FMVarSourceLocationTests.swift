import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("fm-var source locations")
struct FMVarSourceLocationTests {
  @Test
  func `round trips every UTF-8 offset across Unicode LF and CRLF`() throws {
    let source = "é\nA\r\n🙂z"
    let sourceMap = FMVarSourceMap(source: source)

    for offset in 0...source.utf8.count {
      let position = try sourceMap.position(atUTF8Offset: offset)
      #expect(try sourceMap.utf8Offset(line: position.line, column: position.column) == offset)
    }

    #expect(try sourceMap.position(atUTF8Offset: 0) == position(0, 1, 1))
    #expect(try sourceMap.position(atUTF8Offset: 2) == position(2, 1, 3))
    #expect(try sourceMap.position(atUTF8Offset: 3) == position(3, 2, 1))
    #expect(try sourceMap.position(atUTF8Offset: 5) == position(5, 2, 3))
    #expect(try sourceMap.position(atUTF8Offset: 6) == position(6, 3, 1))
    #expect(try sourceMap.position(atUTF8Offset: 7) == position(7, 3, 2))
    #expect(sourceMap.lineCount == 3)
  }

  @Test
  func `empty source exposes one line and its EOF position`() throws {
    let sourceMap = FMVarSourceMap(source: "")

    #expect(sourceMap.utf8Count == 0)
    #expect(sourceMap.lineCount == 1)
    #expect(try sourceMap.position(atUTF8Offset: 0) == position(0, 1, 1))
    #expect(try sourceMap.utf8Offset(line: 1, column: 1) == 0)
  }

  @Test
  func `rejects invalid offsets positions and reversed ranges`() throws {
    let sourceMap = FMVarSourceMap(source: "a\nb")

    #expect(throws: FMVarSourceLocationError.self) {
      try sourceMap.position(atUTF8Offset: -1)
    }
    #expect(throws: FMVarSourceLocationError.self) {
      try sourceMap.position(atUTF8Offset: 4)
    }
    #expect(throws: FMVarSourceLocationError.self) {
      try sourceMap.utf8Offset(line: 0, column: 1)
    }
    #expect(throws: FMVarSourceLocationError.self) {
      try sourceMap.utf8Offset(line: 1, column: 3)
    }
    #expect(throws: FMVarSourceLocationError.self) {
      try FMVarSourceRange(start: position(2, 2, 1), end: position(1, 1, 2))
    }
  }

  @Test
  func `source locations use stable kebab-case JSON keys`() throws {
    let value = try position(4, 2, 1)
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Int]
    )

    #expect(object == ["utf8-offset": 4, "line": 2, "column": 1])
  }

  @Test
  func `decoding rejects invalid positions and reversed ranges`() throws {
    let decoder = JSONDecoder()
    let invalidPosition = Data(#"{"utf8-offset":-1,"line":1,"column":1}"#.utf8)
    let reversedRange = Data(
      #"{"start":{"utf8-offset":2,"line":1,"column":3},"end":{"utf8-offset":1,"line":1,"column":2}}"#.utf8
    )

    #expect(throws: FMVarSourceLocationError.self) {
      try decoder.decode(FMVarSourcePosition.self, from: invalidPosition)
    }
    #expect(throws: FMVarSourceLocationError.self) {
      try decoder.decode(FMVarSourceRange.self, from: reversedRange)
    }
  }

  private func position(_ offset: Int, _ line: Int, _ column: Int) throws -> FMVarSourcePosition {
    try FMVarSourcePosition(utf8Offset: offset, line: line, column: column)
  }
}
