import Foundation
import MarkdownUtilitiesCore
import Testing
@testable import MarkdownUtilitiesTemplates

struct CreationTemplateTests {
  private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
  }

  @Test func documentOwnsFrontmatterAndVariables() async throws {
    let input = try json(#"{"title":"Dune: a book","tags":["fiction"],"done":false,"count":0,"nothing":null}"#)
    let result = try await MarkdownTemplateRenderer().render(
      template: "---\n{{ title | yaml_property:'title' }}\n{{ tags | yaml_property:'tags' }}\n---\n{{ title | h1 }}",
      variables: input,
    )
    #expect(result.source.contains("Dune: a book"))
    #expect(result.document.frontMatterFormat == .yaml)
    #expect(result.document.body.contains("# Dune: a book"))
    #expect(result.warnings.isEmpty)
  }

  @Test(arguments: ["[]", "1", "false", "null", #""text""#])
  func nonObjectRootFails(_ input: String) throws {
    #expect(throws: MarkdownTemplateError.self) {
      try TemplateInputDefaults.prepare(json(input), schema: nil)
    }
  }

  @Test func defaultsPreserveSuppliedValuesAndOnlyCreateDeclaredParents() throws {
    let schema = try json(#"{"properties":{"absent":{"default":"new"},"null":{"default":7},"zero":{"default":7},"empty":{"default":"other"},"false":{"default":true},"optional":{"properties":{"x":{"default":1}}},"created":{"default":{},"properties":{"x":{"default":1}}}}}"#)
    let result = try TemplateInputDefaults.prepare(json(#"{"null":null,"zero":0,"empty":"","false":false}"#), schema: schema)
    #expect(result == (try json(#"{"null":null,"zero":0,"empty":"","false":false,"absent":"new","created":{"x":1}}"#)))
  }

  @Test func arraysReceiveDefaultsWithoutInventingItems() throws {
    let schema = try json(#"{"properties":{"items":{"items":{"properties":{"status":{"default":"unread"}}}}}}"#)
    let result = try TemplateInputDefaults.prepare(json(#"{"items":[{}, {"status":"read"}]}"#), schema: schema)
    #expect(result == (try json(#"{"items":[{"status":"unread"},{"status":"read"}]}"#)))
    #expect(try TemplateInputDefaults.prepare(json(#"{"items":[]}"#), schema: schema) == json(#"{"items":[]}"#))
  }

  @Test func conflictsDoNotDependOnOrder() throws {
    for values in [[1, 2], [2, 1]] {
      let schema = try json("{\"allOf\":[{\"properties\":{\"x\":{\"default\":\(values[0])}}},{\"properties\":{\"x\":{\"default\":\(values[1])}}}]}")
      #expect(throws: MarkdownTemplateError.self) { try TemplateInputDefaults.prepare(.object([:]), schema: schema) }
      #expect(try TemplateInputDefaults.prepare(json(#"{"x":3}"#), schema: schema) == json(#"{"x":3}"#))
    }
  }

  @Test func conditionalDefaultsFollowUnconditionalDefaults() throws {
    let schema = try json(#"{"properties":{"format":{"default":"ebook"}},"if":{"required":["format"],"properties":{"format":{"const":"ebook"}}},"then":{"properties":{"delivery":{"default":"download"}}},"else":{"properties":{"delivery":{"default":"shipping"}}}}"#)
    #expect(try TemplateInputDefaults.prepare(.object([:]), schema: schema) == json(#"{"format":"ebook","delivery":"download"}"#))
    #expect(try TemplateInputDefaults.prepare(json(#"{"format":"hardcover"}"#), schema: schema) == json(#"{"format":"hardcover","delivery":"shipping"}"#))
  }

  @Test func ambiguousAlternativesAndInvalidDefaultsFail() throws {
    let ambiguous = try json(#"{"anyOf":[{"properties":{"x":{"default":1}}},{"properties":{"x":{"default":2}}}]}"#)
    #expect(throws: MarkdownTemplateError.self) { try TemplateInputDefaults.prepare(.object([:]), schema: ambiguous) }
    let invalid = try json(#"{"properties":{"x":{"type":"integer","default":"invalid"}}}"#)
    #expect(throws: MarkdownTemplateError.self) { try TemplateInputDefaults.prepare(.object([:]), schema: invalid) }
  }

  @Test func localReferencesAndRecursiveExpansion() throws {
    let schema = try json(##"{"$defs":{"value":{"default":"Dune"}},"properties":{"title":{"$ref":"#/$defs/value"}}}"##)
    #expect(try TemplateInputDefaults.prepare(.object([:]), schema: schema) == json(#"{"title":"Dune"}"#))
    let recursive = try json(##"{"$defs":{"node":{"default":{},"properties":{"child":{"$ref":"#/$defs/node"}}}},"properties":{"node":{"$ref":"#/$defs/node"}}}"##)
    #expect(throws: MarkdownTemplateError.self) { try TemplateInputDefaults.prepare(.object([:]), schema: recursive) }
  }

  @Test func explicitBodyModeSerializesFrontmatter() async throws {
    let result = try await MarkdownTemplateRenderer().render(template: "{{ data }}",
      variables: json(#"{"frontmatter":{"title":"Dune"},"data":"Body"}"#), mode: .body)
    #expect(result.document.frontMatterFormat == .yaml)
    #expect(result.document.body == "Body")
  }

  @Test func siblingUnconditionalDefaultsPrecedeConditions() throws {
    let schema = try json(#"{"allOf":[{"if":{"required":["format"],"properties":{"format":{"const":"ebook"}}},"then":{"properties":{"delivery":{"default":"download"}}},"else":{"properties":{"delivery":{"default":"shipping"}}}},{"properties":{"format":{"default":"ebook"}}}]}"#)
    #expect(try TemplateInputDefaults.prepare(.object([:]), schema: schema) == json(#"{"format":"ebook","delivery":"download"}"#))
  }

  @Test func propertyAndCompositionDefaultConflictsAreDetected() throws {
    let schema = try json(#"{"properties":{"x":{"default":1}},"allOf":[{"properties":{"x":{"default":2}}}]}"#)
    #expect(throws: MarkdownTemplateError.self) { try TemplateInputDefaults.prepare(.object([:]), schema: schema) }
  }

  @Test func overlappingAnyOfWithoutDifferentDefaultsValidatesNormally() throws {
    let schema = try json(#"{"anyOf":[{"type":"object"},{"properties":{"title":{"type":"string"}}}]}"#)
    #expect(try TemplateInputDefaults.prepare(.object([:]), schema: schema) == .object([:]))
  }
}
