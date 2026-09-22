import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesServer
import PathKit
import SystemPackage

/// Native file-backed repository. Only bounded pages and one refresh candidate hold bodies.
public actor IndexedMarkdownRepository: MarkdownServerReadRepository, RecordStore {
  public nonisolated let resourceNames: [String]
  public nonisolated let plan: EndpointPlan
  private let root: URL
  private let configurationFile: String?
  private let database: SQLiteIndexDatabase
  private let evaluator: IndexProjectEvaluator
  private let configurationSignature: Data
  private let projectionKey: String
  private var projecting = false
  private var restartRequired = false
  private var refreshFailure = false

  /// Offline contract composition reads a saved custom project-config path without
  /// creating, migrating, refreshing, or probing the index's body/metadata policy.
  public static func loadPlan(projectRoot: String, configurationFile: String? = nil) throws -> MarkdownServerPlanRuntime {
    let root = URL(fileURLWithPath: Path(projectRoot).absolute().string).resolvingSymlinksInPath()
    let configuration = try MarkdownServerProjectLoader(projectRoot: Path(root.path),
      configurationFile: configurationFile.map { Path($0) }).loadConfiguration()
    let cache = root.appendingPathComponent(".md-utils/index.sqlite")
    var configPath = root.appendingPathComponent(".md-utils/md-utils.json").path
    if FileManager.default.fileExists(atPath: cache.path) {
      var options = Configuration()
      options.readonly = true
      let queue = try DatabaseQueue(path: cache.path, configuration: options)
      if let saved = try queue.read({ db -> String? in
        guard try db.tableExists("index_metadata") else { return nil }
        return try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='config'")
      }) { configPath = saved }
    }
    let evaluator = try IndexProjectEvaluator(root: Path(root.path), configPath: Path(configPath))
    let plan = try EndpointPlanCompiler(ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]),
      typeRegistry: evaluator.types).compile(configuration)
    return MarkdownServerPlanRuntime(configuration: configuration, plan: plan)
  }

  public func isStale() async -> Bool {
    refreshFailure || ((try? hasOperationalFailure()) != false)
  }

  private func hasOperationalFailure() throws -> Bool {
    try database.serverRead { db in
      try Bool.fetchOne(db, sql: """
        SELECT EXISTS(SELECT 1 FROM scopes WHERE state!='complete')
          OR EXISTS(SELECT 1 FROM diagnostics WHERE code='index.read-or-evaluate')
        """) ?? true
    }
  }

  public init(projectRoot: String, configurationFile: String? = nil) throws {
    root = URL(fileURLWithPath: Path(projectRoot).absolute().string).resolvingSymlinksInPath()
    self.configurationFile = configurationFile
    let configuration = try MarkdownServerProjectLoader(projectRoot: Path(root.path), configurationFile: configurationFile.map { Path($0) }).loadConfiguration()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    configurationSignature = try encoder.encode(configuration)
    let cache = root.appendingPathComponent(".md-utils/", isDirectory: true)
    guard cache.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
      throw MarkdownServerReadError.unavailable
    }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    database = try SQLiteIndexDatabase(path: cache.appendingPathComponent("index.sqlite").path)
    try database.prepareCollection(root: root.path)
    let config = try database.configurationPath(nil) ?? cache.appendingPathComponent("md-utils.json").path
    evaluator = try IndexProjectEvaluator(root: Path(root.path), configPath: Path(config))
    plan = try EndpointPlanCompiler(ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]),
      typeRegistry: evaluator.types).compile(configuration)
    resourceNames = plan.resources.map(\.name)
    projectionKey = IndexFingerprint.combined(["server-projection-1", evaluator.fingerprint,
      String(decoding: try encoder.encode(plan), as: UTF8.self), "named-lookups-1"])
    if plan.resources.contains(where: \.searchEnabled), try database.storagePolicy().bodyMode != .fts {
      throw MarkdownServerReadError.searchUnavailable
    }
    try database.serverWrite { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS server_publications(plan TEXT PRIMARY KEY, generation TEXT NOT NULL, source TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS server_records(
          plan TEXT NOT NULL, generation TEXT NOT NULL, path TEXT NOT NULL, hash TEXT NOT NULL,
          body_bytes INTEGER NOT NULL, projection BLOB NOT NULL, mtime REAL NOT NULL DEFAULT 0,
          PRIMARY KEY(plan,generation,path));
        CREATE TABLE IF NOT EXISTS server_memberships(
          plan TEXT NOT NULL, generation TEXT NOT NULL, resource TEXT NOT NULL,
          path TEXT NOT NULL, identity TEXT,
          PRIMARY KEY(plan,generation,resource,path));
        CREATE INDEX IF NOT EXISTS server_identity ON server_memberships(plan,generation,resource,identity,path);
        CREATE TABLE IF NOT EXISTS server_lookups(
          plan TEXT NOT NULL, generation TEXT NOT NULL, resource TEXT NOT NULL, lookup TEXT NOT NULL,
          path TEXT NOT NULL, value TEXT, selected INTEGER NOT NULL, evidence BLOB NOT NULL,
          PRIMARY KEY(plan,generation,resource,lookup,path));
        CREATE INDEX IF NOT EXISTS server_lookup_value ON server_lookups(plan,generation,resource,lookup,value,path);
        """)
      if try !db.columns(in: "server_records").contains(where: { $0.name == "mtime" }) {
        try db.execute(sql: "ALTER TABLE server_records ADD COLUMN mtime REAL NOT NULL DEFAULT 0")
      }
    }
  }

  /// Startup and watcher refresh reuse exactly the CLI's staged index service.
  public func refresh() async throws {
    try checkConfiguration()
    do {
      let indexer = try CollectionIndexer(database: database, root: root)
      let report = try await indexer.updateMany(adding: IndexScope(), fingerprint: evaluator.fingerprint,
        verifyHashes: true, evaluate: evaluator.evaluate)
      if try hasOperationalFailure() {
        let detail = report.errors.isEmpty ? "Index refresh is incomplete; inspect md-utils index status." : report.errors.joined(separator: "; ")
        throw IndexProjectError(detail)
      }
      try await synchronize()
      refreshFailure = false
    } catch {
      refreshFailure = true
      throw error
    }
  }

  /// Owns the native watcher for the duration of the server's structured task.
  public nonisolated func watch(reportError: @Sendable @escaping (String) -> Void = { _ in }) async throws {
    #if os(macOS)
    let config = try database.configurationPath(nil) ?? root.appendingPathComponent(".md-utils/md-utils.json").path
    let serverConfig = MarkdownServerProjectLoader(projectRoot: Path(root.path),
      configurationFile: configurationFile.map { Path($0) }).configurationFile.string
    let watcher = try IndexWatcher(root: root, databasePath: database.path, additionalDirectories: [
      URL(fileURLWithPath: config).deletingLastPathComponent(),
      URL(fileURLWithPath: serverConfig).deletingLastPathComponent(),
    ])
    try await watcher.run(initialRefresh: false, refresh: { try await self.refresh() }, reportError: { reportError(String(describing: $0)) })
    #else
    // No filesystem discovery on unsupported platforms; requests adopt explicit CLI publications.
    while true { try await Task.sleep(for: .seconds(60)) }
    #endif
  }

  private func checkConfiguration() throws {
    guard !restartRequired else { throw MarkdownServerReadError.restartRequired }
    // Database contention is an operational failure, not evidence that definitions changed.
    let config = try database.configurationPath(nil) ?? root.appendingPathComponent(".md-utils/md-utils.json").path
    let bodyMode = try database.storagePolicy().bodyMode
    do {
      let configuration = try MarkdownServerProjectLoader(projectRoot: Path(root.path), configurationFile: configurationFile.map { Path($0) }).loadConfiguration()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let current = try IndexProjectEvaluator(root: Path(root.path), configPath: Path(config))
      guard try encoder.encode(configuration) == configurationSignature,
        current.fingerprint == evaluator.fingerprint else { throw MarkdownServerReadError.restartRequired }
      if plan.resources.contains(where: \.searchEnabled), bodyMode != .fts {
        throw MarkdownServerReadError.restartRequired
      }
    } catch {
      restartRequired = true
      throw MarkdownServerReadError.restartRequired
    }
  }

  private func sourceGeneration(_ db: Database) throws -> String {
    try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='published_generation'") ?? "0"
  }

  /// Disk-backed staging keeps the old publication readable until every candidate succeeds.
  private func synchronize() async throws {
    guard !projecting else { return }
    // Source syntax diagnostics remain visible through rule-selected records. Only
    // operational failures prevent publication; validation is not a refresh failure.
    guard try !hasOperationalFailure() else { throw MarkdownServerReadError.unavailable }
    let source = try database.serverRead { try sourceGeneration($0) }
    let existing = try database.serverRead {
      try String.fetchOne($0, sql: "SELECT source FROM server_publications WHERE plan=?", arguments: [projectionKey])
    }
    guard source != existing else { return }
    projecting = true
    defer { projecting = false }
    let generation = UUID().uuidString
    do {
      // SQLite copies reusable projections directly on disk; no Swift corpus array.
      try database.serverWrite { db in
        try db.execute(sql: """
          INSERT INTO server_records SELECT r.plan,?,r.path,r.hash,r.body_bytes,r.projection,r.mtime
          FROM server_records r JOIN files f ON f.path=r.path AND f.hash=r.hash AND f.mtime=r.mtime
          WHERE r.plan=? AND r.generation=(SELECT generation FROM server_publications WHERE plan=?);
          INSERT INTO server_memberships SELECT m.plan,?,m.resource,m.path,m.identity
          FROM server_memberships m JOIN server_records r ON r.plan=m.plan AND r.path=m.path AND r.generation=?
          WHERE m.plan=? AND m.generation=(SELECT generation FROM server_publications WHERE plan=?);
          """, arguments: [generation, projectionKey, projectionKey, generation, generation, projectionKey, projectionKey])
      }
      try database.serverWrite { db in
        try db.execute(sql: """
          INSERT INTO server_lookups
          SELECT l.plan,?,l.resource,l.lookup,l.path,l.value,l.selected,l.evidence
          FROM server_lookups l JOIN server_records r ON r.plan=l.plan AND r.path=l.path AND r.generation=?
          WHERE l.plan=? AND l.generation=(SELECT generation FROM server_publications WHERE plan=?)
          """, arguments: [generation, generation, projectionKey, projectionKey])
      }
      var after = ""
      while true {
        try Task.checkCancellation()
        let rows = try database.serverRead { db in
          guard try sourceGeneration(db) == source else { throw MarkdownServerReadError.generationChanged }
          return try Row.fetchAll(db, sql: """
            SELECT path,hash,mtime FROM files f WHERE path>? AND NOT EXISTS(
              SELECT 1 FROM server_records r WHERE r.plan=? AND r.generation=? AND r.path=f.path)
            ORDER BY path COLLATE BINARY LIMIT 128
            """, arguments: [after, projectionKey, generation])
        }
        guard !rows.isEmpty else { break }
        var pending: [ProjectionWrite] = []
        var pendingBytes = 0
        for row in rows {
          let path: String = row["path"]
          after = path
          guard ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { continue }
          let hash: String = row["hash"]
          let data = try readSource(path: path, hash: hash)
          guard let content = String(data: data, encoding: .utf8) else { throw MarkdownServerReadError.sourceChanged }
          let record = MarkdownRecord(identity: .init(rawValue: path), content: content,
            context: .init(path: try MarkdownRecordPath(path), modificationDate: Date(timeIntervalSince1970: row["mtime"])),
            revision: .init(rawValue: hash))
          let snapshot = try await MarkdownServerReadSnapshotBuilder(store: SingleRecordStore(record: record),
            plan: plan, ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]), typeRegistry: evaluator.types).build()
          if plan.persistentIdentity != nil || plan.resources.contains(where: { !$0.lookups.isEmpty }) {
            let analyzed = await MarkdownRecordAnalyzer.analyze(record)
            try database.serverWrite { db in
              for resource in plan.resources {
                let selected = snapshot.resource(named: resource.name)?.records.isEmpty == false
                for item in resource.lookupEvidence(analyzed: analyzed, persistentIdentity: plan.persistentIdentity)
                  where selected || item.uniqueWithin == .server {
                  try db.execute(sql: "INSERT INTO server_lookups VALUES(?,?,?,?,?,?,?,?)",
                    arguments: [projectionKey, generation, resource.name, item.lookup, path, item.value, selected,
                      try JSONEncoder().encode(item)])
                }
              }
            }
          }
          guard let projected = snapshot.resources.lazy.compactMap({ $0.records.first }).first else { continue }
          guard data.suffix(projected.body.utf8.count).elementsEqual(projected.body.utf8) else { throw MarkdownServerReadError.unavailable }
          let empty = replacing(projected, body: "")
          let payload = try JSONEncoder().encode(empty)
          if pendingBytes + payload.count > 8 * 1_024 * 1_024 {
            try write(pending, generation: generation)
            pending.removeAll(keepingCapacity: true)
            pendingBytes = 0
          }
          pending.append(ProjectionWrite(path: path, hash: hash, mtime: row["mtime"], bodyBytes: projected.body.utf8.count,
            payload: payload, memberships: projected.memberships))
          pendingBytes += payload.count
        }
        try write(pending, generation: generation)
      }
      try checkConfiguration()
      try database.serverWrite { db in
        guard try sourceGeneration(db) == source else { throw MarkdownServerReadError.generationChanged }
        let previous = try String.fetchOne(db, sql: "SELECT generation FROM server_publications WHERE plan=?", arguments: [projectionKey])
        try db.execute(sql: "INSERT INTO server_publications VALUES(?,?,?) ON CONFLICT(plan) DO UPDATE SET generation=excluded.generation,source=excluded.source",
          arguments: [projectionKey, generation, source])
        // Another server may be staging its own generation. Delete only the
        // publication being replaced, never another writer's unpublished rows.
        if let previous {
          try db.execute(sql: "DELETE FROM server_records WHERE plan=? AND generation=?", arguments: [projectionKey, previous])
          try db.execute(sql: "DELETE FROM server_memberships WHERE plan=? AND generation=?", arguments: [projectionKey, previous])
          try db.execute(sql: "DELETE FROM server_lookups WHERE plan=? AND generation=?", arguments: [projectionKey, previous])
        }
      }
    } catch {
      try? database.serverWrite { db in
        try db.execute(sql: "DELETE FROM server_records WHERE plan=? AND generation=?", arguments: [projectionKey, generation])
        try db.execute(sql: "DELETE FROM server_memberships WHERE plan=? AND generation=?", arguments: [projectionKey, generation])
        try db.execute(sql: "DELETE FROM server_lookups WHERE plan=? AND generation=?", arguments: [projectionKey, generation])
      }
      throw error
    }
  }

  private func prepareRead() async throws {
    try checkConfiguration()
    do {
      try await synchronize()
      refreshFailure = false
    }
    catch is CancellationError { throw CancellationError() }
    catch {
      refreshFailure = true
      let available = try database.serverRead {
        try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM server_publications WHERE plan=?)", arguments: [projectionKey]) ?? false
      }
      if !available { throw error }
    }
  }

  private struct ProjectionWrite {
    let path: String
    let hash: String
    let mtime: Double
    let bodyBytes: Int
    let payload: Data
    let memberships: [GenericMarkdownResourceMembership]
  }

  private func write(_ values: [ProjectionWrite], generation: String) throws {
    guard !values.isEmpty else { return }
    try database.serverWrite { db in
      for value in values {
        try db.execute(sql: "INSERT INTO server_records VALUES(?,?,?,?,?,?,?)",
          arguments: [projectionKey, generation, value.path, value.hash, value.bodyBytes, value.payload, value.mtime])
        for member in value.memberships {
          try db.execute(sql: "INSERT INTO server_memberships VALUES(?,?,?,?,?)",
            arguments: [projectionKey, generation, member.resourceName, value.path, member.identity?.rawValue])
        }
      }
    }
  }

  public func page(resource: String, query: MarkdownServerReadQuery) async throws -> MarkdownServerReadPage {
    try await prepareRead()
    guard let planned = plan.resources.first(where: { $0.name == resource }) else { throw MarkdownServerReadError.unavailable }
    if query.search != nil && !planned.searchEnabled { throw MarkdownServerReadError.searchUnavailable }
    do { return try database.serverRead { db in
      let generation = try publication(db)
      let after = try MarkdownServerReadCursor.position(resource: resource, generation: generation, query: query) ?? ""
      var sql = """
        SELECT r.path,r.hash,r.body_bytes,CASE WHEN length(r.projection)<=67076096 THEN r.projection ELSE NULL END AS projection FROM server_records r JOIN server_memberships m
          ON m.plan=r.plan AND m.generation=r.generation AND m.path=r.path
        WHERE r.plan=? AND r.generation=? AND m.resource=? AND r.path>?
        """
      var arguments: StatementArguments = [projectionKey, generation, resource, after]
      if let prefix = query.pathPrefix {
        sql += " AND substr(r.path,1,length(?))=?"
        arguments += [prefix, prefix]
      }
      if let valid = query.valid {
        sql += " AND json_extract(CAST(r.projection AS TEXT),'$.valid')=?"
        arguments += [valid]
      }
      for key in query.filter.keys.sorted() {
        guard let value = query.filter[key] else { continue }
        let scalar: (String, DatabaseValue)
        switch value {
        case .null: scalar = ("null", .null)
        case .boolean(let value): scalar = (value ? "true" : "false", value.databaseValue)
        case .integer(let value): scalar = ("integer", value.databaseValue)
        case .number(let value): scalar = ("real", value.databaseValue)
        case .string(let value): scalar = ("text", value.databaseValue)
        default: throw MarkdownServerReadError.invalidQuery("filter values must be JSON scalars")
        }
        sql += """
           AND EXISTS(SELECT 1 FROM json_each(CAST(r.projection AS TEXT),'$.frontmatter') field
             WHERE field.key=? AND field.type=? AND field.value IS ?)
          """
        arguments += [key, scalar.0]
        arguments += StatementArguments([scalar.1])
      }
      if let search = query.search {
        let source = try String.fetchOne(db, sql: "SELECT source FROM server_publications WHERE plan=?", arguments: [projectionKey])
        guard try sourceGeneration(db) == source else { throw MarkdownServerReadError.unavailable }
        sql += " AND r.path IN (SELECT d.path FROM documents d JOIN documents_fts f ON f.rowid=d.rowid WHERE documents_fts MATCH ?)"
        arguments += [search]
      }
      sql += " ORDER BY r.path COLLATE BINARY"
      let cursor: RowCursor
      do { cursor = try Row.fetchCursor(db, sql: sql, arguments: arguments) }
      catch { throw MarkdownServerReadError.invalidQuery("Invalid search expression") }
      var records: [GenericMarkdownRecord] = []
      var bytes = 32_768
      var next: String?
      while let row = try cursor.next() {
        try Task.checkCancellation()
        if records.count == query.limit {
          next = try continuation(resource, generation, query, records)
          break
        }
        var record = try projection(row, db: db, generation: generation)
        record = try materialize(record, row: row)
        let size = try markdownServerEncodedRecordSize(record)
        guard size <= 64 * 1_024 * 1_024 - 32_768 else { throw MarkdownServerReadError.responseTooLarge }
        if bytes + size > 64 * 1_024 * 1_024 {
          next = try continuation(resource, generation, query, records)
          break
        }
        records.append(record)
        bytes += size + 1
      }
      return MarkdownServerReadPage(records: records, generation: generation, nextCursor: next)
    } } catch let error as DatabaseError where query.search != nil && error.resultCode == .SQLITE_ERROR {
      throw MarkdownServerReadError.invalidQuery("Invalid search expression")
    }
  }

  public func lookup(resource: String, identity: MarkdownRecordIdentity) async throws -> MarkdownServerReadLookupResult {
    if let planned = plan.resources.first(where: { $0.name == resource }),
      let alias = planned.assessmentLookups(persistentIdentity: plan.persistentIdentity).first(where: {
        $0.policy(persistentIdentity: plan.persistentIdentity)?.source == planned.identityPolicy.source
          && planned.constraint(for: $0).uniqueWithin == .server
      }) {
      return try await lookup(resource: resource, lookup: alias.name, value: identity.rawValue)
    }
    try await prepareRead()
    return try database.serverRead { db in
      let generation = try publication(db)
      let count = try Int.fetchOne(db, sql: "SELECT count(*) FROM server_memberships WHERE plan=? AND generation=? AND resource=? AND identity=?",
        arguments: [projectionKey, generation, resource, identity.rawValue]) ?? 0
      let rows = try Row.fetchCursor(db, sql: """
        SELECT r.path,r.hash,r.body_bytes,CASE WHEN length(r.projection)<=67076096 THEN r.projection ELSE NULL END AS projection FROM server_records r JOIN server_memberships m
          ON m.plan=r.plan AND m.generation=r.generation AND m.path=r.path
        WHERE r.plan=? AND r.generation=? AND m.resource=? AND m.identity=? ORDER BY r.path LIMIT 1000
        """, arguments: [projectionKey, generation, resource, identity.rawValue])
      var records: [GenericMarkdownRecord] = []
      var bytes = 32_768
      while let row = try rows.next() {
        let record = try materialize(projection(row, db: db, generation: generation), row: row)
        do { bytes += try markdownServerEncodedRecordSize(record) + 1 }
        catch MarkdownServerReadError.responseTooLarge {
          if count == 1 { throw MarkdownServerReadError.responseTooLarge }
          break
        }
        if bytes > 64 * 1_024 * 1_024 {
          if count == 1 { throw MarkdownServerReadError.responseTooLarge }
          break
        }
        records.append(record)
      }
      if count == 0 { return .notFound }
      if count == 1, let record = records.first { return .record(record) }
      return .conflict(MarkdownServerReadConflict(candidates: records, totalCandidates: count))
    }
  }

  public func lookup(resource: String, lookup: String, value: String) async throws -> MarkdownServerReadLookupResult {
    try await prepareRead()
    guard let planned = plan.resources.first(where: { $0.name == resource }),
      let declaration = planned.assessmentLookups(persistentIdentity: plan.persistentIdentity).first(where: { $0.name == lookup }) else { return .notFound }
    let serverScope = planned.constraint(for: declaration).uniqueWithin == .server
    let value = declaration.queryValue(value)
    return try database.serverRead { db in
      let generation = try publication(db)
      let base = "plan=? AND generation=? AND resource=? AND lookup=? AND value=?"
      let arguments: StatementArguments = [projectionKey, generation, resource, lookup, value]
      let visible = try Int.fetchOne(db, sql: "SELECT count(*) FROM server_lookups WHERE \(base) AND selected=1", arguments: arguments) ?? 0
      guard visible > 0 else { return .notFound }
      let count = serverScope
        ? (try Int.fetchOne(db, sql: "SELECT count(*) FROM server_lookups WHERE \(base)", arguments: arguments) ?? visible)
        : visible
      let rows = try Row.fetchCursor(db, sql: """
        SELECT r.path,r.hash,r.body_bytes,CASE WHEN length(r.projection)<=67076096 THEN r.projection ELSE NULL END AS projection
        FROM server_records r JOIN server_lookups l ON l.plan=r.plan AND l.generation=r.generation AND l.path=r.path
        WHERE l.plan=? AND l.generation=? AND l.resource=? AND l.lookup=? AND l.value=? AND l.selected=1
        ORDER BY r.path LIMIT 1000
        """, arguments: arguments)
      var records: [GenericMarkdownRecord] = []
      var bytes = 32_768
      while let row = try rows.next() {
        let record = try materialize(projection(row, db: db, generation: generation), row: row)
        do { bytes += try markdownServerEncodedRecordSize(record) + 1 }
        catch MarkdownServerReadError.responseTooLarge {
          if count == 1 { throw MarkdownServerReadError.responseTooLarge }
          break
        }
        if bytes > 64 * 1_024 * 1_024 {
          if count == 1 { throw MarkdownServerReadError.responseTooLarge }
          break
        }
        records.append(record)
      }
      if count == 1, let record = records.first { return .record(record) }
      return .conflict(MarkdownServerReadConflict(candidates: records, totalCandidates: count))
    }
  }

  public func lookupEvidence(resource: String, path: MarkdownRecordPath) async throws -> [MarkdownLookupEvidence] {
    try await prepareRead()
    return try database.serverRead { db in
      try lookupEvidence(resource: resource, path: path.rawValue, db: db, generation: publication(db))
    }
  }

  private func lookupEvidence(resource: String, path: String, db: Database, generation: String) throws -> [MarkdownLookupEvidence] {
    let rows = try Row.fetchAll(db, sql: "SELECT evidence FROM server_lookups WHERE plan=? AND generation=? AND resource=? AND path=? AND selected=1 ORDER BY lookup",
      arguments: [projectionKey, generation, resource, path])
    return try rows.map { row in
      let item = try JSONDecoder().decode(MarkdownLookupEvidence.self, from: row["evidence"])
      let scope = item.uniqueWithin == .server ? "" : " AND selected=1"
      let count = try Int.fetchOne(db, sql: "SELECT count(*) FROM server_lookups WHERE plan=? AND generation=? AND resource=? AND lookup=? AND value=?\(scope)",
        arguments: [projectionKey, generation, resource, item.lookup, item.value]) ?? 0
      return item.checking(count: count)
    }
  }

  public func lookup(path: MarkdownRecordPath) async throws -> MarkdownServerReadLookupResult {
    try await prepareRead()
    return try database.serverRead { db in
      let generation = try publication(db)
      let rows = try Row.fetchAll(db, sql: "SELECT path,hash,body_bytes,CASE WHEN length(projection)<=67076096 THEN projection ELSE NULL END AS projection FROM server_records WHERE plan=? AND generation=? AND path=?",
        arguments: [projectionKey, generation, path.rawValue])
      return try lookupResult(rows, db: db, generation: generation)
    }
  }

  /// Canonical identities in the file adapter are collection-relative logical paths.
  public func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    try checkConfiguration()
    guard (try? MarkdownRecordPath(identity.rawValue)) != nil else { throw RecordStoreError.notFound(identity) }
    return try database.serverRead { db in
      guard let row = try Row.fetchOne(db, sql: "SELECT path,hash,mtime FROM files WHERE path=?", arguments: [identity.rawValue]) else {
        throw RecordStoreError.notFound(identity)
      }
      return try canonicalRecord(row)
    }
  }

  /// Bounded canonical enumeration also works independently of HTTP resource membership.
  public func records(matching query: RecordStoreQuery) async throws -> RecordStorePage {
    try checkConfiguration()
    let request = try MarkdownServerReadQuery(limit: min(query.limit, 1_000),
      cursor: query.continuationToken?.rawValue, pathPrefix: query.searchRoot.rawValue)
    return try database.serverRead { db in
      let generation = try sourceGeneration(db)
      let after = try MarkdownServerReadCursor.position(resource: "$canonical", generation: generation, query: request) ?? ""
      let cursor = try Row.fetchCursor(db, sql: "SELECT path,hash,mtime FROM files WHERE path>? ORDER BY path COLLATE BINARY", arguments: [after])
      var records: [MarkdownRecord] = []
      var bytes = 0
      var next: RecordStoreContinuationToken?
      while let row = try cursor.next() {
        let path: String = row["path"]
        guard request.pathPrefix.map({ path.hasPrefix($0) }) ?? true else { continue }
        let record = try canonicalRecord(row)
        if records.count == request.limit || bytes + record.content.utf8.count > 64 * 1_024 * 1_024 {
          guard let last = records.last?.context.path?.rawValue else { throw RecordStoreError.unavailable }
          next = RecordStoreContinuationToken(rawValue: try MarkdownServerReadCursor(resource: "$canonical",
            generation: generation, query: request, after: last).encoded())
          break
        }
        records.append(record)
        bytes += record.content.utf8.count
      }
      return RecordStorePage(records: records, continuationToken: next)
    }
  }

  public func create(_ record: MarkdownRecord) async throws -> MarkdownRecord { throw RecordStoreError.unsupportedOperation }
  public func replace(_ record: MarkdownRecord, ifRevision expectedRevision: MarkdownRecordRevision) async throws -> MarkdownRecord {
    throw RecordStoreError.unsupportedOperation
  }
  public func delete(identity: MarkdownRecordIdentity, ifRevision expectedRevision: MarkdownRecordRevision) async throws {
    throw RecordStoreError.unsupportedOperation
  }

  private func canonicalRecord(_ row: Row) throws -> MarkdownRecord {
    let path: String = row["path"]
    let hash: String = row["hash"]
    let bytes = try readSource(path: path, hash: hash)
    guard let content = String(data: bytes, encoding: .utf8) else { throw MarkdownServerReadError.sourceChanged }
    return MarkdownRecord(identity: .init(rawValue: path), content: content,
      context: .init(path: try MarkdownRecordPath(path), modificationDate: Date(timeIntervalSince1970: row["mtime"])),
      revision: .init(rawValue: hash))
  }

  private func publication(_ db: Database) throws -> String {
    guard let generation = try String.fetchOne(db, sql: "SELECT generation FROM server_publications WHERE plan=?", arguments: [projectionKey]) else {
      throw MarkdownServerReadError.unavailable
    }
    return generation
  }

  private func continuation(_ resource: String, _ generation: String, _ query: MarkdownServerReadQuery,
    _ records: [GenericMarkdownRecord]) throws -> String? {
    guard let path = records.last?.logicalPath?.rawValue else { throw MarkdownServerReadError.responseTooLarge }
    return try MarkdownServerReadCursor(resource: resource, generation: generation, query: query, after: path).encoded()
  }

  private func projection(_ row: Row, db: Database, generation: String) throws -> GenericMarkdownRecord {
    guard let data: Data = row["projection"] else { throw MarkdownServerReadError.responseTooLarge }
    let record = try JSONDecoder().decode(GenericMarkdownRecord.self, from: data)
    var memberships: [GenericMarkdownResourceMembership] = []
    var diagnostics = record.diagnostics
    for member in record.memberships {
      for evidence in try lookupEvidence(resource: member.resourceName, path: row["path"], db: db, generation: generation)
        where evidence.violatesConstraint {
        for problem in evidence.diagnostics {
          let diagnostic = MarkdownServerRecordDiagnostic(code: "identity.lookup.\(evidence.status.rawValue)",
            severity: .error, source: .identity, location: "lookups.\(evidence.lookup)",
            message: problem.message, identity: problem.identity,
          )
          if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
        }
      }
      var duplicate = false
      if let identity = member.identity {
        let paths = try String.fetchAll(db, sql: """
          SELECT path FROM server_memberships WHERE plan=? AND generation=? AND resource=? AND identity=? ORDER BY path LIMIT 1001
          """, arguments: [projectionKey, generation, member.resourceName, identity.rawValue])
        duplicate = paths.count > 1
        if duplicate {
          let count = try Int.fetchOne(db, sql: "SELECT count(*) FROM server_memberships WHERE plan=? AND generation=? AND resource=? AND identity=?",
            arguments: [projectionKey, generation, member.resourceName, identity.rawValue]) ?? paths.count
          let diagnostic = MarkdownServerRecordDiagnostic(code: "identity.primary.duplicate", severity: .error,
            source: .identity, location: "identity.primary", message: "Primary identity \"\(identity.rawValue)\" is used by \(count) records",
            identity: identity, paths: try paths.prefix(1_000).map { try MarkdownRecordPath($0) })
          if !diagnostics.contains(diagnostic) {
            let position = diagnostics.firstIndex {
              (member.ruleAssessment != nil && $0.ruleName == member.ruleAssessment?.name)
                || (member.selectedType != nil && $0.typeName == member.selectedType)
            } ?? diagnostics.endIndex
            diagnostics.insert(diagnostic, at: position)
          }
        }
      }
      memberships.append(GenericMarkdownResourceMembership(resourceName: member.resourceName, selectionMode: member.selectionMode,
        identity: member.identity, identityStatus: duplicate ? .duplicate : member.identityStatus,
        ruleAssessment: member.ruleAssessment, selectedType: member.selectedType, assessedTypes: member.assessedTypes, valid: member.valid))
    }
    return GenericMarkdownRecord(canonicalIdentity: record.canonicalIdentity, identityStatus: record.identityStatus,
      logicalPath: record.logicalPath, revision: record.revision, memberships: memberships, valid: record.valid,
      frontmatter: record.frontmatter, body: "", diagnostics: diagnostics)
  }

  private func materialize(_ record: GenericMarkdownRecord, row: Row) throws -> GenericMarkdownRecord {
    let data = try readSource(path: row["path"], hash: row["hash"])
    let bytes: Int = row["body_bytes"]
    guard bytes >= 0, bytes <= data.count else { throw MarkdownServerReadError.sourceChanged }
    return replacing(record, body: String(decoding: data.suffix(bytes), as: UTF8.self))
  }

  private func readSource(path: String, hash: String) throws -> Data {
    do {
      _ = try MarkdownRecordPath(path)
      let file = root.appendingPathComponent(path).resolvingSymlinksInPath()
      guard file.path.hasPrefix(root.path + "/"), !file.path.hasPrefix(root.appendingPathComponent(".md-utils/").path + "/") else {
        throw MarkdownServerReadError.sourceChanged
      }
      guard try Stat(FilePath(file.path), followTargetSymlink: false).type == .regular else {
        throw MarkdownServerReadError.sourceChanged
      }
      let handle = try FileDescriptor.open(FilePath(file.path), .readOnly, options: [.noFollow, .nonBlocking])
      defer { try? handle.close() }
      var data = Data()
      let maximum = 64 * 1_024 * 1_024
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while data.count <= maximum {
        try Task.checkCancellation()
        let remaining = min(buffer.count, maximum + 1 - data.count)
        let count = try buffer.withUnsafeMutableBytes {
          try handle.read(into: UnsafeMutableRawBufferPointer(rebasing: $0.prefix(remaining)))
        }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
      }
      guard data.count <= maximum, IndexFingerprint.hash(data) == hash else { throw MarkdownServerReadError.sourceChanged }
      return data
    } catch is CancellationError { throw CancellationError() }
    catch { throw MarkdownServerReadError.sourceChanged }
  }

  private func replacing(_ record: GenericMarkdownRecord, body: String) -> GenericMarkdownRecord {
    GenericMarkdownRecord(canonicalIdentity: record.canonicalIdentity, identityStatus: record.identityStatus,
      logicalPath: record.logicalPath, revision: record.revision, memberships: record.memberships,
      valid: record.valid, frontmatter: record.frontmatter, body: body, diagnostics: record.diagnostics)
  }

  private func lookupResult(_ rows: [Row], db: Database, generation: String) throws -> MarkdownServerReadLookupResult {
    var records: [GenericMarkdownRecord] = []
    var bytes = 1_024
    for row in rows {
      let record = try materialize(projection(row, db: db, generation: generation), row: row)
      bytes += try markdownServerEncodedRecordSize(record)
      guard bytes < 64 * 1_024 * 1_024 else { throw MarkdownServerReadError.responseTooLarge }
      records.append(record)
    }
    guard let first = records.first else { return .notFound }
    if records.count == 1 { return .record(first) }
    return .conflict(MarkdownServerReadConflict(candidates: records))
  }
}

/// A single candidate preserves the existing semantic projector without a corpus cache.
private struct SingleRecordStore: RecordStore {
  let record: MarkdownRecord
  func record(for identity: MarkdownRecordIdentity) async throws -> MarkdownRecord {
    guard record.identity == identity else { throw RecordStoreError.notFound(identity) }
    return record
  }
  func records(matching query: RecordStoreQuery) async throws -> RecordStorePage { RecordStorePage(records: [record]) }
  func create(_ record: MarkdownRecord) async throws -> MarkdownRecord { throw RecordStoreError.unsupportedOperation }
  func replace(_ record: MarkdownRecord, ifRevision expectedRevision: MarkdownRecordRevision) async throws -> MarkdownRecord { throw RecordStoreError.unsupportedOperation }
  func delete(identity: MarkdownRecordIdentity, ifRevision expectedRevision: MarkdownRecordRevision) async throws { throw RecordStoreError.unsupportedOperation }
}
