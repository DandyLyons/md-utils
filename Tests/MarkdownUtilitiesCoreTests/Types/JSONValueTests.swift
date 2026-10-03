import Foundation
import MarkdownUtilitiesCore
import Testing

@Suite("JSON value scalar preservation")
struct JSONValueTests {
  @Test
  func foundationScalarsMatchCodableScalars() throws {
    let data = Data(#"{"true":true,"false":false,"zero":0,"one":1,"fraction":1.5,"array":[true,false,0,1],"null":null}"#.utf8)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let converted = try JSONValue(any: JSONSerialization.jsonObject(with: data))
    #expect(converted == decoded)
    #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(converted)) == decoded)
  }

  @Test
  func nativeScalarsAndIntegerLimitsArePreserved() throws {
    #expect(try JSONValue(any: true) == .boolean(true))
    #expect(try JSONValue(any: false) == .boolean(false))
    #expect(try JSONValue(any: 0) == .integer(0))
    #expect(try JSONValue(any: 1) == .integer(1))
    #expect(try JSONValue(any: 1.5) == .number(1.5))
    for integer in [Int.min, Int.max] {
      #expect(try JSONValue(any: integer) == .integer(integer))
      let data = Data(String(integer).utf8)
      #expect(try JSONValue(any: JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) == .integer(integer))
    }
  }
}
