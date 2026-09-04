import Foundation
import MarkdownUtilitiesCore
@testable import MarkdownUtilities
import Testing

@Suite("fm-var source orchestration")
struct FMVarSourceResolverTests {
  @Test(arguments: [nil, "", "page.md", "./page.md", "https://example.test/docs/page.md"] as [String?])
  func `sources resolving to the containing identifier reuse its snapshot`(
    reference: String?
  ) async throws {
    let provider = RecordingResourceProvider(result: .failure(.init(
      reason: .denied,
      message: "Provider must not be called"
    )))
    let result = await FMVarSourceResolver().resolve(
      reference: reference,
      containingResource: markdownResource(),
      provider: provider
    )

    #expect(result.status == .resolved)
    #expect(result.identifier?.rawValue == "https://example.test/docs/page.md")
    #expect(await provider.recordedRequests().isEmpty)
    #expect(try member(named: "title", in: result).value == .string("Containing"))
  }

  @Test
  func `self is an ordinary relative resource and invokes provider once`() async throws {
    let external = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/docs/self"),
      bytes: Data("external".utf8),
      contentType: "application/yaml"
    )
    let provider = RecordingResourceProvider(result: .resource(external))
    let result = await FMVarSourceResolver().resolve(
      reference: "self",
      containingResource: markdownResource(),
      provider: provider
    )
    let requests = await provider.recordedRequests()

    #expect(result.status == .resolved)
    #expect(result.queryArgument?.root.value == .string("external"))
    #expect(requests == [FMVarResourceRequest(
      reference: "self",
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/docs/self")
    )])
  }

  @Test
  func `recognized content type wins over conflicting extension`() async throws {
    let yamlAtMarkdownPath = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/data.MD?download=1"),
      bytes: Data("[one, two]".utf8),
      contentType: " Application/YAML ; charset=utf-8 "
    )
    let provider = RecordingResourceProvider(result: .resource(yamlAtMarkdownPath))
    let result = await FMVarSourceResolver().resolve(
      reference: "../data.MD?download=1",
      containingResource: markdownResource(),
      provider: provider
    )

    #expect(result.status == .resolved)
    #expect(result.resourceKind == .yaml)
    #expect(result.queryArgument.map { kind(of: $0.root.value) } == "array")
  }

  @Test(arguments: [
    "application/yaml", "text/yaml", "application/x-yaml", "text/x-yaml",
    "APPLICATION/YAML; charset=UTF-8",
  ])
  func `all recognized YAML media types are case insensitive and ignore parameters`(
    contentType: String
  ) async {
    let resource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/data.bin"),
      bytes: Data("value: true".utf8),
      contentType: contentType
    )
    let result = await FMVarSourceResolver().resolve(
      reference: "../data.bin",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(resource))
    )

    #expect(result.status == .resolved)
    #expect(result.resourceKind == .yaml)
  }

  @Test(arguments: [nil, "", "application/octet-stream", "text/plain; charset=utf-8"] as [String?])
  func `absent blank and generic types fall back to case insensitive path extension`(
    contentType: String?
  ) async {
    let resource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/DATA.YML?revision=2"),
      bytes: Data("name: projected".utf8),
      contentType: contentType
    )
    let result = await FMVarSourceResolver().resolve(
      reference: "../DATA.YML?revision=2",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(resource))
    )

    #expect(result.status == .resolved)
    #expect(result.resourceKind == .yaml)
  }

  @Test
  func `explicit unknown type is unsupported even with recognized extension`() async {
    let resource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/data.yaml"),
      bytes: Data("name: ignored".utf8),
      contentType: "application/json"
    )
    let result = await FMVarSourceResolver().resolve(
      reference: "../data.yaml",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(resource))
    )

    #expect(result.status == .failed)
    #expect(result.failure?.reason == .unsupportedResourceKind)
    #expect(result.failure?.code == .unsupportedResourceKind)
  }

  @Test
  func `provider substitution is a typed unsupported source`() async {
    let substituted = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://other.test/data.yaml"),
      bytes: Data("value: ignored".utf8),
      contentType: "application/yaml"
    )
    let provider = RecordingResourceProvider(result: .resource(substituted))
    let result = await FMVarSourceResolver().resolve(
      reference: "../data.yaml",
      containingResource: markdownResource(),
      provider: provider
    )

    #expect(result.failure?.reason == .unsupportedSource)
    #expect(result.failure?.code == .unsupportedSource)
    #expect(result.failure?.identifier?.rawValue == "https://example.test/data.yaml")
    #expect(await provider.recordedRequests().count == 1)
  }

  @Test
  func `unrecognized generic extension has a typed resource kind failure`() async {
    let resource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/data.txt?raw=1"),
      bytes: Data("value: ignored".utf8),
      contentType: "text/plain"
    )
    let result = await FMVarSourceResolver().resolve(
      reference: "../data.txt?raw=1",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(resource))
    )

    #expect(result.failure?.reason == .unsupportedResourceKind)
    #expect(result.failure?.identifier == resource.identifier)
  }

  @Test
  func `Markdown extracts exact YAML content and enforces mapping root`() async throws {
    let valid = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/source.markdown"),
      bytes: Data("---\nvalue: 1.2300\n---\n<fm-var>ignored</fm-var>".utf8),
      contentType: "text/markdown"
    )
    let validResult = await FMVarSourceResolver().resolve(
      reference: "../source.markdown",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(valid))
    )
    let value = try member(named: "value", in: validResult)
    #expect(value.value == .number(1.23))
    #expect(value.sourceScalar?.content == "1.2300")

    let sequence = FMVarResource(
      identifier: valid.identifier,
      bytes: Data("---\n[one, two]\n---\n".utf8),
      contentType: valid.contentType
    )
    let invalidResult = await FMVarSourceResolver().resolve(
      reference: "../source.markdown",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(sequence))
    )
    #expect(invalidResult.failure?.code == .invalidYAMLFrontmatterRoot)
    #expect(invalidResult.failure?.queryArgumentFailure?.reason == .markdownRootNotMapping)
  }

  @Test
  func `empty Markdown frontmatter projects an empty mapping`() async throws {
    let resource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/empty.md"),
      bytes: Data("---\n\n---\nBody".utf8),
      contentType: "text/markdown"
    )
    let result = await FMVarSourceResolver().resolve(
      reference: "../empty.md",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(resource))
    )
    let root = try #require(result.queryArgument?.root)
    guard case .object(let members) = root.value else {
      Issue.record("Expected empty frontmatter to project an object")
      return
    }
    #expect(members.isEmpty)
  }

  @Test(arguments: [
    ("missing", "# Body", FMVarDiagnosticCode.missingYAMLFrontmatter),
    ("TOML", "+++\nname = 'value'\n+++\n", .unsupportedFrontmatterFormat),
    ("unclosed", "---\nname: value\n", .malformedYAMLFrontmatter),
    ("CRLF", "---\r\nname: value\r\n---\r\n", .missingYAMLFrontmatter),
  ])
  func `Markdown envelope failures are stable`(
    name: String,
    source: String,
    code: FMVarDiagnosticCode
  ) async {
    let resource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/external.md"),
      bytes: Data(source.utf8),
      contentType: "text/markdown"
    )
    let result = await FMVarSourceResolver().resolve(
      reference: "../external.md",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(resource))
    )
    #expect(result.failure?.code == code, Comment(rawValue: name))
  }

  @Test
  func `strict UTF-8 accepts one BOM and rejects malformed bytes`() async throws {
    let bomBytes = Data([0xEF, 0xBB, 0xBF]) + Data("value: yes".utf8)
    let bomResource = FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/data.yaml"),
      bytes: bomBytes,
      contentType: "application/yaml"
    )
    let bomResult = await FMVarSourceResolver().resolve(
      reference: "../data.yaml",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(bomResource))
    )
    #expect(try member(named: "value", in: bomResult).value == .string("yes"))

    let invalidResource = FMVarResource(
      identifier: bomResource.identifier,
      bytes: Data([0xFF]),
      contentType: bomResource.contentType
    )
    let invalidResult = await FMVarSourceResolver().resolve(
      reference: "../data.yaml",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(invalidResource))
    )
    #expect(invalidResult.failure?.reason == .unreadableSource)
    #expect(invalidResult.failure?.code == .unreadableSource)

    let duplicateBOMResource = FMVarResource(
      identifier: bomResource.identifier,
      bytes: Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + Data("value: yes".utf8),
      contentType: bomResource.contentType
    )
    let duplicateBOMResult = await FMVarSourceResolver().resolve(
      reference: "../data.yaml",
      containingResource: markdownResource(),
      provider: RecordingResourceProvider(result: .resource(duplicateBOMResource))
    )
    #expect(duplicateBOMResult.failure?.reason == .unreadableSource)
  }

  @Test(arguments: [
    (FMVarResourceAccessFailureReason.denied, FMVarSourceFailureReason.accessDenied, FMVarDiagnosticCode.sourceAccessDenied),
    (.outsideAllowedRoot, .outsideAllowedRoot, .sourceOutsideAllowedRoot),
    (.symlinkEscape, .symlinkEscape, .sourceSymlinkEscape),
    (.unsupported, .unsupportedSource, .unsupportedSource),
    (.notFound, .sourceNotFound, .sourceNotFound),
    (.unreadable, .unreadableSource, .unreadableSource),
    (.excessiveSize, .excessiveSourceSize, .excessiveSourceSize),
  ])
  func `provider failures remain typed`(
    accessReason: FMVarResourceAccessFailureReason,
    sourceReason: FMVarSourceFailureReason,
    code: FMVarDiagnosticCode
  ) async {
    let provider = RecordingResourceProvider(result: .failure(.init(
      reason: accessReason,
      message: "host detail"
    )))
    let result = await FMVarSourceResolver().resolve(
      reference: "../external.yaml",
      containingResource: markdownResource(),
      provider: provider
    )

    #expect(result.failure?.reason == sourceReason)
    #expect(result.failure?.code == code)
    #expect(result.failure?.message == "host detail")
    #expect(await provider.recordedRequests().count == 1)
  }

  private func markdownResource() -> FMVarResource {
    FMVarResource(
      identifier: FMVarResourceIdentifier(rawValue: "https://example.test/docs/page.md"),
      bytes: Data("---\ntitle: Containing\n---\nBody".utf8),
      contentType: "text/markdown"
    )
  }

  private func member(named name: String, in result: FMVarSourceResolution) throws -> FMVarQueryNode {
    let root = try #require(result.queryArgument?.root)
    guard case .object(let members) = root.value else {
      Issue.record("Expected an object root")
      throw TestLookupError.wrongRoot
    }
    return try #require(members.first(where: { $0.name == name })?.node)
  }

  private func kind(of value: FMVarQueryValue) -> String {
    switch value {
    case .null: "null"
    case .boolean: "boolean"
    case .integer: "integer"
    case .number: "number"
    case .string: "string"
    case .array: "array"
    case .object: "object"
    }
  }
}

private actor RecordingResourceProvider: FMVarResourceProvider {
  private let result: FMVarResourceProviderResult
  private var requests: [FMVarResourceRequest] = []

  init(result: FMVarResourceProviderResult) {
    self.result = result
  }

  func resource(for request: FMVarResourceRequest) async -> FMVarResourceProviderResult {
    requests.append(request)
    return result
  }

  func recordedRequests() -> [FMVarResourceRequest] {
    requests
  }
}

private enum TestLookupError: Error {
  case wrongRoot
}
