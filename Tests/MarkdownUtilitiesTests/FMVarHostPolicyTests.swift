import Foundation
import MarkdownUtilitiesCore
@testable import MarkdownUtilities
import Testing

@Suite("fm-var native host policy")
struct FMVarHostPolicyTests {
  @Test
  func `policy requires an existing local directory and representable limit`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }

    #expect(throws: FMVarHostPolicyError.self) {
      try FMVarHostPolicy(allowedRoot: URL(string: "https://example.test/content/") ?? fixture.root)
    }
    #expect(throws: FMVarHostPolicyError.self) {
      try FMVarHostPolicy(allowedRoot: fixture.root.appendingPathComponent("missing/"))
    }
    #expect(throws: FMVarHostPolicyError.self) {
      try FMVarHostPolicy(allowedRoot: fixture.root, maximumSourceByteCount: UInt64(Int.max))
    }
  }

  @Test
  func `policy exposes bounded defaults and only RFC functions`() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let policy = try FMVarHostPolicy(allowedRoot: fixture.root)

    #expect(policy.maximumSourceByteCount == 8 * 1_024 * 1_024)
    #expect(policy.jsonPathLimits == FMVarJSONPathLimits())
    #expect(policy.availableJSONPathFunctions == Set(FMVarJSONPathFunction.allCases))

    let root = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$"),
      value: .array([])
    )
    let evaluation = policy.makeJSONPathEvaluator().evaluate(
      query: "$[?values(@)]",
      argument: FMVarQueryArgument(root: root)
    )
    #expect(evaluation.status == .unsupportedCapability)
    #expect(evaluation.failure?.functionName == "values")
  }

  @Test
  func `containing and external resources load inside allowed root`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let document = fixture.root.appendingPathComponent("docs/page.md")
    let source = fixture.root.appendingPathComponent("data/value.yaml")
    try fixture.write("---\ntitle: Page\n---\n", to: document)
    try fixture.write("answer: 42\n", to: source)
    let provider = FileFMVarResourceProvider(
      policy: try FMVarHostPolicy(allowedRoot: fixture.root)
    )

    let containing = provider.containingResource(at: document)
    let containingResource = try #require(containing.resource)
    #expect(containingResource.identifier.rawValue == document.absoluteURL.absoluteString)
    #expect(containingResource.contentType == "text/markdown")

    let resolution = await FMVarSourceResolver().resolve(
      reference: "../data/value.yaml",
      containingResource: containingResource,
      provider: provider
    )
    #expect(resolution.status == .resolved)
    #expect(resolution.resourceKind == .yaml)
  }

  @Test
  func `absolute paths and file URIs share root enforcement`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let source = fixture.root.appendingPathComponent("source.yaml")
    try fixture.write("value: allowed\n", to: source)
    let provider = FileFMVarResourceProvider(
      policy: try FMVarHostPolicy(allowedRoot: fixture.root)
    )

    let result = await provider.resource(for: request(source.absoluteString))
    #expect(result.resource?.bytes == Data("value: allowed\n".utf8))

    let outsideResult = await provider.resource(for: request(fixture.outside.absoluteString))
    let traversalResult = await provider.resource(for: request(
      fixture.root.absoluteString + "../outside.yaml"
    ))
    let encodedTraversalResult = await provider.resource(for: request(
      fixture.root.absoluteString + "%2e%2e/outside.yaml"
    ))
    #expect(outsideResult.failure?.reason == .outsideAllowedRoot)
    #expect(traversalResult.failure?.reason == .outsideAllowedRoot)
    #expect(encodedTraversalResult.failure?.reason == .outsideAllowedRoot)
  }

  @Test
  func `symlinks may remain inside root but may not escape it`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let insideTarget = fixture.root.appendingPathComponent("inside.yaml")
    let insideLink = fixture.root.appendingPathComponent("inside-link.yaml")
    let outsideLink = fixture.root.appendingPathComponent("outside-link.yaml")
    try fixture.write("inside: true\n", to: insideTarget)
    try fixture.write("outside: true\n", to: fixture.outside)
    try FileManager.default.createSymbolicLink(at: insideLink, withDestinationURL: insideTarget)
    try FileManager.default.createSymbolicLink(at: outsideLink, withDestinationURL: fixture.outside)
    let provider = FileFMVarResourceProvider(
      policy: try FMVarHostPolicy(allowedRoot: fixture.root)
    )

    let inside = await provider.resource(for: request(insideLink.absoluteString))
    let outside = await provider.resource(for: request(outsideLink.absoluteString))
    #expect(inside.resource?.bytes == Data("inside: true\n".utf8))
    #expect(outside.failure?.reason == .symlinkEscape)
  }

  @Test
  func `unsupported URI capabilities fail without reading`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let provider = FileFMVarResourceProvider(
      policy: try FMVarHostPolicy(allowedRoot: fixture.root)
    )
    let identifiers = [
      "https://example.test/value.yaml",
      "file://server.example/value.yaml",
      "file://user:secret@/value.yaml",
      fixture.root.appendingPathComponent("value.yaml").absoluteString + "?token=secret",
      "file:///bad%GG.yaml",
    ]

    for identifier in identifiers {
      let result = await provider.resource(for: request(identifier))
      #expect(result.failure?.reason == .unsupported, Comment(rawValue: identifier))
      #expect(result.failure?.message.contains("secret") == false)
    }
  }

  @Test
  func `missing directories and unsupported kinds remain distinct`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent("directory.yaml", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let provider = FileFMVarResourceProvider(
      policy: try FMVarHostPolicy(allowedRoot: fixture.root)
    )

    let missing = await provider.resource(for: request(
      fixture.root.appendingPathComponent("missing.yaml").absoluteString
    ))
    let unreadable = await provider.resource(for: request(directory.absoluteString))
    let unsupported = await provider.resource(for: request(
      fixture.root.appendingPathComponent("value.json").absoluteString
    ))

    #expect(missing.failure?.reason == .notFound)
    #expect(unreadable.failure?.reason == .unreadable)
    #expect(unsupported.failure?.reason == .unsupported)
  }

  @Test
  func `source byte limit accepts exact size and rejects larger sources`() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let exact = fixture.root.appendingPathComponent("exact.yaml")
    let excessive = fixture.root.appendingPathComponent("excessive.yaml")
    try fixture.write("1234", to: exact)
    try fixture.write("12345", to: excessive)
    let provider = FileFMVarResourceProvider(policy: try FMVarHostPolicy(
      allowedRoot: fixture.root,
      maximumSourceByteCount: 4
    ))

    let exactResult = await provider.resource(for: request(exact.absoluteString))
    let excessiveResult = await provider.resource(for: request(excessive.absoluteString))
    let excessiveContaining = provider.containingResource(at: excessive)
    #expect(exactResult.resource?.bytes.count == 4)
    #expect(excessiveResult.failure?.reason == .excessiveSize)
    #expect(excessiveContaining.failure?.reason == .excessiveSize)
  }

  @Test
  func `diagnostic identifiers redact credentials and query contents`() {
    let identifier = FMVarResourceIdentifier(
      rawValue: "https://user:secret@example.test/value.yaml?token=sensitive"
    )
    #expect(identifier.diagnosticDescription.contains("user") == false)
    #expect(identifier.diagnosticDescription.contains("secret") == false)
    #expect(identifier.diagnosticDescription.contains("sensitive") == false)
    #expect(identifier.diagnosticDescription.contains("example.test/value.yaml") == true)
    #expect(identifier.diagnosticDescription.hasSuffix("?redacted"))
  }

  private func request(_ identifier: String) -> FMVarResourceRequest {
    FMVarResourceRequest(
      reference: identifier,
      identifier: FMVarResourceIdentifier(rawValue: identifier)
    )
  }
}

private struct Fixture {
  let directory: URL
  let root: URL
  let outside: URL

  init() throws {
    let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    self.directory = current.appendingPathComponent(
      "tmp/fm-var-host-policy-\(UUID().uuidString)/",
      isDirectory: true
    )
    self.root = directory.appendingPathComponent("content/", isDirectory: true)
    self.outside = directory.appendingPathComponent("outside.yaml")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func write(_ content: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(content.utf8).write(to: url)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private extension FMVarResourceProviderResult {
  var resource: FMVarResource? {
    guard case .resource(let resource) = self else { return nil }
    return resource
  }

  var failure: FMVarResourceAccessFailure? {
    guard case .failure(let failure) = self else { return nil }
    return failure
  }
}
