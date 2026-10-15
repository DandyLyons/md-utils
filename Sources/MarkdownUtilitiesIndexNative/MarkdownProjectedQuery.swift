import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

extension MarkdownCollectionQuerySession {
  /// SQL first narrows incoming sources; only retained normalized evidence is decoded.
  static func projectedSnapshot(_ request: MarkdownCollectionQueryRequest, database: SQLiteIndexDatabase,
    root: Path, limits: MarkdownRelationshipLimits,
  ) async throws -> (result: MarkdownCollectionQueryResult, complete: Bool)? {
    let snapshot = try database.serverRead { db -> (IndexedRelationshipPublication.Header, Set<String>, [String: MarkdownPreparedQueryDocument], Bool)? in
      let generation = try SQLiteIndexDatabase.publishedGeneration(in: db)
      guard try db.tableExists("relationship_projection_header"),
        let payload = try Data.fetchOne(db, sql: "SELECT payload FROM relationship_projection_header"),
        let header = try? JSONDecoder().decode(IndexedRelationshipPublication.Header.self, from: payload),
        header.version == 2, header.generation == generation,
        header.profile == MarkdownRelationshipEvaluator.profile,
        header.epoch == (try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='epoch'")) else { return nil }
      for name in request.types {
        guard let relations = header.types[name] else { throw IndexProjectError("Unknown indexed declaring type: \(name)") }
        if let relation = request.relation, !relations.contains(relation) { throw IndexProjectError("Unknown indexed relationship: \(name).\(relation)") }
      }
      for selector in request.selectors + request.exclusions {
        switch selector {
        case .type(let name), .requiredType(let name):
          guard header.types[name] != nil else { throw IndexProjectError("Unknown indexed type: \(name)") }
        case .rule(let name):
          guard header.rules.contains(name) else { throw IndexProjectError("Unknown indexed rule: \(name)") }
        default: break
        }
      }
      let namespace = try String.fetchAll(db, sql: "SELECT path FROM files ORDER BY path LIMIT ?", arguments: [limits.candidates + 1])
      var complete = namespace.count <= limits.candidates
      let paths = Set(namespace.prefix(limits.candidates))
      let endpoints = request.candidateSources(in: paths)
      var sourcePaths = endpoints
      if request.direction != .outgoing && !endpoints.isEmpty {
        // Indexed target lookups avoid the former 10,000-record collection scan.
        for endpoint in endpoints {
          sourcePaths.formUnion(try String.fetchAll(db,
            sql: "SELECT source FROM relationship_projection_edges WHERE target=? LIMIT ?",
            arguments: [endpoint, limits.records + 1]))
          if sourcePaths.count > limits.records { complete = false; break }
        }
        sourcePaths.formUnion(try String.fetchAll(db,
          sql: "SELECT path FROM relationship_projection WHERE uncertain=1 ORDER BY path LIMIT ?",
          arguments: [limits.records + 1]))
      }
      var facts: [String: MarkdownPreparedQueryDocument] = [:]
      var bytes = 0
      for path in endpoints.sorted() + sourcePaths.subtracting(endpoints).sorted() {
        try Task.checkCancellation()
        guard facts.count < limits.records else { complete = false; break }
        guard let row = try Row.fetchOne(db, sql: "SELECT length(payload) AS bytes,payload FROM relationship_projection WHERE path=?", arguments: [path]) else {
          complete = false; continue
        }
        let count: Int = row["bytes"]
        guard count <= limits.bytes - bytes else { complete = false; break }
        bytes += count
        facts[path] = try JSONDecoder().decode(MarkdownPreparedQueryDocument.self, from: row["payload"] as Data)
      }
      return (header, paths, facts, complete)
    }
    guard let (header, paths, facts, complete) = snapshot else { return nil }
    var records: [String: MarkdownRecord] = [:]
    for (path, fact) in facts {
      records[path] = .init(identity: .init(rawValue: path), content: "",
        context: .init(path: try MarkdownRecordPath(path)), revision: fact.revision)
    }
    var limitations = header.limitations
    if !complete { limitations.append("Indexed relationship evidence exceeds the query budget or is unavailable.") }
    let collection = MarkdownRelationshipCollection(identity: root.string, generation: String(header.generation),
      records: records, paths: paths, sourcesComplete: header.sourcesComplete && complete,
      candidatesComplete: header.candidatesComplete, limitations: limitations)
    let registry = try MarkdownTypeRegistry(definitions: [])
    var graph = try await MarkdownRelationshipEvaluator(registry: registry, limits: limits).evaluate(roots: [], collection: collection)
    graph.assessments = facts.keys.sorted().flatMap { facts[$0]?.nodes ?? [] }
    graph.occurrences = facts.keys.sorted().flatMap { facts[$0]?.assertions ?? [] }
    var result = try await MarkdownCollectionQueryEvaluator(types: registry, limits: limits)
      .evaluate(request, collection: collection, evaluation: graph, indexed: nil, prepared: facts)
    if !header.limitations.isEmpty {
      result.complete = false
      if result.result.coverage != nil { result.result.coverage?.interpretations = "incomplete" }
      if !result.result.notices.contains(where: { $0.code == "query.incomplete" }) {
        result.result.notices.append(.init(code: "query.incomplete", message: "Search incomplete; more relationships may exist.", hint: "Use --detail explain."))
      }
    }
    result.result.generation = String(header.generation)
    result.result.notices.insert(.init(code: "query.index-snapshot",
      message: "Index snapshot generation \(header.generation); raw files were not read or refreshed."), at: 0)
    return result
  }
}
