import Foundation
import MarkdownUtilitiesCore
import Testing
@testable import MarkdownUtilitiesServer

@Suite("Paged read repositories")
struct MarkdownServerReadRepositoryTests {
  private func record(_ id: String, path: String? = nil, body: String = "body") throws -> GenericMarkdownRecord {
    GenericMarkdownRecord(canonicalIdentity: .init(rawValue: id), identityStatus: .available,
      logicalPath: try path.map(MarkdownRecordPath.init), revision: nil, memberships: [], valid: true,
      frontmatter: nil, body: body, diagnostics: [])
  }

  @Test func `pagination retains pathless records and repeated logical paths`() async throws {
    let records = try [record("a"), record("b"), record("c", path: "same.md"), record("d", path: "same.md")]
    let snapshot = MarkdownServerReadSnapshot(resources: [MarkdownResourceReadSnapshot(name: "all", records: records, primaryLookup: [:])],
      canonicalRecords: records, logicalPathLookup: [:])
    let repository = MarkdownSnapshotReadRepository(snapshot: snapshot, generation: "test")
    var cursor: String?
    var identities: [String] = []
    repeat {
      let page = try await repository.page(resource: "all", query: .init(limit: 1, cursor: cursor))
      identities += page.records.compactMap { $0.canonicalIdentity?.rawValue }
      cursor = page.nextCursor
    } while cursor != nil && identities.count < 10
    #expect(identities == ["a", "b", "c", "d"])
  }

  @Test func `body byte preflight matches JSON escaping without serializing large bodies`() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let sample = try record("sample", body: "\u{0000}/\n\" \\ \u{2028}雪😀")
    #expect(try markdownServerEncodedRecordSize(sample) == encoder.encode(sample).count)
    let oversized = try record("large", body: String(repeating: "\u{0000}", count: 12 * 1_024 * 1_024))
    #expect(throws: MarkdownServerReadError.responseTooLarge) { try markdownServerEncodedRecordSize(oversized) }
  }
}
