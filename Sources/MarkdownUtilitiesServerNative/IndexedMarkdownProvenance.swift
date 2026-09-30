import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer

extension IndexedMarkdownRepository {
  /// Refreshes the collection and explains a UUID collision without changing source files.
  ///
  /// Acquires the collection writer lease and includes holders outside exposed
  /// resource selections. Parse failures or more than 256 holders prevent an
  /// ownership recommendation. Refreshing may update the disposable index.
  ///
  /// - Parameter uuid: A UUID spelling accepted by Foundation's UUID initializer.
  /// - Returns: A shared collision explanation, never authorization to repair files.
  /// - Throws: A `MarkdownMutationError` with code `uuid.invalid` if the UUID is
  ///   invalid or persistent identity is not configured. Lease, refresh, record
  ///   enumeration, and database errors propagate to the caller.
  public func explainUUIDCollision(_ uuid: String) async throws -> UUIDCollisionExplanation {
    guard let value = UUID(uuidString: uuid), let identity = plan.persistentIdentity else {
      throw MarkdownMutationError(422, "uuid.invalid", "Supply a UUID and configure persistent identity.")
    }
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    try await refresh(lease: lease)
    let policy = MarkdownRecordIdentityPolicy(source: .frontmatter(path: identity.path, format: .uuid))
    var token: RecordStoreContinuationToken?
    var candidates: [UUIDCollisionCandidate] = []
    var complete = true
    repeat {
      let page = try await records(matching: .init(limit: 1, continuationToken: token))
      for record in page.records {
        let analyzed = await MarkdownRecordAnalyzer.analyze(record)
        if analyzed.parseDiagnostics.contains(where: { $0.severity == .error }) { complete = false }
        if MarkdownRecordIdentityIndex.assess(analyzed, policy: policy).primaryIdentity?.rawValue == value.uuidString.lowercased(),
          let path = record.context.path, let revision = record.revision {
          guard candidates.count < 256 else {
            return UUIDCollisionAssessor.assess(candidates,
              evidence: try database.provenance(paths: candidates.map(\.path)), completeHolderSet: false)
          }
          candidates.append(.init(path: path.rawValue, revision: revision.rawValue))
        }
      }
      token = page.continuationToken
    } while token != nil
    let evidence = candidates.isEmpty
      ? DocumentProvenanceEvidence(epoch: try database.provenanceEpoch(), observations: [], events: [])
      : try database.provenance(paths: candidates.map(\.path))
    return UUIDCollisionAssessor.assess(candidates, evidence: evidence, completeHolderSet: complete)
  }
}
