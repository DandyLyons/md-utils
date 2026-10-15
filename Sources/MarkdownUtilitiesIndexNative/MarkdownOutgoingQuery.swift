import Foundation
import MarkdownUtilitiesCore
import PathKit
import SystemPackage

extension MarkdownCollectionQuerySession {
  /// Outgoing queries need a filename namespace, selected sources, and reachable
  /// target evidence, not a refreshed and materialized whole-collection index.
  static func outgoing(_ request: MarkdownCollectionQueryRequest, root: Path,
    project: IndexProjectEvaluator, provider: IndexJMESPathProvider,
    includeRules: Bool, limits: MarkdownRelationshipLimits,
  ) async throws -> (result: MarkdownCollectionQueryResult, complete: Bool) {
    let url = URL(fileURLWithPath: root.string)
    let namespace: (paths: Set<String>, complete: Bool)
    let scoped = request.suppliedSourceBound != nil
    if let supplied = request.suppliedSourceBound { namespace = (supplied, true) }
    else { namespace = try MarkdownRelationshipNativeCollection.discoverBounded(root: url, maximum: limits.candidates) }
    let sources = request.candidateSources(in: namespace.paths)
    let loader = OutgoingRecordLoader(root: url, limits: limits, namespace: scoped ? nil : namespace)
    var records: [String: MarkdownRecord] = [:]
    var limitations: [String] = []
    for path in sources.sorted() {
      if let record = try await loader.read(path) { records[path] = record }
      else { limitations.append("\(path): selected document is unavailable or exceeds the query budget") }
    }
    if !namespace.complete { limitations.append("relationship.limit.exceeded: candidate discovery budget") }
    var collection = MarkdownRelationshipCollection(identity: root.string, generation: UUID().uuidString,
      records: records, paths: namespace.paths, sourcesComplete: limitations.isEmpty,
      candidatesComplete: namespace.complete, completeExactPaths: Set(records.keys), limitations: limitations)
    collection.loadRecord = { path in try await loader.read(path) }
    collection.resolveLink = { target, source, markdown in
      try await loader.resolve(target, from: source, markdown: markdown)
    }
    var needed = Set(request.types)
    for selector in request.selectors + request.exclusions {
      if case .type(let name) = selector { needed.insert(name) }
    }
    let definitions = project.types.definitions.filter {
      request.types.isEmpty || project.rules != nil || needed.contains($0.name.rawValue)
    }.sorted { $0.name.rawValue < $1.name.rawValue }
    var roots: [(MarkdownRecord, MarkdownTypeName)] = []
    var exhausted = false
    for path in records.keys.sorted() {
      guard let record = records[path] else { continue }
      for definition in definitions {
        guard roots.count < limits.nodes else { exhausted = true; break }
        roots.append((record, definition.name))
      }
      if exhausted { break }
    }
    var evaluation = try await MarkdownRelationshipEvaluator(registry: project.types, limits: limits)
      .evaluate(roots: roots, collection: collection)
    if exhausted {
      evaluation.diagnosticsTruncated = true
      evaluation.limitations.append("Type applicability assessment budget exhausted.")
    }
    let result = try await MarkdownCollectionQueryEvaluator(types: project.types, rules: project.rules, limits: limits)
      .evaluate(request, collection: collection, evaluation: evaluation, queryProvider: provider)
    // Only consumed contents need revision verification. Namespace verification
    // protects ambiguous and negative lookups without reading unrelated bodies.
    try await loader.verify()
    guard try IndexProjectEvaluator(root: root, configPath: root + ".md-utils/md-utils.json",
      includeRules: includeRules).fingerprint == project.fingerprint else {
      throw IndexProjectError("Definitions changed during query; retry.")
    }
    return result
  }
}

/// Actor ownership bounds and memoizes both successful and failed reads. Synchronous
/// filesystem reads cannot suspend between the budget check and accounting update.
private actor OutgoingRecordLoader {
  let root: URL
  let limits: MarkdownRelationshipLimits
  var records: [String: MarkdownRecord] = [:]
  var attempted: Set<String> = []
  var bytes = 0
  var namespace: (paths: Set<String>, complete: Bool)?
  var exactPaths: [String: Bool] = [:]

  init(root: URL, limits: MarkdownRelationshipLimits, namespace: (paths: Set<String>, complete: Bool)?) {
    self.root = root; self.limits = limits; self.namespace = namespace
  }

  func resolve(_ target: String, from source: String, markdown: Bool) throws -> CollectionWikilinkResolution? {
    try Task.checkCancellation()
    let exact: Set<String>?
    if markdown {
      guard let normalized = MarkdownQueryLinks.markdownPath(target, source: source) else { return nil }
      exact = normalized.supported ? [normalized.path] : []
    } else { exact = CollectionWikilinkResolver.exactCandidatePaths(target: target, from: source) }
    let resolver: CollectionWikilinkResolver
    if let exact {
      for path in exact where exactPaths[path] == nil {
        guard exactPaths.count < limits.candidates else {
          return CollectionWikilinkResolver(paths: [], namespaceComplete: false).resolve(target: target, from: source)
        }
        exactPaths[path] = try exists(path)
      }
      // Construct only the tiny exact namespace, not a new basename index per link.
      resolver = .init(paths: exact.filter { exactPaths[$0] == true }, namespaceComplete: true)
    } else {
      if namespace == nil {
        namespace = try MarkdownRelationshipNativeCollection.discoverBounded(root: root, maximum: limits.candidates)
      }
      resolver = basenameResolver()
    }
    return markdown ? MarkdownQueryLinks.resolveMarkdown(target, source: source, resolver: resolver)
      : resolver.resolve(target: target, from: source)
  }

  private var cachedResolver: CollectionWikilinkResolver?
  private func basenameResolver() -> CollectionWikilinkResolver {
    if let cachedResolver { return cachedResolver }
    let resolver = CollectionWikilinkResolver(paths: namespace?.paths ?? [], namespaceComplete: namespace?.complete ?? false)
    cachedResolver = resolver
    return resolver
  }

  private func exists(_ path: String) throws -> Bool {
    _ = try MarkdownRecordPath(path)
    var file = root
    let components = path.split(separator: "/")
    for (index, component) in components.enumerated() {
      guard !component.hasPrefix(".") else { return false }
      file.appendPathComponent(String(component))
      do {
        let metadata = try Stat(FilePath(file.path), followTargetSymlink: false)
        guard metadata.type == (index == components.count - 1 ? .regular : .directory),
          try file.resourceValues(forKeys: [.isHiddenKey]).isHidden != true else { return false }
      } catch let error as Errno where error == .noSuchFileOrDirectory || error == .notDirectory {
        return false
      }
    }
    return true
  }

  func read(_ path: String) throws -> MarkdownRecord? {
    try Task.checkCancellation()
    if let record = records[path] { return record }
    guard !attempted.contains(path), attempted.count < limits.records else { return nil }
    attempted.insert(path)
    do {
      guard try exists(path) else { return nil }
      let record = try MarkdownRelationshipNativeCollection.read(path: path, root: root, maximum: limits.bytes - bytes)
      bytes += record.content.utf8.count
      records[path] = record
      return record
    } catch is CancellationError { throw CancellationError() }
    catch { return nil }
  }

  func verify() throws {
    for (path, record) in records {
      try Task.checkCancellation()
      guard try exists(path),
        try MarkdownRelationshipNativeCollection.read(path: path, root: root, maximum: limits.bytes) == record else {
        throw IndexProjectError("Relationship source changed during query: \(path)")
      }
    }
    for (path, present) in exactPaths {
      guard try exists(path) == present else { throw IndexProjectError("Relationship destination changed during query: \(path)") }
    }
    if let namespace {
      let current = try MarkdownRelationshipNativeCollection.discoverBounded(root: root, maximum: limits.candidates)
      guard current.paths == namespace.paths, current.complete == namespace.complete else {
        throw IndexProjectError("Relationship candidate namespace changed during query; retry.")
      }
    }
  }
}
