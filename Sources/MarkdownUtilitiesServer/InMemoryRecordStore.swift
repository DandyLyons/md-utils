import Foundation
import MarkdownUtilitiesCore

/// An actor-backed reference implementation of ``RecordStore``.
///
/// Records are indexed by stable identity. Enumeration uses identity ordering and
/// opaque keyset tokens; it does not promise snapshot consistency across mutations.
/// The actor serializes revision checks with mutations so stale replacements and
/// deletions cannot commit. Every stored record has an identity and a store-owned
/// revision, while canonical Markdown content is retained without parsing or
/// conformance assessment.
public actor InMemoryRecordStore: RecordStore {
  /// Canonical records keyed by the same stable identity stored on each value.
  ///
  /// Entries are inserted only after storage validation and revision assignment.
  /// Consequently, every value in this dictionary has a non-`nil` identity and
  /// revision, and its identity equals its dictionary key.
  private var recordsByIdentity: [MarkdownRecordIdentity: MarkdownRecord]

  /// Numeric component reserved for the next store-owned opaque revision.
  ///
  /// The counter advances for each successful seed import, create, or replacement.
  /// Deletion does not recycle revision values.
  private var nextRevisionValue: UInt64

  /// Creates a store and imports seed records through normal creation invariants.
  ///
  /// Seed records require identities, must not contain revisions, and receive
  /// store-owned revisions in their supplied order.
  ///
  /// - Parameter records: Initial canonical records.
  /// - Throws: ``RecordStoreError`` when a seed is invalid or duplicates an identity.
  public init(records: [MarkdownRecord] = []) throws {
    var imported: [MarkdownRecordIdentity: MarkdownRecord] = [:]
    var revisionValue: UInt64 = 1

    for record in records {
      let identity = try Self.validatedIdentity(for: record)
      guard imported[identity] == nil else {
        throw RecordStoreError.conflict(.identityAlreadyExists(identity))
      }
      let revision = try Self.takeRevision(from: &revisionValue)
      var stored = record
      stored.revision = revision
      imported[identity] = stored
    }

    recordsByIdentity = imported
    nextRevisionValue = revisionValue
  }

  /// Fetches the current canonical record for an identity.
  ///
  /// Cancellation is checked before the actor reads its state.
  ///
  /// - Parameter identity: Stable identity used as the storage key.
  /// - Returns: The complete canonical record, including its current revision.
  /// - Throws: ``RecordStoreError/notFound(_:)`` when no record has the identity,
  ///   or `CancellationError` when the task is already cancelled.
  public func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    try Task.checkCancellation()
    guard let record = recordsByIdentity[identity] else {
      throw RecordStoreError.notFound(identity)
    }
    return record
  }

  /// Enumerates a deterministic page ordered by stable identity.
  ///
  /// The collection root includes every record, including records without logical
  /// paths. A nested search root includes only records whose logical path begins
  /// with that validated directory. A continuation resumes strictly after the last
  /// identity returned by the preceding page.
  ///
  /// Cancellation is checked before enumeration, while scanning candidates, and
  /// before returning the completed page.
  ///
  /// - Parameter query: Validated search root, positive page limit, and optional token.
  /// - Returns: At most `query.limit` records and a continuation token when more remain.
  /// - Throws: ``RecordStoreError/invalidQuery(_:)`` for malformed or mismatched
  ///   continuation tokens, ``RecordStoreError/unavailable`` if a token cannot be
  ///   encoded, or `CancellationError` when enumeration is cancelled.
  public func records(matching query: RecordStoreQuery) async throws -> RecordStorePage {
    try Task.checkCancellation()
    let position = try decode(query.continuationToken, for: query.searchRoot)
    var candidates: [(identity: MarkdownRecordIdentity, record: MarkdownRecord)] = []
    candidates.reserveCapacity(recordsByIdentity.count)

    for (identity, record) in recordsByIdentity {
      try Task.checkCancellation()
      guard Self.includes(record, in: query.searchRoot) else { continue }
      guard position.map({ identity.rawValue > $0.rawValue }) ?? true else { continue }
      candidates.append((identity, record))
    }
    candidates.sort { $0.identity.rawValue < $1.identity.rawValue }

    let pageCandidates = Array(candidates.prefix(query.limit))
    let hasMore = pageCandidates.count < candidates.count
    let token: RecordStoreContinuationToken?
    if hasMore, let lastIdentity = pageCandidates.last?.identity {
      token = try encode(lastIdentity, for: query.searchRoot)
    } else {
      token = nil
    }
    try Task.checkCancellation()
    return RecordStorePage(records: pageCandidates.map(\.record), continuationToken: token)
  }

  /// Creates a record after atomically confirming that its identity is unused.
  ///
  /// The proposed record must have a stable identity and no revision. The store
  /// assigns a new opaque revision immediately before committing the record.
  ///
  /// - Parameter record: Complete canonical record proposed for creation.
  /// - Returns: The committed record with its store-owned revision.
  /// - Throws: ``RecordStoreError/invalidRecord(_:)`` for missing identity or a
  ///   caller-supplied revision, ``RecordStoreError/conflict(_:)`` for an existing
  ///   identity, ``RecordStoreError/unavailable`` on revision exhaustion, or
  ///   `CancellationError` before commit.
  public func create(_ record: MarkdownRecord) async throws -> MarkdownRecord {
    try Task.checkCancellation()
    let identity = try Self.validatedIdentity(for: record)
    guard recordsByIdentity[identity] == nil else {
      throw RecordStoreError.conflict(.identityAlreadyExists(identity))
    }
    try Task.checkCancellation()
    let revision = try Self.takeRevision(from: &nextRevisionValue)
    var stored = record
    stored.revision = revision
    recordsByIdentity[identity] = stored
    return stored
  }

  /// Replaces a record after atomically checking its expected revision.
  ///
  /// Validation, lookup, revision comparison, new-revision allocation, and commit
  /// execute under actor isolation. A failed precondition leaves the existing value
  /// unchanged.
  ///
  /// - Parameters:
  ///   - record: Complete replacement with an identity and no revision.
  ///   - expectedRevision: Revision that must match the current stored record.
  /// - Returns: The committed replacement with a newly assigned revision.
  /// - Throws: ``RecordStoreError/invalidRecord(_:)`` for invalid input,
  ///   ``RecordStoreError/notFound(_:)`` when the identity is absent,
  ///   ``RecordStoreError/conflict(_:)`` on a stale revision,
  ///   ``RecordStoreError/unavailable`` if stored invariants fail or revisions are
  ///   exhausted, or `CancellationError` before commit.
  public func replace(
    _ record: MarkdownRecord,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws -> MarkdownRecord {
    try Task.checkCancellation()
    let identity = try Self.validatedIdentity(for: record)
    guard let current = recordsByIdentity[identity] else {
      throw RecordStoreError.notFound(identity)
    }
    guard let actualRevision = current.revision else {
      throw RecordStoreError.unavailable
    }
    guard actualRevision == expectedRevision else {
      throw RecordStoreError.conflict(.revisionMismatch(
        identity: identity,
        expected: expectedRevision,
        actual: actualRevision
      ))
    }
    try Task.checkCancellation()
    let revision = try Self.takeRevision(from: &nextRevisionValue)
    var stored = record
    stored.revision = revision
    recordsByIdentity[identity] = stored
    return stored
  }

  /// Deletes a record after atomically checking its expected revision.
  ///
  /// The record remains stored when the expected revision is stale or cancellation
  /// is observed before removal.
  ///
  /// - Parameters:
  ///   - identity: Stable identity of the record to remove.
  ///   - expectedRevision: Revision that must match the current stored record.
  /// - Throws: ``RecordStoreError/notFound(_:)`` when the identity is absent,
  ///   ``RecordStoreError/conflict(_:)`` on a stale revision,
  ///   ``RecordStoreError/unavailable`` if the stored record lacks a revision, or
  ///   `CancellationError` before commit.
  public func delete(
    identity: MarkdownRecordIdentity,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws {
    try Task.checkCancellation()
    guard let current = recordsByIdentity[identity] else {
      throw RecordStoreError.notFound(identity)
    }
    guard let actualRevision = current.revision else {
      throw RecordStoreError.unavailable
    }
    guard actualRevision == expectedRevision else {
      throw RecordStoreError.conflict(.revisionMismatch(
        identity: identity,
        expected: expectedRevision,
        actual: actualRevision
      ))
    }
    try Task.checkCancellation()
    recordsByIdentity.removeValue(forKey: identity)
  }

  /// Validates the persistence invariants shared by seed import and write operations.
  ///
  /// This check deliberately does not parse Markdown, YAML, rules, or mdtypes. Those
  /// representations and assessments are derived from the canonical stored content.
  ///
  /// - Parameter record: Canonical record proposed for storage.
  /// - Returns: The stable identity used to index the record.
  /// - Throws: ``RecordStoreError/invalidRecord(_:)`` when the identity is absent or
  ///   the caller has supplied a backend-owned revision.
  private static func validatedIdentity(
    for record: MarkdownRecord
  ) throws -> MarkdownRecordIdentity {
    guard let identity = record.identity else {
      throw RecordStoreError.invalidRecord(.missingIdentity)
    }
    if let revision = record.revision {
      throw RecordStoreError.invalidRecord(.callerSuppliedRevision(revision))
    }
    return identity
  }

  /// Allocates the next opaque revision and advances the supplied counter.
  ///
  /// The counter changes only when allocation succeeds. Revision strings are an
  /// implementation detail and callers must not infer ordering from their contents.
  ///
  /// - Parameter nextValue: Counter containing the next unallocated numeric component.
  /// - Returns: A unique revision for this in-memory store instance.
  /// - Throws: ``RecordStoreError/unavailable`` when the counter is exhausted.
  private static func takeRevision(
    from nextValue: inout UInt64
  ) throws -> MarkdownRecordRevision {
    guard nextValue < UInt64.max else {
      throw RecordStoreError.unavailable
    }
    let revision = MarkdownRecordRevision(rawValue: "in-memory-\(nextValue)")
    nextValue += 1
    return revision
  }

  /// Determines whether a record belongs to a query's logical search root.
  ///
  /// The collection root includes pathless records. Nested roots require a logical
  /// path with the root's validated trailing-slash prefix.
  ///
  /// - Parameters:
  ///   - record: Candidate canonical record.
  ///   - searchRoot: Collection root or validated nested directory.
  /// - Returns: `true` when enumeration should retain the record.
  private static func includes(_ record: MarkdownRecord, in searchRoot: MarkdownSearchRoot) -> Bool {
    guard searchRoot != .collectionRoot else { return true }
    return record.context.path?.rawValue.hasPrefix(searchRoot.rawValue) == true
  }

  /// Decodes and validates an optional continuation position for a search root.
  ///
  /// Token versions allow the private representation to evolve without changing the
  /// public token wrapper. Tokens are scoped to a search root but not to a page size.
  ///
  /// - Parameters:
  ///   - token: Opaque token returned by a preceding enumeration, or `nil` to start.
  ///   - searchRoot: Root of the query being resumed.
  /// - Returns: Last emitted identity, or `nil` for the first page.
  /// - Throws: ``RecordStoreError/invalidQuery(_:)`` when decoding fails, the token
  ///   version is unsupported, or the token belongs to another root.
  private func decode(
    _ token: RecordStoreContinuationToken?,
    for searchRoot: MarkdownSearchRoot
  ) throws -> MarkdownRecordIdentity? {
    guard let token else { return nil }
    guard let data = Data(base64Encoded: token.rawValue),
          let payload = try? JSONDecoder().decode(ContinuationPayload.self, from: data)
    else {
      throw RecordStoreError.invalidQuery(.invalidContinuationToken)
    }
    guard payload.version == 1 else {
      throw RecordStoreError.invalidQuery(.invalidContinuationToken)
    }
    guard payload.searchRoot == searchRoot.rawValue else {
      throw RecordStoreError.invalidQuery(.continuationTokenQueryMismatch)
    }
    return MarkdownRecordIdentity(rawValue: payload.lastIdentity)
  }

  /// Encodes an identity as an opaque continuation token scoped to a search root.
  ///
  /// - Parameters:
  ///   - identity: Last identity included in the current page.
  ///   - searchRoot: Root whose enumeration will be resumed.
  /// - Returns: Base64-encoded versioned payload for the next query.
  /// - Throws: ``RecordStoreError/unavailable`` if the payload cannot be encoded.
  private func encode(
    _ identity: MarkdownRecordIdentity,
    for searchRoot: MarkdownSearchRoot
  ) throws -> RecordStoreContinuationToken {
    let payload = ContinuationPayload(
      version: 1,
      searchRoot: searchRoot.rawValue,
      lastIdentity: identity.rawValue
    )
    guard let data = try? JSONEncoder().encode(payload) else {
      throw RecordStoreError.unavailable
    }
    return RecordStoreContinuationToken(rawValue: data.base64EncodedString())
  }

  /// Private wire representation embedded in an opaque continuation token.
  private struct ContinuationPayload: Codable {
    /// Payload schema version used to reject unsupported token formats.
    let version: Int

    /// Canonical raw search root that scopes the continuation position.
    let searchRoot: String

    /// Stable identity after which the next page resumes.
    let lastIdentity: String
  }
}
