import Foundation
import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownCreationDefinitionTests {
  private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  @Test func templateRoundTripPreservesInlineAndReferencedSchemas() throws {
    for schema in [#"{"inline":false}"#, #"{"ref":"./input.json"}"#] {
      let declaration = try MarkdownCreationTemplate.decode(json("{\"template\":{\"inline\":\"{{ title }}\",\"inputSchema\":\(schema)}}"))
      #expect(declaration.mode == .document)
      #expect(try MarkdownCreationTemplate.decode(declaration.jsonValue) == declaration)
    }
  }

  @Test(arguments: [
    #"{"template":{"inline":"x","ref":"x.knap"}}"#,
    #"{"template":{"ref":""}}"#,
    #"{"template":{"inline":"x","mode":"unknown"}}"#,
    #"{"template":{"inline":"x","inputSchema":{"inline":3}}}"#,
    #"{"template":{"inline":"x","unknown":true}}"#,
  ])
  func malformedTemplatesAreRejected(_ text: String) throws {
    #expect(throws: MarkdownTypeDefinitionError.self) { try MarkdownCreationTemplate.decode(json(text)) }
  }

  @Test func ruleRoundTripPreservesCreationTarget() throws {
    let rule = try MarkdownRuleFile.decode(#"{"name":"Books","types":"book.mdtype.json","creation":{"type":"Book","directory":"./Books/"}}"#, source: "books.mdrule.json")
    #expect(rule.creation?.directory == "./Books/")
    #expect(rule.creation?.type == "Book")
    #expect(try MarkdownRuleFile.decode(rule.encoded(), source: rule.source) == rule)
  }
}
