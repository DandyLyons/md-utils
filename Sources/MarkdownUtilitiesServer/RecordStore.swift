import Foundation
import MarkdownUtilitiesCore

/// An opaque position used to continue a bounded record-store enumeration.
public struct RecordStoreContinuationToken: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  /// Backend-defined token contents.
  public let rawValue: String

  /// Creates a token from the opaque value returned by a record store.
  ///
  /// Callers should persist or forward this value without interpreting it.
  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

/// A bounded, storage-neutral request for canonical Markdown records.
public struct RecordStoreQuery: Equatable, Sendable {
  /// Collection-relative directory used to narrow the returned records.
  public let searchRoot: MarkdownSearchRoot

  /// Maximum number of records returned in one page.
  public let limit: Int

  /// Opaque position returned by the preceding page, when continuing enumeration.
  public let continuationToken: RecordStoreContinuationToken?

  /// Creates a bounded enumeration query.
  ///
  /// - Parameters:
  ///   - searchRoot: Collection-relative directory to enumerate, defaulting to the collection root.
  ///   - limit: Positive maximum number of records to return.
  ///   - continuationToken: Opaque token returned by the preceding page.
  /// - Throws: ``RecordStoreError/invalidQuery(_:)`` when `limit` is not positive.
  public init(
    searchRoot: MarkdownSearchRoot = .collectionRoot,
    limit: Int,
    continuationToken: RecordStoreContinuationToken? = nil
  ) throws {
    guard limit > 0 else {
      throw RecordStoreError.invalidQuery(.nonPositiveLimit(limit))
    }
    self.searchRoot = searchRoot
    self.limit = limit
    self.continuationToken = continuationToken
  }
}

/// One bounded page of canonical Markdown records.
public struct RecordStorePage: Equatable, Sendable {
  /// Records in the store's deterministic enumeration order.
  public let records: [MarkdownRecord]

  /// Opaque position for the next page, or `nil` when enumeration is complete.
  public let continuationToken: RecordStoreContinuationToken?

  /// Creates a record page.
  ///
  /// - Parameters:
  ///   - records: Canonical records in deterministic order.
  ///   - continuationToken: Position for continuing enumeration, if more records remain.
  public init(
    records: [MarkdownRecord],
    continuationToken: RecordStoreContinuationToken? = nil
  ) {
    self.records = records
    self.continuationToken = continuationToken
  }
}

/// A semantic conflict detected while atomically mutating canonical records.
public enum RecordStoreConflict: Equatable, Sendable {
  /// A create attempted to reuse an existing stable identity.
  case identityAlreadyExists(MarkdownRecordIdentity)

  /// A mutation's expected revision did not match the current stored revision.
  case revisionMismatch(
    identity: MarkdownRecordIdentity,
    expected: MarkdownRecordRevision,
    actual: MarkdownRecordRevision
  )
}

/// A storage invariant violated by a proposed canonical record.
public enum RecordStoreInvalidRecordReason: Equatable, Sendable {
  /// Canonical persistence requires a stable record identity.
  case missingIdentity

  /// Write callers cannot provide a revision because revisions belong to the store.
  case callerSuppliedRevision(MarkdownRecordRevision)
}

/// A problem with a bounded enumeration request.
public enum RecordStoreInvalidQueryReason: Equatable, Sendable {
  /// Page limits must be greater than zero.
  case nonPositiveLimit(Int)

  /// The continuation token could not be decoded by this store.
  case invalidContinuationToken

  /// The continuation token was created for a different search root.
  case continuationTokenQueryMismatch
}

/// Stable semantic failures exposed by a storage-neutral record store.
public enum RecordStoreError: Error, Equatable, Sendable, LocalizedError {
  /// No canonical record has the requested stable identity.
  case notFound(MarkdownRecordIdentity)

  /// An atomic mutation conflicted with current store state.
  case conflict(RecordStoreConflict)

  /// A proposed record violated a storage invariant.
  case invalidRecord(RecordStoreInvalidRecordReason)

  /// A bounded enumeration query or continuation token was invalid.
  case invalidQuery(RecordStoreInvalidQueryReason)

  /// The backend could not currently perform the requested operation.
  case unavailable

  /// Human-readable description of the semantic storage failure.
  public var errorDescription: String? {
    switch self {
    case .notFound(let identity):
      return "No Markdown record exists with identity \"\(identity.rawValue)\""
    case .conflict(.identityAlreadyExists(let identity)):
      return "A Markdown record already exists with identity \"\(identity.rawValue)\""
    case .conflict(.revisionMismatch(let identity, let expected, let actual)):
      return "Revision conflict for \"\(identity.rawValue)\": expected \"\(expected.rawValue)\", found \"\(actual.rawValue)\""
    case .invalidRecord(.missingIdentity):
      return "A stored Markdown record requires a stable identity"
    case .invalidRecord(.callerSuppliedRevision(let revision)):
      return "Record-store revisions are assigned by the store, not callers: \(revision.rawValue)"
    case .invalidQuery(.nonPositiveLimit(let limit)):
      return "A record-store page limit must be positive: \(limit)"
    case .invalidQuery(.invalidContinuationToken):
      return "The record-store continuation token is invalid"
    case .invalidQuery(.continuationTokenQueryMismatch):
      return "The record-store continuation token belongs to a different query"
    case .unavailable:
      return "The record store is unavailable"
    }
  }
}

/// Storage-neutral persistence for canonical `MarkdownRecord` values.
///
/// Implementations own opaque revisions and must compare revisions atomically with
/// replacement and deletion. Cancellation is propagated as `CancellationError`.
public protocol RecordStore: Sendable {
  /// Fetches a canonical record by stable identity.
  ///
  /// - Parameter identity: Stable identity of the requested record.
  /// - Returns: The current canonical stored record.
  /// - Throws: ``RecordStoreError/notFound(_:)`` when the identity is absent.
  func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord

  /// Enumerates one deterministic, bounded page of canonical records.
  ///
  /// - Parameter query: Search root, page limit, and optional continuation position.
  /// - Returns: One page and an opaque token when more records remain.
  func records(matching query: RecordStoreQuery) async throws -> RecordStorePage

  /// Creates a canonical record and assigns its initial opaque revision.
  ///
  /// - Parameter record: Record with a stable identity and no caller-supplied revision.
  /// - Returns: The stored record, including its assigned revision.
  func create(_ record: MarkdownRecord) async throws -> MarkdownRecord

  /// Replaces a canonical record when its current revision matches the precondition.
  ///
  /// - Parameters:
  ///   - record: Complete replacement with the same stable identity and no revision.
  ///   - expectedRevision: Revision that must still be current when the write commits.
  /// - Returns: The stored replacement with a newly assigned revision.
  func replace(
    _ record: MarkdownRecord,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws -> MarkdownRecord

  /// Deletes a canonical record when its current revision matches the precondition.
  ///
  /// - Parameters:
  ///   - identity: Stable identity of the record to remove.
  ///   - expectedRevision: Revision that must still be current when deletion commits.
  func delete(
    identity: MarkdownRecordIdentity,
    ifRevision expectedRevision: MarkdownRecordRevision
  ) async throws
}
