import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

/// Builds a query projection during explicit indexing. Readers never invoke this service.
/// Each source must match its published hash; publication is generation/epoch bound.
public enum IndexedRelationshipPublication {
  package struct Header: Codable {
    var version = 2
    var generation: Int
    var epoch: String
    var profile = MarkdownRelationshipEvaluator.profile
    var types: [String: [String]]
    var rules: [String]
    var limitations: [String]
    var sourcesComplete: Bool
    var candidatesComplete: Bool
  }

  public static func publish(database: SQLiteIndexDatabase, root: Path,
    project: IndexProjectEvaluator, writerLease: CollectionWriterLease,
  ) async throws {
    let url = URL(fileURLWithPath: root.string).resolvingSymlinksInPath()
    guard writerLease.root == url else { throw IndexProjectError("Relationship publication requires the collection writer lease.") }
    let baseline = try database.serverRead { db in
      (try SQLiteIndexDatabase.publishedGeneration(in: db),
       try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'") ?? "",
       try Row.fetchAll(db, sql: "SELECT path,hash,state FROM files ORDER BY path"))
    }
    // Refresh has a larger collection budget than a single query. Result reads
    // still use the ordinary query budgets and SQL reverse-edge selection.
    var limits = MarkdownRelationshipLimits()
    limits.records = 100_000
    limits.bytes = 256 * 1_024 * 1_024
    limits.nodes = 1_000_000
    limits.occurrences = 1_000_000
    limits.edges = 1_000_000
    var records: [String: MarkdownRecord] = [:]
    var paths: Set<String> = []
    var limitations: [String] = []
    var bytes = 0
    for row in baseline.2 {
      try Task.checkCancellation()
      let path: String = row["path"]
      guard paths.count < limits.candidates else {
        limitations.append("Relationship publication candidate budget exhausted."); break
      }
      guard row["state"] as String == "ok" else {
        limitations.append("\(path): indexed source is unavailable.")
        continue
      }
      paths.insert(path)
      guard ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { continue }
      guard records.count < limits.records, bytes < limits.bytes else {
        limitations.append("Relationship publication source budget exhausted."); break
      }
      do {
        let record = try MarkdownRelationshipNativeCollection.read(path: path, root: url, maximum: limits.bytes - bytes)
        guard record.revision?.rawValue == (row["hash"] as String) else {
          throw IndexProjectError("Source changed after index refresh; refresh again.")
        }
        bytes += record.content.utf8.count
        records[path] = record
      } catch is CancellationError { throw CancellationError() }
      catch { limitations.append("\(path): \(error.localizedDescription)") }
    }
    let collection = MarkdownRelationshipCollection(identity: url.path, generation: String(baseline.0),
      records: records, paths: paths, sourcesComplete: limitations.isEmpty,
      candidatesComplete: paths.count == baseline.2.count, limitations: limitations)
    var roots: [(MarkdownRecord, MarkdownTypeName)] = []
    for path in records.keys.sorted() {
      guard let record = records[path] else { continue }
      for definition in project.types.definitions where !definition.relationships.isEmpty {
        guard roots.count < limits.nodes else { break }
        roots.append((record, definition.name))
      }
    }
    var graph = try await MarkdownRelationshipEvaluator(registry: project.types, limits: limits)
      .evaluate(roots: roots, collection: collection)
    if records.count * project.types.definitions.filter({ !$0.relationships.isEmpty }).count > limits.nodes {
      graph.limitations.append("Relationship publication type assessment budget exhausted.")
      graph.diagnosticsTruncated = true
    }
    var facts: [String: MarkdownPreparedQueryDocument] = [:]
    let cachedTypes = try database.serverRead { db in
      var values: [String: [String: MarkdownAssessmentOutcome]] = [:]
      for row in try Row.fetchAll(db, sql: "SELECT id,definition FROM scopes WHERE fingerprint=? AND state IN ('complete','limited')", arguments: [project.fingerprint]) {
        let scope = try JSONDecoder().decode(IndexScope.self, from: Data((row["definition"] as String).utf8))
        guard scope.kind == .type else { continue }
        let cursor = try Row.fetchCursor(db, sql: "SELECT path,selected,status FROM assessments WHERE scope_id=?", arguments: [scope.id])
        while let assessment = try cursor.next() {
          values[assessment["path"] as String, default: [:]][scope.name] = (assessment["status"] as String) == "evaluation-error"
            ? .unavailable : ((assessment["selected"] as Bool) ? .pass : .fail)
        }
      }
      return values
    }
    _ = try await MarkdownCollectionQueryEvaluator(types: project.types, rules: project.rules, limits: limits)
      .evaluate(.init(direction: .both, selectors: [.folder("")], detail: .summary),
        collection: collection, evaluation: graph, indexed: nil, capture: { facts = $0 }, cachedTypes: cachedTypes)
    limitations += graph.limitations
    if graph.diagnosticsTruncated { limitations.append("Published relationship diagnostics were truncated.") }
    let header = Header(generation: baseline.0, epoch: baseline.1,
      types: Dictionary(uniqueKeysWithValues: project.types.definitions.map { ($0.name.rawValue, $0.relationships.keys.sorted()) }),
      rules: project.rules?.definitions.map(\.name).sorted() ?? [],
      limitations: Array(Set(limitations)).sorted(), sourcesComplete: collection.sourcesComplete,
      candidatesComplete: collection.resolver.namespaceComplete)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    // Scratch rows remain invisible to readers until the final transaction swaps
    // all facts and reverse edges. A failed/cancelled build cannot mix generations.
    try database.serverWrite { db in
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS relationship_projection_header(payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS relationship_projection(path TEXT PRIMARY KEY,payload BLOB NOT NULL,uncertain INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS relationship_projection_edges(source TEXT NOT NULL,target TEXT NOT NULL,PRIMARY KEY(target,source));
        CREATE TABLE IF NOT EXISTS relationship_projection_staging(path TEXT PRIMARY KEY,payload BLOB NOT NULL,uncertain INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS relationship_projection_edge_staging(source TEXT NOT NULL,target TEXT NOT NULL,PRIMARY KEY(target,source));
        DELETE FROM relationship_projection_staging;
        DELETE FROM relationship_projection_edge_staging;
        """)
    }
    var storedBytes = 0
    var batch: [(String, Data, Bool, Set<String>)] = []
    var batchBytes = 0
    func flush() throws {
      try database.serverWrite { db in
        for (path, payload, uncertain, targets) in batch {
          try db.execute(sql: "INSERT INTO relationship_projection_staging VALUES(?,?,?)", arguments: [path, payload, uncertain])
          for target in targets {
            try db.execute(sql: "INSERT OR IGNORE INTO relationship_projection_edge_staging VALUES(?,?)", arguments: [path, target])
          }
        }
      }
      batch.removeAll(keepingCapacity: true)
      batchBytes = 0
    }
    for path in facts.keys.sorted() {
      try Task.checkCancellation()
      guard let fact = facts[path] else { continue }
      let payload = try encoder.encode(fact)
      storedBytes += payload.count
      guard storedBytes <= limits.bytes else { throw IndexProjectError("Relationship projection exceeds 256 MiB; existing publication retained.") }
      let resolutions = fact.occurrences.map(\.resolution) + fact.assertions.map(\.resolution)
      let targets = Set(resolutions.compactMap { $0 }.flatMap { $0.candidates + ($0.destination.map { [$0] } ?? []) })
      let uncertain = resolutions.contains { $0 == nil || $0?.status == .unavailable }
      batch.append((path, payload, uncertain, targets))
      batchBytes += payload.count
      if batch.count >= 128 || batchBytes >= 1_024 * 1_024 { try flush() }
    }
    if !batch.isEmpty { try flush() }
    let headerData = try encoder.encode(header)
    try database.serverWrite { db in
      guard try SQLiteIndexDatabase.publishedGeneration(in: db) == baseline.0,
        try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'") == baseline.1 else {
        throw IndexProjectError("Index changed during relationship publication; refresh again.")
      }
      try db.execute(sql: """
        DELETE FROM relationship_projection;
        INSERT INTO relationship_projection SELECT * FROM relationship_projection_staging;
        DELETE FROM relationship_projection_edges;
        INSERT INTO relationship_projection_edges SELECT * FROM relationship_projection_edge_staging;
        DELETE FROM relationship_projection_header;
        DELETE FROM relationship_projection_staging;
        DELETE FROM relationship_projection_edge_staging;
        """)
      try db.execute(sql: "INSERT INTO relationship_projection_header VALUES(?)", arguments: [headerData])
    }
  }
}
