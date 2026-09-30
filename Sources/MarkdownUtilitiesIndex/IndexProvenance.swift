import Foundation
import GRDB
import MarkdownUtilitiesCore

extension SQLiteIndexDatabase {
    /// Returns the cache lifetime identifier, or an empty string if none is stored.
    ///
    /// Full rebuilds replace the epoch. Do not replay older receipts into a new
    /// epoch as if their events were part of its observation history.
    /// - Throws: A database read error.
    public func provenanceEpoch() throws -> String {
        try databaseQueue.read { try String.fetchOne($0, sql: "SELECT value FROM index_metadata WHERE key='epoch'") ?? "" }
    }
    static func createProvenance(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE observations(
              path TEXT PRIMARY KEY, first_revision TEXT, last_revision TEXT,
              first_generation INTEGER NOT NULL, last_generation INTEGER NOT NULL,
              first_at REAL NOT NULL, last_at REAL NOT NULL, verified INTEGER NOT NULL,
              complete INTEGER NOT NULL, absent INTEGER NOT NULL DEFAULT 0, gap INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE managed_events(id TEXT PRIMARY KEY, path TEXT NOT NULL, source_path TEXT,
              observed_at REAL NOT NULL, payload BLOB NOT NULL);
            CREATE INDEX managed_events_path ON managed_events(path);
            CREATE INDEX managed_events_source ON managed_events(source_path);
            CREATE TABLE refresh_verified(generation INTEGER NOT NULL,path TEXT NOT NULL,
              PRIMARY KEY(generation,path));
            """)
    }

    func stageVerified(generation: Int, path: String) throws {
        try databaseQueue.write {
            try $0.execute(sql: "INSERT OR IGNORE INTO refresh_verified VALUES(?,?)", arguments: [generation, path])
        }
    }

    /// Runs inside the same publication transaction as files and assessments.
    func publishObservations(_ db: Database, generation: Int, complete: Bool) throws {
        let now = Date().timeIntervalSince1970
        try db.execute(sql: """
            INSERT INTO observations(path,first_revision,last_revision,first_generation,last_generation,
              first_at,last_at,verified,complete)
            SELECT r.path,NULLIF(f.hash,''),NULLIF(f.hash,''),?,?,?, ?,
              EXISTS(SELECT 1 FROM refresh_verified v WHERE v.generation=? AND v.path=r.path) AND f.state='ok',?
            FROM (SELECT DISTINCT path FROM refresh_seen WHERE generation=?) r JOIN files f USING(path)
            WHERE true
            ON CONFLICT(path) DO UPDATE SET last_revision=excluded.last_revision,
              last_generation=excluded.last_generation,last_at=excluded.last_at,
              verified=excluded.verified,complete=excluded.complete,absent=0,
              gap=observations.gap OR observations.absent OR NOT observations.complete;
            UPDATE observations SET absent=1,gap=1 WHERE NOT EXISTS(SELECT 1 FROM files f WHERE f.path=observations.path);
            """, arguments: [generation, generation, now, now, generation, complete, generation])
        // Live summaries are O(current paths). Removed paths and managed events
        // have fixed retention; discarded history can never increase confidence.
        let pruned = try Int.fetchOne(db, sql: "SELECT count(*) FROM observations WHERE absent=1") ?? 0
        if pruned > 10_000 {
            try db.execute(sql: "DELETE FROM observations WHERE path IN (SELECT path FROM observations WHERE absent=1 ORDER BY last_at DESC,path LIMIT -1 OFFSET 10000)")
            try db.execute(sql: "INSERT OR REPLACE INTO index_metadata VALUES('provenance_pruned','1')")
        }
        try db.execute(sql: "DELETE FROM refresh_verified WHERE generation=?", arguments: [generation])
    }

    /// Retains a confirmed managed event, ignoring an already recorded receipt identifier.
    ///
    /// The caller must establish confirmation and match the receipt's provenance
    /// epoch to the current cache. This method does not verify the source file.
    /// Only the newest 10,000 events are retained; pruning marks the epoch's
    /// history as incomplete for subsequent collision assessment.
    /// - Parameter event: Evidence from a confirmed mutation receipt.
    /// - Throws: An index error for encoded events larger than 32 KiB, or an
    ///   encoding or database error.
    public func recordManagedEvent(_ event: ManagedDocumentEvent) throws {
        let payload = try JSONEncoder().encode(event)
        guard payload.count <= 32_768 else { throw SQLiteIndexError(message: "Managed evidence exceeds 32 KiB.") }
        try databaseQueue.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO managed_events VALUES(?,?,?,?,?)",
                arguments: [event.id, event.path, event.sourcePath, event.observedAt, payload])
            if try Int.fetchOne(db, sql: "SELECT count(*) FROM managed_events") ?? 0 > 10_000 {
                try db.execute(sql: "DELETE FROM managed_events WHERE id IN (SELECT id FROM managed_events ORDER BY observed_at DESC,id LIMIT -1 OFFSET 10000)")
                try db.execute(sql: "INSERT OR REPLACE INTO index_metadata VALUES('provenance_pruned','1')")
            }
        }
    }

    /// Reads bounded evidence for paths in an already assessed collision group.
    ///
    /// This query does not refresh files. Observations are sorted by path; events
    /// are newest first, with receipt identifiers breaking timestamp ties. Missing
    /// observations mean unknown history. Events may mention other paths as well.
    /// - Parameters:
    ///   - paths: One to 256 collection-relative paths.
    ///   - limit: The maximum number of matching events, from one to 1,000.
    /// - Returns: Evidence marked as truncated when more matching events exist.
    /// - Throws: An index error for invalid bounds, or a database or decoding error.
    public func provenance(paths: [String], limit: Int = 256) throws -> DocumentProvenanceEvidence {
        guard !paths.isEmpty, paths.count <= 256, (1...1_000).contains(limit) else {
            throw SQLiteIndexError(message: "Request 1–256 provenance paths and an evidence limit of 1–1000.")
        }
        return try databaseQueue.read { db in
            let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ",")
            let observations = try Row.fetchAll(db, sql: "SELECT * FROM observations WHERE path IN (\(placeholders)) ORDER BY path", arguments: StatementArguments(paths))
                .map { row in DocumentObservation(path: row["path"], firstRevision: row["first_revision"], lastRevision: row["last_revision"],
                    firstGeneration: row["first_generation"], lastGeneration: row["last_generation"],
                    firstObservedAt: row["first_at"], lastObservedAt: row["last_at"], verified: row["verified"],
                    completeScan: row["complete"], absent: row["absent"], historyGap: row["gap"]) }
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM managed_events WHERE path IN (\(placeholders)) OR source_path IN (\(placeholders)) ORDER BY observed_at DESC,id LIMIT ?",
                arguments: StatementArguments(paths + paths) + StatementArguments([limit + 1]))
            let events = try rows.prefix(limit).map { try JSONDecoder().decode(ManagedDocumentEvent.self, from: $0["payload"]) }
            return DocumentProvenanceEvidence(epoch: try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'") ?? "",
                observations: observations, events: events,
                historyPruned: try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='provenance_pruned'") == "1",
                truncated: rows.count > limit)
        }
    }
}
