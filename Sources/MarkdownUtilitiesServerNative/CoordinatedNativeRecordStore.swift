import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer

/// A write-capable RecordStore exists only inside an acquired collection lease.
/// The coordinator surrounds these atomic source operations with validation,
/// durable intent, and publication. It is not exposed through the read repository.
struct CoordinatedNativeRecordStore: RecordStore {
  let repository: IndexedMarkdownRepository
  let root: URL
  let lease: CollectionWriterLease

  func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    try await repository.record(for: identity)
  }
  func records(matching query: RecordStoreQuery) async throws -> RecordStorePage {
    try await repository.records(matching: query)
  }
  func create(_ record: MarkdownRecord) async throws -> MarkdownRecord {
    try persist(record, revision: nil)
  }
  func replace(_ record: MarkdownRecord, ifRevision expectedRevision: MarkdownRecordRevision) async throws -> MarkdownRecord {
    try persist(record, revision: expectedRevision)
  }
  func delete(identity: MarkdownRecordIdentity, ifRevision expectedRevision: MarkdownRecordRevision) async throws {
    guard lease.root == root else { throw RecordStoreError.unavailable }
    try NativeMutationFiles.persist(url: NativeMutationFiles.url(root: root, path: MarkdownRecordPath(identity.rawValue)),
      content: nil, expected: expectedRevision)
  }
  private func persist(_ record: MarkdownRecord, revision: MarkdownRecordRevision?) throws -> MarkdownRecord {
    guard lease.root == root else { throw RecordStoreError.unavailable }
    guard let identity = record.identity else { throw RecordStoreError.invalidRecord(.missingIdentity) }
    if let supplied = record.revision { throw RecordStoreError.invalidRecord(.callerSuppliedRevision(supplied)) }
    let path = try MarkdownRecordPath(identity.rawValue)
    guard record.context.path == path else { throw RecordStoreError.unavailable }
    let data = Data(record.content.utf8)
    guard data.count <= 8 * 1024 * 1024 else { throw MarkdownMutationError(413, "record.too-large", "Source exceeds 8 MiB.") }
    try NativeMutationFiles.persist(url: NativeMutationFiles.url(root: root, path: path), content: data, expected: revision, modificationDate: record.context.modificationDate)
    var committed = record
    committed.revision = .init(rawValue: IndexFingerprint.hash(data))
    return committed
  }
}
