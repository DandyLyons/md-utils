import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Markdown record identity index")
struct MarkdownRecordIdentityIndexTests {
  @Test
  func `Existing identity uses logical path fallback by default`() async throws {
    let record = try makeRecord(path: "books/dune.md", identity: "record-1")

    let index = await MarkdownRecordIdentityIndex.build(
      records: [record],
      policy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
    )

    let assessment = try #require(index.assessments.first)
    let expectedPath = try MarkdownRecordPath("books/dune.md")
    #expect(assessment.primaryIdentity == MarkdownRecordIdentity(rawValue: "record-1"))
    #expect(assessment.logicalPathFallback == expectedPath)
    #expect(assessment.status == .available)
    #expect(index.lookup(primary: MarkdownRecordIdentity(rawValue: "record-1")) == .record(
      MarkdownRecordIdentityCandidate(
        record: record,
        primaryIdentity: MarkdownRecordIdentity(rawValue: "record-1"),
        logicalPathFallback: expectedPath
      )
    ))
  }

  @Test
  func `Fallback can be disabled without hiding a primary collision`() async throws {
    let records = [
      try makeRecord(path: "a.md", identity: "same"),
      try makeRecord(path: "b.md", identity: "same"),
    ]
    let policy = MarkdownRecordIdentityPolicy(
      source: .existingIdentity,
      logicalPathFallbackEnabled: false
    )

    let index = await MarkdownRecordIdentityIndex.build(records: records, policy: policy)

    #expect(index.assessments.allSatisfy { $0.status == .duplicate })
    #expect(index.assessments.allSatisfy { $0.logicalPathFallback == nil })
    #expect(index.lookup(logicalPath: try MarkdownRecordPath("a.md")) == .notFound)
    guard case .conflict(let conflict) = index.lookup(
      primary: MarkdownRecordIdentity(rawValue: "same")
    ) else {
      Issue.record("Expected a primary identity conflict")
      return
    }
    #expect(conflict.candidates.count == 2)
  }

  @Test
  func `Logical path identity changes when a record moves`() async throws {
    let original = try makeRecord(path: "books/dune.md")
    let moved = try makeRecord(path: "archive/dune.md")
    let policy = MarkdownRecordIdentityPolicy(source: .logicalPath)

    let originalIndex = await MarkdownRecordIdentityIndex.build(records: [original], policy: policy)
    let movedIndex = await MarkdownRecordIdentityIndex.build(records: [moved], policy: policy)

    #expect(originalIndex.assessments.first?.primaryIdentity?.rawValue == "books/dune.md")
    #expect(movedIndex.assessments.first?.primaryIdentity?.rawValue == "archive/dune.md")
  }

  @Test
  func `Existing and frontmatter identities remain stable when a record moves`() async throws {
    let original = try makeRecord(
      path: "books/dune.md",
      identity: "stored-id",
      frontmatter: "metadata:\n  id: authored-id"
    )
    let moved = try makeRecord(
      path: "archive/dune.md",
      identity: "stored-id",
      frontmatter: "metadata:\n  id: authored-id"
    )

    let existingPolicy = MarkdownRecordIdentityPolicy(source: .existingIdentity)
    let frontmatterPolicy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["metadata", "id"], format: .string)
    )
    let originalExisting = await MarkdownRecordIdentityIndex.build(records: [original], policy: existingPolicy)
    let movedExisting = await MarkdownRecordIdentityIndex.build(records: [moved], policy: existingPolicy)
    let originalFrontmatter = await MarkdownRecordIdentityIndex.build(records: [original], policy: frontmatterPolicy)
    let movedFrontmatter = await MarkdownRecordIdentityIndex.build(records: [moved], policy: frontmatterPolicy)

    #expect(originalExisting.assessments.first?.primaryIdentity == movedExisting.assessments.first?.primaryIdentity)
    #expect(
      originalFrontmatter.assessments.first?.primaryIdentity
        == movedFrontmatter.assessments.first?.primaryIdentity
    )
  }

  @Test
  func `Nested frontmatter strings are exact and reserved metadata is excluded`() async throws {
    let exact = try makeRecord(path: "exact.md", frontmatter: "metadata:\n  id: Book-01")
    let reserved = try makeRecord(path: "reserved.md", frontmatter: "$md-utils:\n  privateID: hidden")
    let exactPolicy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["metadata", "id"], format: .string)
    )
    let reservedPolicy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["$md-utils", "privateID"], format: .string)
    )

    let exactIndex = await MarkdownRecordIdentityIndex.build(records: [exact], policy: exactPolicy)
    let reservedIndex = await MarkdownRecordIdentityIndex.build(records: [reserved], policy: reservedPolicy)

    #expect(exactIndex.assessments.first?.primaryIdentity?.rawValue == "Book-01")
    #expect(reservedIndex.assessments.first?.status == .missing)
    #expect(reservedIndex.assessments.first?.diagnostics.first?.code == .missingFrontmatterValue)
  }

  @Test
  func `Missing null malformed and empty paths produce distinct assessment failures`() async throws {
    let missing = try makeRecord(path: "missing.md", frontmatter: "title: Missing")
    let null = try makeRecord(path: "null.md", frontmatter: "id: null")
    let malformed = MarkdownRecord(
      content: "---\nid: [unterminated\n---\n# Note\n",
      context: MarkdownRecordContext(path: try MarkdownRecordPath("malformed.md"))
    )

    let policy = MarkdownRecordIdentityPolicy(source: .frontmatter(path: ["id"], format: .string))
    let index = await MarkdownRecordIdentityIndex.build(records: [missing, null, malformed], policy: policy)
    let invalidPolicy = MarkdownRecordIdentityPolicy(source: .frontmatter(path: [], format: .string))
    let invalidIndex = await MarkdownRecordIdentityIndex.build(records: [missing], policy: invalidPolicy)

    #expect(index.assessments.map(\.status) == [.missing, .missing, .invalid])
    #expect(index.assessments[0].diagnostics.first?.code == .missingFrontmatterValue)
    #expect(index.assessments[1].diagnostics.first?.code == .missingFrontmatterValue)
    #expect(index.assessments[2].diagnostics.first?.code == .invalidFrontmatter)
    #expect(invalidIndex.assessments.first?.diagnostics.first?.code == .invalidFrontmatterPath)
  }

  @Test
  func `Unsupported frontmatter scalars and nonintegral numbers are invalid`() async throws {
    let records = [
      try makeRecord(path: "boolean.md", frontmatter: "id: true"),
      try makeRecord(path: "array.md", frontmatter: "id: [one, two]"),
      try makeRecord(path: "object.md", frontmatter: "id:\n  nested: value"),
    ]
    let stringPolicy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["id"], format: .string)
    )
    let number = try makeRecord(path: "number.md", frontmatter: "id: 1.5")
    let integerPolicy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["id"], format: .integer)
    )

    let scalarIndex = await MarkdownRecordIdentityIndex.build(records: records, policy: stringPolicy)
    let numberIndex = await MarkdownRecordIdentityIndex.build(records: [number], policy: integerPolicy)

    #expect(scalarIndex.assessments.allSatisfy { $0.status == .invalid })
    #expect(scalarIndex.assessments.allSatisfy {
      $0.diagnostics.first?.code == .unsupportedFrontmatterValue
    })
    #expect(numberIndex.assessments.first?.diagnostics.first?.code == .invalidInteger)
  }

  @Test
  func `Integers use canonical base ten identity and reject numeric strings`() async throws {
    let integer = try makeRecord(path: "integer.md", frontmatter: "id: 42")
    let string = try makeRecord(path: "string.md", frontmatter: "id: '42'")

    let integerIndex = await MarkdownRecordIdentityIndex.build(
      records: [integer, string],
      policy: MarkdownRecordIdentityPolicy(source: .frontmatter(path: ["id"], format: .integer))
    )
    let stringIndex = await MarkdownRecordIdentityIndex.build(
      records: [string],
      policy: MarkdownRecordIdentityPolicy(source: .frontmatter(path: ["id"], format: .string))
    )

    #expect(integerIndex.assessments.first?.primaryIdentity?.rawValue == "42")
    #expect(stringIndex.assessments.first?.primaryIdentity?.rawValue == "42")
    #expect(integerIndex.assessments.first?.status == .available)
    #expect(integerIndex.assessments.last?.status == .invalid)
    #expect(stringIndex.assessments.first?.status == .available)
  }

  @Test
  func `UUID spelling is canonicalized before collision detection`() async throws {
    let records = [
      try makeRecord(path: "a.md", frontmatter: "id: 550E8400-E29B-41D4-A716-446655440000"),
      try makeRecord(path: "b.md", frontmatter: "id: 550e8400-e29b-41d4-a716-446655440000"),
    ]
    let policy = MarkdownRecordIdentityPolicy(source: .frontmatter(path: ["id"], format: .uuid))

    let index = await MarkdownRecordIdentityIndex.build(records: records, policy: policy)

    #expect(index.assessments.allSatisfy { $0.status == .duplicate })
    #expect(index.assessments.allSatisfy {
      $0.primaryIdentity?.rawValue == "550e8400-e29b-41d4-a716-446655440000"
    })
  }

  @Test
  func `Invalid UUID is diagnosed`() async throws {
    let record = try makeRecord(path: "invalid.md", frontmatter: "id: not-a-uuid")
    let policy = MarkdownRecordIdentityPolicy(source: .frontmatter(path: ["id"], format: .uuid))

    let index = await MarkdownRecordIdentityIndex.build(records: [record], policy: policy)

    #expect(index.assessments.first?.status == .invalid)
    #expect(index.assessments.first?.diagnostics.first?.code == .invalidUUID)
  }

  @Test
  func `Strict ASCII slug requires lowercase single-hyphen segments`() async throws {
    let values = ["book-42", "Book-42", "book--42", "-book", "book_42"]
    let records = try values.enumerated().map { index, value in
      try makeRecord(path: "\(index).md", frontmatter: "id: \(value)")
    }
    let policy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["id"], format: .slug(.strictASCII))
    )

    let index = await MarkdownRecordIdentityIndex.build(records: records, policy: policy)

    #expect(index.assessments.map(\.status) == [.available, .invalid, .invalid, .invalid, .invalid])
  }

  @Test
  func `Unicode slug permits lowercase letters digits hyphens and underscores`() async throws {
    let valid = try makeRecord(path: "valid.md", frontmatter: "id: café_42-notes")
    let uppercase = try makeRecord(path: "uppercase.md", frontmatter: "id: Café")
    let adjacent = try makeRecord(path: "adjacent.md", frontmatter: "id: café_-notes")
    let policy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["id"], format: .slug(.unicode))
    )

    let index = await MarkdownRecordIdentityIndex.build(
      records: [valid, uppercase, adjacent],
      policy: policy
    )

    #expect(index.assessments.map(\.status) == [.available, .invalid, .invalid])
  }

  @Test
  func `Preserve slug accepts ASCII case without normalizing it`() async throws {
    let upper = try makeRecord(path: "upper.md", frontmatter: "id: Book-42")
    let lower = try makeRecord(path: "lower.md", frontmatter: "id: book-42")
    let policy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["id"], format: .slug(.preserve))
    )

    let index = await MarkdownRecordIdentityIndex.build(records: [upper, lower], policy: policy)

    #expect(index.assessments.map(\.status) == [.available, .available])
    #expect(index.assessments.map { $0.primaryIdentity?.rawValue } == ["Book-42", "book-42"])
  }

  @Test
  func `Collision diagnostics and candidates contain every path in stable order`() async throws {
    let records = [
      try makeRecord(path: "z.md", frontmatter: "id: shared"),
      try makeRecord(path: "a.md", frontmatter: "id: shared"),
      try makeRecord(path: "m.md", frontmatter: "id: shared"),
    ]
    let policy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["id"], format: .string)
    )

    let index = await MarkdownRecordIdentityIndex.build(records: records, policy: policy)
    let expectedPaths = try ["a.md", "m.md", "z.md"].map(MarkdownRecordPath.init)
    let diagnostic = try #require(index.assessments.first?.diagnostics.first {
      $0.code == .duplicatePrimaryIdentity
    })

    #expect(diagnostic.paths == expectedPaths)
    #expect(index.collisionDiagnostics == [diagnostic])
    guard case .conflict(let conflict) = index.lookup(
      primary: MarkdownRecordIdentity(rawValue: "shared")
    ) else {
      Issue.record("Expected a primary identity conflict")
      return
    }
    #expect(conflict.candidates.compactMap { $0.record.context.path } == expectedPaths)
  }

  @Test
  func `Duplicate logical paths return conflict instead of first record`() async throws {
    let records = [
      try makeRecord(path: "same.md", identity: "one", body: "# One\n"),
      try makeRecord(path: "same.md", identity: "two", body: "# Two\n"),
    ]
    let index = await MarkdownRecordIdentityIndex.build(
      records: records,
      policy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
    )

    #expect(index.assessments.allSatisfy {
      $0.diagnostics.contains { $0.code == .duplicateLogicalPath }
    })
    guard case .conflict(let conflict) = index.lookup(logicalPath: try MarkdownRecordPath("same.md")) else {
      Issue.record("Expected a logical path conflict")
      return
    }
    #expect(conflict.candidates.count == 2)
  }

  @Test
  func `Missing primary identity remains available by fallback and independent of type assessment`() async throws {
    let record = try makeRecord(path: "books/note.md", body: "# Note\n")
    let index = await MarkdownRecordIdentityIndex.build(
      records: [record],
      policy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
    )

    #expect(index.assessments.first?.status == .missing)
    guard case .record(let candidate) = index.lookup(
      logicalPath: try MarkdownRecordPath("books/note.md")
    ) else {
      Issue.record("Expected fallback lookup to remain available")
      return
    }
    #expect(candidate.record == record)
  }

  @Test
  func `Identity status is independent from Markdown type conformance`() async throws {
    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "Book"),
      version: "1.0.0",
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "book-heading",
          predicate: .heading(MarkdownHeadingPredicate(text: "Book", level: 1))
        )
      ])
    )
    let checker = try MarkdownTypeChecker(registry: MarkdownTypeRegistry(definitions: [definition]))
    let record = try makeRecord(path: "notes/note.md", identity: "record-1", body: "# Note\n")

    let typeAssessment = try await checker.assess(record, as: "Book")
    let identityIndex = await MarkdownRecordIdentityIndex.build(
      records: [record],
      policy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
    )

    #expect(typeAssessment.conforms == false)
    #expect(identityIndex.assessments.first?.status == .available)
  }

  @Test
  func `Enabled fallback diagnoses a record without a logical path`() async {
    let record = MarkdownRecord(
      identity: MarkdownRecordIdentity(rawValue: "record-1"),
      content: "# Note\n"
    )

    let index = await MarkdownRecordIdentityIndex.build(
      records: [record],
      policy: MarkdownRecordIdentityPolicy(source: .existingIdentity)
    )

    #expect(index.assessments.first?.status == .available)
    #expect(index.assessments.first?.logicalPathFallback == nil)
    #expect(index.assessments.first?.diagnostics.first?.code == .missingLogicalPath)
  }

  @Test
  func `Configuration and structured lookup results round trip through Codable`() async throws {
    let policy = MarkdownRecordIdentityPolicy(
      source: .frontmatter(path: ["metadata", "slug"], format: .slug(.unicode)),
      logicalPathFallbackEnabled: false
    )
    let policyData = try JSONEncoder().encode(policy)
    #expect(try JSONDecoder().decode(MarkdownRecordIdentityPolicy.self, from: policyData) == policy)

    let result = MarkdownRecordIdentityLookupResult.conflict(MarkdownRecordIdentityConflict(
      key: .primary(MarkdownRecordIdentity(rawValue: "same")),
      candidates: []
    ))
    let resultData = try JSONEncoder().encode(result)
    #expect(try JSONDecoder().decode(MarkdownRecordIdentityLookupResult.self, from: resultData) == result)
  }

  private func makeRecord(
    path: String,
    identity: String? = nil,
    frontmatter: String? = nil,
    body: String = "# Note\n"
  ) throws -> MarkdownRecord {
    let content = frontmatter.map { "---\n\($0)\n---\n\(body)" } ?? body
    return MarkdownRecord(
      identity: identity.map(MarkdownRecordIdentity.init(rawValue:)),
      content: content,
      context: MarkdownRecordContext(path: try MarkdownRecordPath(path))
    )
  }
}
