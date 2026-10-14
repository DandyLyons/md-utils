import Foundation
import GRDB

/// Disposable evidence, accessible only after the native host verifies its input certificate.
/// Payloads are staged in 256 KiB transactions; publication switches the manifest and chunks
/// together. Retention is capped at four requests and 64 MiB across all published requests.
extension SQLiteIndexDatabase {
    package static let relationshipCacheBytes = 64 * 1_024 * 1_024
    package static let relationshipChunkBytes = 256 * 1_024

    static func createRelationshipCache(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE relationship_cache(
              request TEXT PRIMARY KEY, certificate TEXT NOT NULL, epoch TEXT NOT NULL,
              generation INTEGER NOT NULL, bytes INTEGER NOT NULL, hash TEXT NOT NULL);
            CREATE TABLE relationship_chunks(
              request TEXT NOT NULL REFERENCES relationship_cache(request) ON DELETE CASCADE,
              ordinal INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(request,ordinal));
            CREATE TABLE refresh_relationship_chunks(
              token TEXT NOT NULL, ordinal INTEGER NOT NULL, payload BLOB NOT NULL,
              PRIMARY KEY(token,ordinal));
            """)
    }

    package func relationshipEpoch(generation: Int) throws -> String {
        try databaseQueue.read { db in
            try Self.requireRelationshipGeneration(db, generation: generation)
            guard let epoch = try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'") else {
                throw SQLiteIndexError(message: "Missing index epoch; rebuild the index.")
            }
            return epoch
        }
    }

    private static func requireRelationshipGeneration(_ db: Database, generation: Int, epoch: String? = nil) throws {
        try Task.checkCancellation()
        guard try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='generation'") == generation,
              try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='published_generation'") == generation else {
            throw SQLiteIndexError(message: "Relationship snapshot was superseded; retry assessment.")
        }
        if let epoch, try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'") != epoch {
            throw SQLiteIndexError(message: "Relationship snapshot predates index rebuild; retry assessment.")
        }
    }

    package func relationshipCached(request: String, certificate: String, epoch: String, generation: Int) throws -> Data? {
        try databaseQueue.read { db in
            try Self.requireRelationshipGeneration(db, generation: generation, epoch: epoch)
            guard let row = try Row.fetchOne(db, sql: "SELECT bytes,hash FROM relationship_cache WHERE request=? AND certificate=? AND epoch=?",
                arguments: [request, certificate, epoch]) else { return nil }
            let count: Int = row["bytes"]
            guard count >= 0, count <= Self.relationshipCacheBytes else { return nil }
            var data = Data()
            let cursor = try Row.fetchCursor(db, sql: "SELECT ordinal,length(payload) AS bytes,payload FROM relationship_chunks WHERE request=? ORDER BY ordinal", arguments: [request])
            var ordinal = 0
            while let chunk = try cursor.next() {
                try Task.checkCancellation()
                let index: Int = chunk["ordinal"]
                let size: Int = chunk["bytes"]
                // Canonical chunk sizes also bound cursor work on a corrupt cache.
                guard index == ordinal, size > 0,
                      size == min(Self.relationshipChunkBytes, count - data.count) else { return nil }
                let payload: Data = chunk["payload"]
                data.append(payload)
                ordinal += 1
            }
            guard data.count == count, IndexFingerprint.hash(data) == row["hash"] as String else { return nil }
            return data
        }
    }

    /// The caller holds the collection writer lease and has reverified source/definition evidence.
    package func publishRelationship(request: String, certificate: String, epoch: String, generation: Int,
        data: Data, verify: () throws -> Void = {},
    ) throws {
        guard data.count <= Self.relationshipCacheBytes else { return }
        let token = UUID().uuidString
        defer {
            try? databaseQueue.write { db in
                try db.execute(sql: "DELETE FROM refresh_relationship_chunks WHERE token=?", arguments: [token])
            }
        }
        try databaseQueue.write { db in
            try Self.requireRelationshipGeneration(db, generation: generation, epoch: epoch)
            // The writer lease excludes other staging owners; reclaim interrupted publications.
            try db.execute(sql: "DELETE FROM refresh_relationship_chunks")
        }
        for offset in stride(from: 0, to: data.count, by: Self.relationshipChunkBytes) {
            try databaseQueue.write { db in
                try Self.requireRelationshipGeneration(db, generation: generation, epoch: epoch)
                try db.execute(sql: "INSERT INTO refresh_relationship_chunks VALUES(?,?,?)",
                    arguments: [token, offset / Self.relationshipChunkBytes,
                        data.subdata(in: offset..<min(data.count, offset + Self.relationshipChunkBytes))])
            }
        }
        try verify()
        try databaseQueue.write { db in
            try Self.requireRelationshipGeneration(db, generation: generation, epoch: epoch)
            try db.execute(sql: "DELETE FROM relationship_cache WHERE request=?", arguments: [request])
            while try Bool.fetchOne(db, sql: "SELECT count(*)>=4 OR coalesce(sum(bytes),0)>? FROM relationship_cache",
                arguments: [Self.relationshipCacheBytes - data.count]) == true {
                try db.execute(sql: "DELETE FROM relationship_cache WHERE request=(SELECT request FROM relationship_cache ORDER BY generation,request LIMIT 1)")
            }
            try db.execute(sql: "INSERT INTO relationship_cache VALUES(?,?,?,?,?,?)",
                arguments: [request, certificate, epoch, generation, data.count, IndexFingerprint.hash(data)])
            try db.execute(sql: "INSERT INTO relationship_chunks SELECT ?,ordinal,payload FROM refresh_relationship_chunks WHERE token=?",
                arguments: [request, token])
        }
    }
}
