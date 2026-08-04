import MarkdownUtilitiesCore
import Testing
@testable import MarkdownUtilitiesServer

@Suite("In-memory record store")
struct InMemoryRecordStoreTests {
  @Test
  func `Seeded records receive revisions and can be fetched by identity`() async throws {
    let seed = try makeRecord("book", path: "books/book.md", content: "# Book")
    let store = try InMemoryRecordStore(records: [seed])

    let stored = try await store.record(for: MarkdownRecordIdentity(rawValue: "book"))

    #expect(stored.content == "# Book")
    #expect(stored.revision != nil)
  }

  @Test
  func `Missing identity lookup reports not found`() async throws {
    let store = try InMemoryRecordStore()
    let identity = MarkdownRecordIdentity(rawValue: "missing")

    await #expect(throws: RecordStoreError.notFound(identity)) {
      try await store.record(for: identity)
    }
  }

  @Test
  func `Enumeration is bounded deterministic and resumable`() async throws {
    let store = try InMemoryRecordStore(records: [
      makeRecord("charlie"),
      makeRecord("alpha"),
      makeRecord("bravo"),
    ])

    let first = try await store.records(matching: RecordStoreQuery(limit: 2))
    let firstToken = try #require(first.continuationToken)
    let second = try await store.records(matching: RecordStoreQuery(
      limit: 2,
      continuationToken: firstToken
    ))

    #expect(first.records.compactMap(\.identity?.rawValue) == ["alpha", "bravo"])
    #expect(second.records.compactMap(\.identity?.rawValue) == ["charlie"])
    #expect(second.continuationToken == nil)
  }

  @Test
  func `Search roots filter logical paths while collection root retains pathless records`() async throws {
    let store = try InMemoryRecordStore(records: [
      makeRecord("nested", path: "books/classics/dune.md"),
      makeRecord("book", path: "books/book.md"),
      makeRecord("note", path: "notes/note.md"),
      makeRecord("pathless"),
    ])
    let booksRoot = try #require(MarkdownSearchRoot(rawValue: "books/"))

    let all = try await store.records(matching: RecordStoreQuery(limit: 10))
    let books = try await store.records(matching: RecordStoreQuery(searchRoot: booksRoot, limit: 10))

    #expect(all.records.count == 4)
    #expect(books.records.compactMap(\.identity?.rawValue) == ["book", "nested"])
  }

  @Test
  func `Queries reject nonpositive limits and malformed or mismatched tokens`() async throws {
    #expect(throws: RecordStoreError.invalidQuery(.nonPositiveLimit(0))) {
      try RecordStoreQuery(limit: 0)
    }

    let store = try InMemoryRecordStore(records: [makeRecord("a"), makeRecord("b")])
    let malformed = RecordStoreContinuationToken(rawValue: "not-base64")
    await #expect(throws: RecordStoreError.invalidQuery(.invalidContinuationToken)) {
      try await store.records(matching: RecordStoreQuery(limit: 1, continuationToken: malformed))
    }

    let first = try await store.records(matching: RecordStoreQuery(limit: 1))
    let token = try #require(first.continuationToken)
    let nestedRoot = try #require(MarkdownSearchRoot(rawValue: "nested/"))
    await #expect(throws: RecordStoreError.invalidQuery(.continuationTokenQueryMismatch)) {
      try await store.records(matching: RecordStoreQuery(
        searchRoot: nestedRoot,
        limit: 1,
        continuationToken: token
      ))
    }
  }

  @Test
  func `Create assigns revisions and rejects duplicates`() async throws {
    let store = try InMemoryRecordStore()
    let record = try makeRecord("book", content: "# Book")

    let created = try await store.create(record)

    #expect(created.revision != nil)
    await #expect(throws: RecordStoreError.conflict(
      .identityAlreadyExists(MarkdownRecordIdentity(rawValue: "book"))
    )) {
      try await store.create(record)
    }
  }

  @Test
  func `Writes reject missing identities and caller supplied revisions`() async throws {
    let store = try InMemoryRecordStore()
    let anonymous = MarkdownRecord(content: "# Anonymous")
    let revision = MarkdownRecordRevision(rawValue: "caller")
    let versioned = MarkdownRecord(
      identity: MarkdownRecordIdentity(rawValue: "versioned"),
      content: "# Versioned",
      revision: revision
    )

    await #expect(throws: RecordStoreError.invalidRecord(.missingIdentity)) {
      try await store.create(anonymous)
    }
    await #expect(throws: RecordStoreError.invalidRecord(.callerSuppliedRevision(revision))) {
      try await store.create(versioned)
    }
  }

  @Test
  func `Canonical invalid Markdown remains storable`() async throws {
    let store = try InMemoryRecordStore()
    let malformed = try makeRecord("malformed", content: "---\n: invalid YAML\n---")

    let stored = try await store.create(malformed)

    #expect(stored.content == malformed.content)
  }

  @Test
  func `Replace changes revision and stale replacement leaves state unchanged`() async throws {
    let original = try makeRecord("book", content: "original")
    let store = try InMemoryRecordStore(records: [original])
    let stored = try await store.record(for: MarkdownRecordIdentity(rawValue: "book"))
    let originalRevision = try #require(stored.revision)
    let replacement = try makeRecord("book", content: "replacement")

    let replaced = try await store.replace(replacement, ifRevision: originalRevision)
    let newRevision = try #require(replaced.revision)

    #expect(newRevision != originalRevision)
    await #expect(throws: RecordStoreError.conflict(.revisionMismatch(
      identity: MarkdownRecordIdentity(rawValue: "book"),
      expected: originalRevision,
      actual: newRevision
    ))) {
      try await store.replace(makeRecord("book", content: "stale"), ifRevision: originalRevision)
    }
    #expect(try await store.record(for: MarkdownRecordIdentity(rawValue: "book")) == replaced)
  }

  @Test
  func `Delete checks revisions and leaves conflicts unchanged`() async throws {
    let store = try InMemoryRecordStore(records: [makeRecord("book")])
    let identity = MarkdownRecordIdentity(rawValue: "book")
    let stored = try await store.record(for: identity)
    let revision = try #require(stored.revision)
    let staleRevision = MarkdownRecordRevision(rawValue: "stale")

    await #expect(throws: RecordStoreError.conflict(.revisionMismatch(
      identity: identity,
      expected: staleRevision,
      actual: revision
    ))) {
      try await store.delete(identity: identity, ifRevision: staleRevision)
    }
    #expect(try await store.record(for: identity) == stored)

    try await store.delete(identity: identity, ifRevision: revision)
    await #expect(throws: RecordStoreError.notFound(identity)) {
      try await store.record(for: identity)
    }
  }

  @Test
  func `Seed import rejects duplicate identities`() throws {
    let identity = MarkdownRecordIdentity(rawValue: "duplicate")

    #expect(throws: RecordStoreError.conflict(.identityAlreadyExists(identity))) {
      try InMemoryRecordStore(records: [makeRecord("duplicate"), makeRecord("duplicate")])
    }
  }

  @Test
  func `Cancellation propagates without committing a mutation`() async throws {
    let store = try InMemoryRecordStore()
    let identity = MarkdownRecordIdentity(rawValue: "cancelled")
    let task = Task {
      withUnsafeCurrentTask { currentTask in
        currentTask?.cancel()
      }
      return try await store.create(makeRecord("cancelled"))
    }

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    await #expect(throws: RecordStoreError.notFound(identity)) {
      try await store.record(for: identity)
    }
  }

  @Test
  func `Public store contract accepts an actor implementation`() async throws {
    let store: any RecordStore = try InMemoryRecordStore(records: [makeRecord("record")])

    let page = try await store.records(matching: RecordStoreQuery(limit: 1))

    #expect(page.records.count == 1)
  }

  private func makeRecord(
    _ identity: String,
    path: String? = nil,
    content: String = "# Record"
  ) throws -> MarkdownRecord {
    let logicalPath: MarkdownRecordPath?
    if let path {
      logicalPath = try MarkdownRecordPath(path)
    } else {
      logicalPath = nil
    }
    return MarkdownRecord(
      identity: MarkdownRecordIdentity(rawValue: identity),
      content: content,
      context: MarkdownRecordContext(path: logicalPath)
    )
  }
}
