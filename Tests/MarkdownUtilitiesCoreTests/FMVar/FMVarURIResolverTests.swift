import Foundation
@testable import MarkdownUtilitiesCore
import Testing

@Suite("fm-var RFC 3986 source resolution")
struct FMVarURIResolverTests {
  @Test
  func `language-neutral RFC 3986 normal and abnormal vectors`() throws {
    let fixtureURL = try #require(
      Bundle.module.url(forResource: "FMVar", withExtension: nil)?
        .appendingPathComponent("source-resolution-cases.json")
    )
    let fixture = try JSONDecoder().decode(
      SourceResolutionFixture.self,
      from: Data(contentsOf: fixtureURL)
    )
    #expect(fixture.version == "1.0.0")
    let base = FMVarResourceIdentifier(rawValue: fixture.base)

    for testCase in fixture.cases {
      let result = try FMVarURIResolver().resolve(
        reference: testCase.reference,
        relativeTo: base
      )
      #expect(result.rawValue == testCase.expected, Comment(rawValue: testCase.reference))
    }
  }

  @Test
  func `omitted source returns the containing identifier unchanged`() throws {
    let base = FMVarResourceIdentifier(rawValue: "HTTPS://example.test/a/../document.md?draft=1")
    let result = try FMVarURIResolver().resolve(reference: nil, relativeTo: base)
    #expect(result == base)
  }

  @Test(arguments: ["#section", "#", "g#section", "g?x#section"])
  func `fragment components are rejected`(reference: String) {
    #expect(throws: FMVarURIResolutionError.self) {
      try FMVarURIResolver().resolve(
        reference: reference,
        relativeTo: FMVarResourceIdentifier(rawValue: "https://example.test/document.md")
      )
    }
  }

  @Test(arguments: [
    "bad space", "%", "%0", "%GG", "é.yaml", "//[bad", "//host:port/path",
    "//user@@host/path", "//[2001:::1]/path",
  ])
  func `malformed URI references are rejected`(reference: String) {
    #expect(throws: FMVarURIResolutionError.self) {
      try FMVarURIResolver().resolve(
        reference: reference,
        relativeTo: FMVarResourceIdentifier(rawValue: "https://example.test/document.md")
      )
    }
  }

  @Test(arguments: ["document.md", "//example.test/document.md#fragment"])
  func `base must be absolute and fragment free`(base: String) {
    #expect(throws: FMVarURIResolutionError.self) {
      try FMVarURIResolver().resolve(
        reference: "data.yaml",
        relativeTo: FMVarResourceIdentifier(rawValue: base)
      )
    }
  }

  @Test
  func `percent encoded spelling and query content are preserved`() throws {
    let result = try FMVarURIResolver().resolve(
      reference: "../d%61ta.yaml?next=a/../b%2f",
      relativeTo: FMVarResourceIdentifier(rawValue: "https://example.test/a/b/document.md")
    )
    #expect(result.rawValue == "https://example.test/a/d%61ta.yaml?next=a/../b%2f")
  }

  @Test(arguments: [
    ("//user:pass@example.test:8443/data", "https://user:pass@example.test:8443/data"),
    ("//[2001:db8::1]:443/data", "https://[2001:db8::1]:443/data"),
    ("//[v1.a:b]/data", "https://[v1.a:b]/data"),
  ])
  func `valid authority forms are retained`(reference: String, expected: String) throws {
    let result = try FMVarURIResolver().resolve(
      reference: reference,
      relativeTo: FMVarResourceIdentifier(rawValue: "https://example.test/document.md")
    )
    #expect(result.rawValue == expected)
  }
}

private struct SourceResolutionFixture: Decodable {
  let version: String
  let base: String
  let cases: [SourceResolutionCase]
}

private struct SourceResolutionCase: Decodable {
  let reference: String
  let expected: String
}
