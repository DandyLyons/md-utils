import Foundation
import JSONSchema
import Testing
@testable import MarkdownUtilitiesCore

@Suite("fm-var fixture contract")
struct FMVarFixtureContractTests {
  @Test
  func `manifest validates against its language-neutral schema`() throws {
    let root = try fixtureRoot()
    let schema = try jsonObject(at: root.appending(path: "schema.json"))
    let manifest = try jsonObject(at: root.appending(path: "manifest.json"))

    let result = try JSONSchema.validate(manifest, schema: schema)

    #expect(result.valid)
    #expect(result.errors?.isEmpty != false)
  }

  @Test
  func `manifest has exact proposal provenance unique cases and safe paths`() throws {
    let root = try fixtureRoot()
    let manifest = try decode(
      FMVarFixtureManifest.self,
      at: root.appending(path: "manifest.json")
    )

    #expect(manifest.schemaVersion == 2)
    #expect(manifest.specification.rfc == "RFC 001 Rev 3")
    #expect(manifest.specification.revision == "18604853843d6edf22aba927c98697f5c956a0f3")
    #expect(manifest.specification.blob == "c612cb01262ac527236dd6dc60b9db5fb46622f5")
    #expect(manifest.specification.document == "PROPOSAL.md")
    #expect(Set(manifest.cases.map(\.id)).count == manifest.cases.count)

    for fixtureCase in manifest.cases {
      #expect(fixtureCase.features.isEmpty == false)
      _ = try safeFixtureURL(fixtureCase.input, beneath: root)
      _ = try safeFixtureURL(fixtureCase.expectation, beneath: root)
    }
  }

  @Test
  func `every expectation validates and decodes into public Core models`() throws {
    let root = try fixtureRoot()
    let schemaObject = try jsonObject(at: root.appending(path: "schema.json"))
    let definitions = try #require(schemaObject["$defs"] as? [String: Any])
    let expectationSchema: [String: Any] = [
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$ref": "#/$defs/expectation",
      "$defs": definitions,
    ]
    let manifest = try decode(
      FMVarFixtureManifest.self,
      at: root.appending(path: "manifest.json")
    )

    for fixtureCase in manifest.cases {
      let expectationURL = try safeFixtureURL(fixtureCase.expectation, beneath: root)
      let expectationObject = try jsonObject(at: expectationURL)
      let validation = try JSONSchema.validate(expectationObject, schema: expectationSchema)
      #expect(validation.valid, "Invalid expectation schema for \(fixtureCase.id)")

      let expectation = try decode(FMVarFixtureExpectation.self, at: expectationURL)
      #expect(expectation.caseID == fixtureCase.id)
      #expect(expectation.statuses.isEmpty == false)
      #expect(expectation.resultMetadata.map(\.status) == expectation.statuses)

      let source = try fixtureSource(
        at: safeFixtureURL(fixtureCase.input, beneath: root)
      )
      let sourceMap = FMVarSourceMap(source: source)
      let ranges = expectation.diagnostics.compactMap(\.range) + expectation.edits.map(\.range)
      for range in ranges {
        #expect(try sourceMap.position(atUTF8Offset: range.start.utf8Offset) == range.start)
        #expect(try sourceMap.position(atUTF8Offset: range.end.utf8Offset) == range.end)
      }
    }
  }

  @Test
  func `initial corpus covers the portable v1 vocabulary`() throws {
    let root = try fixtureRoot()
    let manifest = try decode(
      FMVarFixtureManifest.self,
      at: root.appending(path: "manifest.json")
    )
    let features = Set(manifest.cases.flatMap(\.features))
    let expectedFeatures: Set<String> = [
      "fm-var", "fm-list", "fm-format", "attributes", "effective-format",
      "default-zero", "default-null", "zero-result-fallback", "unresolved-zero-result",
      "null-result-fallback", "unresolved-null-result", "query-argument", "invalid-query",
      "unsupported-query", "query-resource", "nodelist", "multi-node", "scalar", "sequence",
      "mapping", "denied", "wrong-value-shape", "list-shape", "unicode", "escaping", "crlf",
      "utf8", "text-edit", "diagnostic",
    ]

    #expect(expectedFeatures.isSubset(of: features))
    #expect(Set(FMVarReferenceStatus.allCases).isSubset(of: Set(try allStatuses(in: manifest, root: root))))

    let allAttributes = try decode(
      FMVarFixtureExpectation.self,
      at: root.appending(path: "cases/all-v1-attributes/expected.json")
    )
    let formatOptions = try #require(allAttributes.formatDeclarations.first?.options)
    #expect(formatOptions == completeOptions())
    #expect(allAttributes.scalarDeclarations.count == 1)
    #expect(allAttributes.listDeclarations.count == 1)
    #expect(allAttributes.scalarDeclarations.first?.query == "$.published")
    #expect(allAttributes.listDeclarations.first?.query == "$.items")
  }

  private func allStatuses(
    in manifest: FMVarFixtureManifest,
    root: URL
  ) throws -> [FMVarReferenceStatus] {
    try manifest.cases.flatMap { fixtureCase in
      try decode(
        FMVarFixtureExpectation.self,
        at: safeFixtureURL(fixtureCase.expectation, beneath: root)
      ).statuses
    }
  }

  private func fixtureRoot() throws -> URL {
    try #require(Bundle.module.url(forResource: "FMVar", withExtension: nil))
  }

  private func safeFixtureURL(_ path: String, beneath root: URL) throws -> URL {
    guard path.hasPrefix("/") == false else { throw FMVarFixtureTestError.unsafePath(path) }
    let candidate = root.appending(path: path).standardizedFileURL
    let rootPrefix = root.standardizedFileURL.path + "/"
    guard candidate.path.hasPrefix(rootPrefix) else { throw FMVarFixtureTestError.unsafePath(path) }
    guard FileManager.default.fileExists(atPath: candidate.path) else {
      throw FMVarFixtureTestError.missingFile(path)
    }
    return candidate
  }

  private func fixtureSource(at url: URL) throws -> String {
    if url.pathExtension == "json" {
      return try decode(FMVarEncodedFixtureSource.self, at: url).source
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func jsonObject(at url: URL) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return try #require(object as? [String: Any])
  }

  private func decode<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
  }

  private func completeOptions() -> FMVarFormatOptions {
    FMVarFormatOptions(
      locale: "en-US",
      format: "conjunction",
      listStyle: .long,
      calendar: "gregory",
      numberingSystem: "latn",
      timeZone: "UTC",
      hourCycle: "h23",
      hour12: false,
      dateStyle: "long",
      timeStyle: "medium",
      weekday: "long",
      era: "short",
      year: "numeric",
      month: "long",
      day: "2-digit",
      dayPeriod: "long",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      fractionalSecondDigits: 3,
      timeZoneName: "short",
      formatMatcher: "basic"
    )
  }
}

private struct FMVarFixtureManifest: Decodable {
  let schemaVersion: Int
  let specification: Specification
  let cases: [FixtureCase]

  struct Specification: Decodable {
    let repository: String
    let document: String
    let rfc: String
    let revision: String
    let blob: String
  }

  struct FixtureCase: Decodable {
    let id: String
    let summary: String
    let input: String
    let expectation: String
    let features: [String]
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema-version"
    case specification
    case cases
  }
}

private struct FMVarFixtureExpectation: Decodable {
  let caseID: String
  let statuses: [FMVarReferenceStatus]
  let resultMetadata: [FMVarReferenceResultMetadata]
  let scalarDeclarations: [FMVarScalarDeclaration]
  let listDeclarations: [FMVarListDeclaration]
  let formatDeclarations: [FMVarFormatDeclaration]
  let effectiveConfigurations: [FMVarEffectiveConfiguration]
  let diagnostics: [FMVarDiagnostic]
  let edits: [FMVarTextEdit]

  private enum CodingKeys: String, CodingKey {
    case caseID = "case-id"
    case statuses
    case resultMetadata = "result-metadata"
    case scalarDeclarations = "scalar-declarations"
    case listDeclarations = "list-declarations"
    case formatDeclarations = "format-declarations"
    case effectiveConfigurations = "effective-configurations"
    case diagnostics
    case edits
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    caseID = try container.decode(String.self, forKey: .caseID)
    statuses = try container.decode([FMVarReferenceStatus].self, forKey: .statuses)
    resultMetadata = try container.decode(
      [FMVarReferenceResultMetadata].self,
      forKey: .resultMetadata
    )
    scalarDeclarations = try container.decodeIfPresent(
      [FMVarScalarDeclaration].self,
      forKey: .scalarDeclarations
    ) ?? []
    listDeclarations = try container.decodeIfPresent(
      [FMVarListDeclaration].self,
      forKey: .listDeclarations
    ) ?? []
    formatDeclarations = try container.decodeIfPresent(
      [FMVarFormatDeclaration].self,
      forKey: .formatDeclarations
    ) ?? []
    effectiveConfigurations = try container.decodeIfPresent(
      [FMVarEffectiveConfiguration].self,
      forKey: .effectiveConfigurations
    ) ?? []
    diagnostics = try container.decode([FMVarDiagnostic].self, forKey: .diagnostics)
    edits = try container.decode([FMVarTextEdit].self, forKey: .edits)
  }
}

private struct FMVarEncodedFixtureSource: Decodable {
  let source: String
}

private enum FMVarFixtureTestError: Error {
  case unsafePath(String)
  case missingFile(String)
}
