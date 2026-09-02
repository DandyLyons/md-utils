import DynamicJSON
import Testing

@Suite("DynamicJSON integration")
struct DynamicJSONIntegrationTests {
  @Test
  func `RFC 9535 API parses and evaluates an ordered nodelist`() throws {
    let value: JSON = [
      "items": [
        ["title": "First"],
        ["title": "Second"],
      ]
    ]
    let path = try JSONPath(query: "$.items[*].title", strict: true)

    let results = try value.query(path)

    #expect(results.map(\.value) == [.string("First"), .string("Second")])
    #expect(results.map(\.location.description) == [
      "$['items'][0]['title']",
      "$['items'][1]['title']",
    ])
  }
}
