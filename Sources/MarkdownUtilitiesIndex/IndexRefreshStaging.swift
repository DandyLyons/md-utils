import Foundation
import GRDB

struct CachedIndexCandidate {
    var file: CachedIndexFile?
    var assessmentReusable: Bool
}

struct StagedIndexChange {
    var file: IndexFileChange
    var assessments: [String: IndexAssessment]

    var payloadBytes: Int {
        var bytes = file.path.utf8.count + file.hash.utf8.count
            + file.evaluation.metadata.utf8.count + file.evaluation.body.utf8.count
            + file.evaluation.parseState.utf8.count
        for (id, assessment) in assessments {
            bytes += id.utf8.count + assessment.status.utf8.count + assessment.detail.utf8.count
            for diagnostic in assessment.diagnostics {
                bytes += diagnostic.category.utf8.count + diagnostic.severity.utf8.count
                    + diagnostic.code.utf8.count + diagnostic.location.utf8.count + diagnostic.message.utf8.count
            }
        }
        return bytes
    }
}

extension SQLiteIndexDatabase {
    private func requireGeneration(_ generation: Int, in database: Database) throws {
        guard try Int.fetchOne(database, sql: "SELECT value FROM index_metadata WHERE key='generation'") == generation else {
            throw SQLiteIndexError(message: "Another index update started during this scan; retry the update.")
        }
    }

    func discardStagedRefresh(generation: Int) throws {
        try databaseQueue.write { database in
            for table in ["refresh_diagnostics", "refresh_assessments", "refresh_files", "refresh_seen", "refresh_scopes"] {
                try database.execute(sql: "DELETE FROM \(table) WHERE generation=?", arguments: [generation])
            }
        }
    }

    func beginStagedRefresh(scopes: [IndexScope], fingerprint: String) throws -> Int {
        try databaseQueue.write { database in
            try database.execute(sql: "DELETE FROM refresh_diagnostics; DELETE FROM refresh_assessments; DELETE FROM refresh_files; DELETE FROM refresh_seen; DELETE FROM refresh_scopes")
            let generation = (try Int.fetchOne(database,
                sql: "SELECT value FROM index_metadata WHERE key='generation'") ?? 0) + 1
            try database.execute(sql: "UPDATE index_metadata SET value=? WHERE key='generation'",
                arguments: [String(generation)])
            try database.execute(sql: "INSERT INTO index_metadata VALUES('last_started_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [String(Date().timeIntervalSince1970)])
            for scope in scopes {
                let reusable = try Bool.fetchOne(database, sql: "SELECT state='complete' AND fingerprint=? FROM scopes WHERE id=?",
                    arguments: [fingerprint, scope.id]) ?? false
                try database.execute(sql: "INSERT INTO refresh_scopes VALUES(?,?,?)",
                    arguments: [generation, scope.id, reusable])
                let definition = String(decoding: try JSONEncoder().encode(scope), as: UTF8.self)
                try database.execute(sql: """
                    INSERT INTO scopes(id,definition,state) VALUES(?,?,'updating')
                    ON CONFLICT(id) DO UPDATE SET definition=excluded.definition,state='updating',error=NULL
                    """, arguments: [scope.id, definition])
            }
            return generation
        }
    }

    func stageSeen(generation: Int, scopeID: String, paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try databaseQueue.write { database in
            try requireGeneration(generation, in: database)
            for path in paths {
                try database.execute(sql: "INSERT OR IGNORE INTO refresh_seen VALUES(?,?,?)",
                    arguments: [generation, scopeID, path])
            }
        }
    }

    func stagedCandidatePaths(generation: Int, after: String?, limit: Int) throws -> [String] {
        try databaseQueue.read { database in
            if let after {
                return try String.fetchAll(database, sql: """
                    SELECT DISTINCT path FROM refresh_seen
                    WHERE generation=? AND path>? ORDER BY path LIMIT ?
                    """, arguments: [generation, after, limit])
            }
            return try String.fetchAll(database, sql: """
                SELECT DISTINCT path FROM refresh_seen WHERE generation=? ORDER BY path LIMIT ?
                """, arguments: [generation, limit])
        }
    }

    func stagedScopeIDs(generation: Int, path: String) throws -> [String] {
        try databaseQueue.read {
            // Otherwise SQLite may choose the (generation,scope_id,path) primary
            // key to satisfy ORDER BY and scan the entire generation for each file.
            try String.fetchAll($0, sql: "SELECT scope_id FROM refresh_seen INDEXED BY refresh_seen_path WHERE generation=? AND path=? ORDER BY scope_id",
                arguments: [generation, path])
        }
    }

    func cachedCandidate(generation: Int, scopeID: String, path: String) throws -> CachedIndexCandidate {
        try databaseQueue.read { database in
            let row = try Row.fetchOne(database, sql: "SELECT mtime,size,hash,state FROM files WHERE path=?", arguments: [path])
            let file = row.map { CachedIndexFile(mtime: $0["mtime"], size: $0["size"], hash: $0["hash"], state: $0["state"]) }
            let reusable = try Bool.fetchOne(database, sql: """
                SELECT EXISTS(SELECT 1 FROM assessments a JOIN refresh_scopes s ON s.scope_id=a.scope_id
                  WHERE a.scope_id=? AND a.path=? AND s.generation=? AND s.reusable=1
                    AND a.status!='evaluation-error')
                """, arguments: [scopeID, path, generation]) ?? false
            return CachedIndexCandidate(file: file, assessmentReusable: reusable)
        }
    }

    func stageChanges(generation: Int, changes: [StagedIndexChange]) throws {
        guard !changes.isEmpty else { return }
        try databaseQueue.write { database in
            try requireGeneration(generation, in: database)
            let policy = try storagePolicy(database)
            for change in changes {
                let file = change.file
                let body: String? = policy.bodyMode == .fts ? file.evaluation.body : nil
                try database.execute(sql: """
                    INSERT INTO refresh_files VALUES(?,?,?,?,?,?,?,?)
                    ON CONFLICT(generation,path) DO UPDATE SET
                      mtime=excluded.mtime,size=excluded.size,hash=excluded.hash,state=excluded.state,
                      metadata=excluded.metadata,body=excluded.body
                    """, arguments: [generation, file.path, file.mtime, file.size, file.hash,
                        file.evaluation.parseState, file.evaluation.metadata, body])
                for (scopeID, assessment) in change.assessments {
                    try database.execute(sql: """
                        INSERT INTO refresh_assessments VALUES(?,?,?,?,?,?)
                        ON CONFLICT(generation,scope_id,path) DO UPDATE SET
                          selected=excluded.selected,status=excluded.status,detail=excluded.detail
                        """, arguments: [generation, scopeID, file.path, assessment.selected, assessment.status, assessment.detail])
                    try database.execute(sql: "DELETE FROM refresh_diagnostics WHERE generation=? AND scope_id=? AND path=?",
                        arguments: [generation, scopeID, file.path])
                    for diagnostic in assessment.diagnostics {
                        try database.execute(sql: "INSERT INTO refresh_diagnostics VALUES(?,?,?,?,?,?,?,?)",
                            arguments: [generation, scopeID, file.path, diagnostic.category, diagnostic.severity,
                                diagnostic.code, diagnostic.location, diagnostic.message])
                    }
                }
            }
        }
    }

    func commitStagedRefresh(scopes: [IndexScope], errors: [String: String], fingerprint: String,
        generation: Int) throws {
        try databaseQueue.write { database in
            guard try Int.fetchOne(database,
                sql: "SELECT value FROM index_metadata WHERE key='generation'") == generation else {
                throw SQLiteIndexError(message: "Another index update started during this scan; retry the update.")
            }
            for scope in scopes where errors[scope.id] == nil {
                try database.execute(sql: """
                    DELETE FROM assessments WHERE scope_id=? AND NOT EXISTS(
                      SELECT 1 FROM refresh_seen r WHERE r.generation=? AND r.scope_id=? AND r.path=assessments.path)
                    """, arguments: [scope.id, generation, scope.id])
            }
            try database.execute(sql: """
                INSERT INTO files(path,mtime,size,hash,state)
                SELECT path,mtime,size,hash,state FROM refresh_files WHERE generation=?
                ON CONFLICT(path) DO UPDATE SET mtime=excluded.mtime,size=excluded.size,
                  hash=excluded.hash,state=excluded.state;
                """, arguments: [generation])
            try database.execute(sql: """
                DELETE FROM assessments WHERE EXISTS(
                  SELECT 1 FROM refresh_assessments r WHERE r.generation=?
                    AND r.scope_id=assessments.scope_id AND r.path=assessments.path);
                INSERT INTO assessments(scope_id,path,selected,status,detail)
                SELECT scope_id,path,selected,status,detail FROM refresh_assessments WHERE generation=?;
                INSERT INTO diagnostics(scope_id,path,category,severity,code,location,message)
                SELECT scope_id,path,category,severity,code,location,message
                  FROM refresh_diagnostics WHERE generation=?;
                """, arguments: [generation, generation, generation])
            let policy = try storagePolicy(database)
            let metadataFunction = policy.metadataEncoding == .jsonb ? "jsonb" : "json"
            try database.execute(sql: """
                INSERT INTO documents(path,metadata,body)
                SELECT path,\(metadataFunction)(metadata),body FROM refresh_files WHERE generation=?
                ON CONFLICT(path) DO UPDATE SET metadata=excluded.metadata,body=excluded.body;
                """, arguments: [generation])
            for scope in scopes {
                try database.execute(sql: "UPDATE scopes SET state=?,error=?,fingerprint=? WHERE id=?",
                    arguments: [errors[scope.id] == nil ? "complete" : "incomplete", errors[scope.id], fingerprint, scope.id])
            }
            try database.execute(sql: "DELETE FROM documents WHERE NOT EXISTS(SELECT 1 FROM assessments a WHERE a.path=documents.path AND a.selected=1)")
            try database.execute(sql: "DELETE FROM files WHERE NOT EXISTS(SELECT 1 FROM assessments a WHERE a.path=files.path)")
            try database.execute(sql: "INSERT INTO index_metadata VALUES('runtime',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [IndexFingerprint.runtimeVersion])
            let stagedFailures = try Bool.fetchOne(database, sql: """
                SELECT EXISTS(SELECT 1 FROM refresh_files WHERE generation=? AND state!='ok')
                  OR EXISTS(SELECT 1 FROM refresh_assessments WHERE generation=? AND status='evaluation-error')
                """, arguments: [generation, generation]) ?? false
            if errors.isEmpty && !stagedFailures {
                try database.execute(sql: "INSERT INTO index_metadata VALUES('last_completed_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [String(Date().timeIntervalSince1970)])
            }
            try refreshTypeViews(database)
            try database.execute(sql: "INSERT INTO index_metadata VALUES('published_generation',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [String(generation)])
            try database.execute(sql: "DELETE FROM refresh_diagnostics; DELETE FROM refresh_assessments; DELETE FROM refresh_files; DELETE FROM refresh_seen; DELETE FROM refresh_scopes")
        }
    }

}
