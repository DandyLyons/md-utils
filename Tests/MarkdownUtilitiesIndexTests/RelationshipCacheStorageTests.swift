import Foundation
import GRDB
import Testing
@testable import MarkdownUtilitiesIndex

struct RelationshipCacheStorageTests {
  private func fixture() throws -> (SQLiteIndexDatabase, String) {
    let db = try SQLiteIndexDatabase(path: ":memory:")
    try db.prepareCollection(root: "/vault/")
    try db.serverWrite { connection in
      try connection.execute(sql: "INSERT INTO index_metadata VALUES('published_generation','0')")
    }
    return (db, try db.relationshipEpoch(generation: 0))
  }

  @Test func chunksRoundTripAndCorruptionIsAMiss() throws {
    let (db, epoch) = try fixture()
    let data = Data(repeating: 42, count: SQLiteIndexDatabase.relationshipChunkBytes + 3)
    try db.publishRelationship(request: "a", certificate: "c", epoch: epoch, generation: 0, data: data)
    #expect(try db.relationshipCached(request: "a", certificate: "c", epoch: epoch, generation: 0) == data)
    #expect(try db.relationshipCached(request: "a", certificate: "other", epoch: epoch, generation: 0) == nil)
    try db.serverWrite { try $0.execute(sql: "INSERT INTO relationship_chunks VALUES('a',2,x'')") }
    #expect(try db.relationshipCached(request: "a", certificate: "c", epoch: epoch, generation: 0) == nil)
    try db.serverWrite { try $0.execute(sql: "DELETE FROM relationship_chunks WHERE ordinal=2") }
    try db.serverWrite { try $0.execute(sql: "DELETE FROM relationship_chunks WHERE ordinal=0") }
    #expect(try db.relationshipCached(request: "a", certificate: "c", epoch: epoch, generation: 0) == nil)
  }

  @Test func failedPublicationPreservesPreviousEvidenceAndCleansStaging() throws {
    let (db, epoch) = try fixture()
    let original = Data("original".utf8)
    try db.publishRelationship(request: "a", certificate: "old", epoch: epoch, generation: 0, data: original)
    #expect(throws: CancellationError.self) {
      try db.publishRelationship(request: "a", certificate: "new", epoch: epoch, generation: 0,
        data: Data("replacement".utf8), verify: { throw CancellationError() })
    }
    #expect(try db.relationshipCached(request: "a", certificate: "old", epoch: epoch, generation: 0) == original)
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM refresh_relationship_chunks") } == 0)
  }

  @Test func epochGenerationAndHostInvalidationRejectStaleReaders() throws {
    let (db, epoch) = try fixture()
    try db.publishRelationship(request: "a", certificate: "c", epoch: epoch, generation: 0, data: Data())
    #expect(throws: SQLiteIndexError.self) {
      try db.relationshipCached(request: "a", certificate: "c", epoch: "rebuilt", generation: 0)
    }
    try db.invalidate(message: "mutation refresh failed")
    #expect(throws: SQLiteIndexError.self) {
      try db.relationshipCached(request: "a", certificate: "c", epoch: epoch, generation: 0)
    }
    #expect(throws: SQLiteIndexError.self) {
      try db.publishRelationship(request: "b", certificate: "c", epoch: epoch, generation: 0, data: Data())
    }
  }

  @Test func retentionIsBoundedAndAbandonedStagingIsReclaimed() throws {
    let (db, epoch) = try fixture()
    try db.serverWrite { try $0.execute(sql: "INSERT INTO refresh_relationship_chunks VALUES('abandoned',0,x'00')") }
    for index in 0..<7 {
      try db.publishRelationship(request: String(index), certificate: "c", epoch: epoch, generation: 0, data: Data([42]))
    }
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM relationship_cache") } == 4)
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM relationship_chunks") } == 4)
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM refresh_relationship_chunks") } == 0)
  }

  @Test func byteBudgetEvictsAndOversizedPayloadIsNotStaged() throws {
    let (db, epoch) = try fixture()
    let data = Data(repeating: 0, count: SQLiteIndexDatabase.relationshipCacheBytes / 2 + 1)
    for request in ["first", "second"] {
      try db.publishRelationship(request: request, certificate: "c", epoch: epoch, generation: 0, data: data)
    }
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM relationship_cache") } == 1)
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT sum(bytes) FROM relationship_cache") } == data.count)
    try db.publishRelationship(request: "oversized", certificate: "c", epoch: epoch, generation: 0,
      data: Data(repeating: 0, count: SQLiteIndexDatabase.relationshipCacheBytes + 1))
    #expect(try db.relationshipCached(request: "oversized", certificate: "c", epoch: epoch, generation: 0) == nil)
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM refresh_relationship_chunks") } == 0)
  }

  @Test func supersededPublicationNeverReplacesManifest() throws {
    let (db, epoch) = try fixture()
    try db.publishRelationship(request: "a", certificate: "old", epoch: epoch, generation: 0, data: Data([1]))
    #expect(throws: SQLiteIndexError.self) {
      try db.publishRelationship(request: "a", certificate: "new", epoch: epoch, generation: 0, data: Data([2]),
        verify: { try db.invalidate(message: "Concurrent publication") })
    }
    #expect(try db.serverRead { try String.fetchOne($0, sql: "SELECT certificate FROM relationship_cache WHERE request='a'") } == "old")
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM refresh_relationship_chunks") } == 0)
  }
}
