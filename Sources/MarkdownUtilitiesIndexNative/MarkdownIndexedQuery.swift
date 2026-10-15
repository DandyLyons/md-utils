import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

extension MarkdownCollectionQuerySession {
  /// Reads one published SQLite transaction. No project loader, writer lease,
  /// refresh service, or native source reader is reachable from this path.
  static func indexedSnapshot(_ request: MarkdownCollectionQueryRequest, root: Path,
    limits: MarkdownRelationshipLimits,
  ) async throws -> (result: MarkdownCollectionQueryResult, complete: Bool) {
    let root = root.absolute().normalize()
    let database = try SQLiteIndexDatabase(readOnlyPath: (root + ".md-utils/index.sqlite").string)
    let snapshot = try database.serverRead { db in
      let generation = try SQLiteIndexDatabase.publishedGeneration(in: db)
      let identity = try String.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='root'") ?? root.string
      if request.suppliedSourceBound?.isEmpty == true {
        let empty = MarkdownRelationshipCollection(identity: identity, generation: String(generation),
          records: [:], paths: [], sourcesComplete: true, candidatesComplete: true)
        return (empty, MarkdownIndexedQueryEvidence(), Optional<MarkdownRelationshipEvaluation>.none)
      }
      var paths: Set<String> = []
      var limitations: [String] = []
      var namespaceComplete = true
      let candidates = try Row.fetchCursor(db, sql: "SELECT path,state FROM files ORDER BY path")
      while let row = try candidates.next() {
        try Task.checkCancellation()
        guard paths.count < limits.candidates else { namespaceComplete = false; break }
        let path: String = row["path"]
        if row["state"] as String == "ok" { paths.insert(path) }
        else { namespaceComplete = false }
      }
      if !namespaceComplete { limitations.append("Indexed candidate evidence is incomplete or exceeds the candidate budget.") }
      let selectedCandidates = request.candidateSources(in: paths)
      let sources = request.direction == .outgoing ? selectedCandidates : paths
      var records: [String: MarkdownRecord] = [:]
      var byteCount = 0
      var missingBodies = 0
      var truncated = false
      func retain(_ row: Row) throws {
        let path: String = row["path"]
        guard sources.contains(path) || selectedCandidates.contains(path), records[path] == nil,
          ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { return }
        guard records.count < limits.records else { truncated = true; return }
        let metadata: String = row["metadata"]
        let body: String? = row["body"]
        let content = "---\n" + metadata + "\n---\n" + (body ?? "")
        guard content.utf8.count <= limits.bytes - byteCount else { truncated = true; return }
        byteCount += content.utf8.count
        if body == nil { missingBodies += 1 }
        records[path] = .init(identity: .init(rawValue: path), content: content,
          context: .init(path: try MarkdownRecordPath(path)), revision: .init(rawValue: row["hash"]))
      }
      // Explicit query endpoints are retained before the incoming-source budget.
      let sql = "SELECT d.path,json(d.metadata) AS metadata,d.body,f.hash FROM documents d JOIN files f USING(path) WHERE f.state='ok'"
      for path in (request.suppliedSourceBound ?? []).sorted().prefix(limits.records) {
        if let row = try Row.fetchOne(db, sql: sql + " AND d.path=?", arguments: [path]) { try retain(row) }
      }
      let rows = try Row.fetchCursor(db, sql: sql + " ORDER BY d.path")
      while let row = try rows.next() {
        try Task.checkCancellation()
        try retain(row)
        if truncated { break }
      }
      if missingBodies > 0 { limitations.append("Body link evidence is not stored for \(missingBodies) inspected documents; raw files were not read.") }
      if truncated { limitations.append("Indexed source evidence exceeds the record/byte budget.") }
      var evidence = MarkdownIndexedQueryEvidence()
      let requestedTypes = Set((request.selectors + request.exclusions).compactMap { selector -> String? in
        if case .type(let name) = selector { return name }; return nil
      })
      let requestedRules = Set((request.selectors + request.exclusions).compactMap { selector -> String? in
        if case .rule(let name) = selector { return name }; return nil
      })
      if !requestedTypes.isEmpty || !requestedRules.isEmpty {
        for row in try Row.fetchAll(db, sql: "SELECT id,definition FROM scopes") {
          let definition: String = row["definition"]
          let scope = try JSONDecoder().decode(IndexScope.self, from: Data(definition.utf8))
          guard (scope.kind == .type && requestedTypes.contains(scope.name))
            || (scope.kind == .rule && requestedRules.contains(scope.name)) else { continue }
          let findings = try Row.fetchCursor(db, sql: "SELECT path,status,selected FROM assessments WHERE scope_id=?", arguments: [scope.id])
          while let finding = try findings.next() {
            let path: String = finding["path"]
            let status: String = finding["status"]
            let outcome: MarkdownAssessmentOutcome = status == "evaluation-error" ? .unavailable
              : ((finding["selected"] as Bool) ? .pass : .fail)
            if scope.kind == .type { evidence.types[path, default: [:]][scope.name] = outcome }
            else { evidence.rules[path, default: [:]][scope.name] = outcome }
          }
        }
      }
      let collection = MarkdownRelationshipCollection(identity: identity, generation: String(generation), records: records,
        paths: paths, sourcesComplete: missingBodies == 0 && !truncated,
        candidatesComplete: namespaceComplete, limitations: limitations)
      // Certified graph payloads can be read as historical facts only when they
      // belong to this exact published generation and epoch. Never validate them
      // against raw sources or reuse an older-generation certificate implicitly.
      var graph: MarkdownRelationshipEvaluation?
      let caches = try Row.fetchAll(db, sql: "SELECT request,bytes,hash FROM relationship_cache WHERE generation=? AND epoch=(SELECT value FROM index_metadata WHERE key='epoch') ORDER BY request LIMIT 4", arguments: [generation])
      var cacheBytes = 0
      for cache in caches {
        let size: Int = cache["bytes"]
        guard size >= 0, size <= SQLiteIndexDatabase.relationshipCacheBytes - cacheBytes else { continue }
        cacheBytes += size
        let key: String = cache["request"]
        let chunks = try Row.fetchCursor(db, sql: "SELECT ordinal,length(payload) AS bytes,payload FROM relationship_chunks WHERE request=? ORDER BY ordinal", arguments: [key])
        var data = Data()
        var ordinal = 0
        var valid = true
        while let chunk = try chunks.next() {
          try Task.checkCancellation()
          let count: Int = chunk["bytes"]
          guard count > 0, count <= SQLiteIndexDatabase.relationshipChunkBytes,
            count <= size - data.count else { valid = false; break }
          let payload: Data = chunk["payload"]
          guard (chunk["ordinal"] as Int) == ordinal, !payload.isEmpty,
            payload.count <= SQLiteIndexDatabase.relationshipChunkBytes,
            payload.count <= size - data.count else { valid = false; break }
          data.append(payload); ordinal += 1
        }
        guard valid, data.count == size, IndexFingerprint.hash(data) == (cache["hash"] as String),
          let decoded = try? JSONDecoder().decode(MarkdownRelationshipEvaluation.self, from: data),
          decoded.evaluatorProfile == MarkdownRelationshipEvaluator.profile else { continue }
        if graph == nil || decoded.assessments.count > (graph?.assessments.count ?? 0) { graph = decoded }
      }
      return (collection, evidence, graph)
    }
    let types = try MarkdownTypeRegistry(definitions: [])
    let empty = try await MarkdownRelationshipEvaluator(registry: types, limits: limits)
      .evaluate(roots: [], collection: snapshot.0)
    let evaluation = snapshot.2 ?? empty
    var output = try await MarkdownCollectionQueryEvaluator(types: types, limits: limits)
      .evaluate(request, collection: snapshot.0, evaluation: evaluation, indexed: snapshot.1)
    output.result.generation = snapshot.0.generation
    output.result.notices.insert(.init(code: "query.index-snapshot",
      message: "Index snapshot generation \(snapshot.0.generation); raw files were not read or refreshed."), at: 0)
    return output
  }
}
