import Foundation
import JSONSchema
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import md_utils

@Suite("Config scalar validation")
struct ConfigScalarValidationTests {
  @Test(arguments: ["[]", "[1]", "[true,false]", "[{\"nested\":[]}]", "{}", "{\"nested\":[]}", "null", "true", "0", "\"array\""])
  func containerTypesRemainDistinct(_ json: String) throws {
    let value = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    // JSONDecoder independently establishes the fixture's JSON type.
    let isArray = (try? JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))) != nil
    let isObject = (try? JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))) != nil
    #expect(try JSONSchema.validate(value, schema: ["type": "array"]).valid == isArray)
    #expect(try JSONSchema.validate(value, schema: ["type": "object"]).valid == isObject)
  }

  @Test
  func emptyLegacyConfigLoads() throws {
    let project = Path(#filePath).parent().parent().parent().parent() + "tmp/config-empty-\(UUID().uuidString)/"
    try project.mkpath()
    defer { try? project.delete() }
    let configPath = project + "md-utils.json"
    try configPath.write(#"{"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[]}"#)
    #expect(try MdUtilsConfig.load(from: configPath).schemaRules.isEmpty)
  }

  @Test(arguments: ["true", "false", "0", "1", "1.5", "null", "\"true\""])
  func scalarTypesRemainDistinct(_ literal: String) throws {
    let value = try JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed)
    for type in ["boolean", "integer", "number", "null", "string"] {
      let expected: Bool
      switch type {
      case "boolean": expected = literal == "true" || literal == "false"
      case "integer": expected = literal == "0" || literal == "1"
      case "number": expected = literal == "0" || literal == "1" || literal == "1.5"
      case "null": expected = literal == "null"
      default: expected = literal == "\"true\""
      }
      #expect(try JSONSchema.validate(value, schema: ["type": type]).valid == expected)
    }
    #expect(try JSONSchema.validate(value, schema: ["const": true]).valid == (literal == "true"))
    #expect(try JSONSchema.validate(value, schema: ["enum": [false]]).valid == (literal == "false"))
  }

  @Test(arguments: ["true", "false", "0", "1", "\"true\"", "null"])
  func configBooleanChecksAreStrict(_ literal: String) throws {
    let project = Path(#filePath).parent().parent().parent().parent() + "tmp/config-scalars-\(UUID().uuidString)/"
    try project.mkpath()
    defer { try? project.delete() }
    let configPath = project + "md-utils.json"
    try configPath.write("""
      {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[{
        "name":"notes","match":{"paths":["notes/**"]},
        "checks":[{"type":"frontmatterSchema","schema":"note.schema.json","frontmatterRequired":\(literal)}]
      }]}
      """)
    if literal == "true" || literal == "false" {
      let config = try MdUtilsConfig.load(from: configPath)
      let check = try #require(config.schemaRules.first?.checks.first)
      #expect(check.requiresFrontmatter == (literal == "true"))
    } else {
      do {
        _ = try MdUtilsConfig.load(from: configPath)
        Issue.record("Expected a non-boolean frontmatterRequired to fail schema validation")
      } catch {
        #expect(String(describing: error).contains("Project config is invalid"))
        #expect(String(describing: error).contains("0.2.0"))
      }
    }
  }
}
