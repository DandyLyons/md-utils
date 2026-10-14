import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

/// One compiled definition set and verified collection. Persistent reuse conservatively
/// depends on the entire snapshot, including negative lookup namespaces and nonmembers.
public struct MarkdownRelationshipAssessmentSession: Sendable {
  public let collection: MarkdownRelationshipCollection
  public let project: IndexProjectEvaluator
  private let root: String
  private let configPath: String
  private let limits: MarkdownRelationshipLimits
  private let indexedOnly: Bool
  private let includeRules: Bool
  private let scopes: [String]
  private let database: SQLiteIndexDatabase?
  private let epoch: String?

  public static func load(root: Path, configPath: Path? = nil, noIndex: Bool = false,
    indexedOnly: Bool = false, verifyHashes: Bool = false, includeNonMarkdown: Bool = false,
    requestedScopes: [IndexScope]? = nil, limits: MarkdownRelationshipLimits = .init(), includeRules: Bool = true,
    warning: (String) -> Void = { _ in },
  ) async throws -> Self {
    let root = Path(URL(fileURLWithPath: root.absolute().string).resolvingSymlinksInPath().path)
    let config = configPath?.absolute() ?? root + ".md-utils/md-utils.json"
    let project = try IndexProjectEvaluator(root: root, configPath: config, includeRules: includeRules)
    let collection = try await MarkdownRelationshipNativeCollection.load(root: root, noIndex: noIndex,
      indexedOnly: indexedOnly, verifyHashes: verifyHashes, includeNonMarkdown: includeNonMarkdown,
      requestedScopes: requestedScopes, configPath: config, limits: limits, warning: warning)
    guard try IndexProjectEvaluator(root: root, configPath: config, includeRules: includeRules).fingerprint == project.fingerprint else {
      throw IndexProjectError("Definitions changed during relationship snapshot construction; retry assessment")
    }
    var database: SQLiteIndexDatabase?
    var epoch: String?
    var scopes = requestedScopes?.map(\.id) ?? []
    if !noIndex, let generation = Int(collection.generation), (root + ".md-utils/index.sqlite").exists {
      let opened = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
      epoch = try opened.relationshipEpoch(generation: generation)
      database = opened
      if requestedScopes == nil { scopes = try opened.scopes().map(\.id) }
    }
    return Self(collection: collection, project: project, root: root.string, configPath: config.string,
      limits: limits, indexedOnly: indexedOnly, includeRules: includeRules, scopes: scopes.sorted(), database: database, epoch: epoch)
  }

  /// Cache hits skip the portable evaluator, but never skip input verification.
  public func relationships(roots: [(String, MarkdownTypeName)]) async throws
    -> (value: MarkdownRelationshipEvaluation, cacheHit: Bool) {
    for (path, type) in roots {
      guard collection.records[path] != nil, project.types.definition(named: type) != nil else {
        throw IndexProjectError("Relationship root record or declaring type is unavailable: \(path), \(type.rawValue)")
      }
    }
    let request = Request(kind: "relationships", selections: roots.map { [$0.0, $0.1.rawValue] }, witness: nil)
    var result = try await cached(request: request, eligible: reusable) {
      try await MarkdownRelationshipEvaluator(registry: project.types, limits: limits).evaluate(
        roots: roots.compactMap { path, type in collection.records[path].map { ($0, type) } }, collection: collection)
    }
    result.value.generation = collection.generation
    return result
  }

  public func policies(ruleNames: [String], cycleWitnessMode: MarkdownCycleWitnessMode = .perComponent) async throws
    -> (value: MarkdownRuleCollectionAssessment, cacheHit: Bool) {
    guard let registry = project.rules else { throw IndexProjectError("Rule registry is unavailable") }
    let request = Request(kind: "policies", selections: ruleNames.sorted().map { [$0] }, witness: cycleWitnessMode)
    var result = try await cached(request: request, eligible: {
      !$0.diagnosticsTruncated && reusable($0.extraction) && reusable($0.typeEvidence)
        && $0.limitations == collection.limitations
        && !$0.rules.contains { $0.policies.contains { $0.diagnosticsTruncated || $0.diagnostics.contains { budgetFailure($0.diagnostic) } } }
    }) {
      try await MarkdownRuleCollectionEvaluator(registry: registry, limits: limits, cycleWitnessMode: cycleWitnessMode)
        .evaluate(collection: collection, ruleNames: ruleNames)
    }
    result.value.generation = collection.generation
    result.value.extraction.generation = collection.generation
    result.value.typeEvidence.generation = collection.generation
    return result
  }

  private struct Request: Encodable {
    var kind: String
    var selections: [[String]]
    var witness: MarkdownCycleWitnessMode?
  }

  private func budgetFailure(_ diagnostic: MarkdownDiagnostic) -> Bool {
    diagnostic.code == "relationship.limit.exceeded" || diagnostic.causes?.contains(where: budgetFailure) == true
  }

  private func reusable(_ value: MarkdownRelationshipEvaluation) -> Bool {
    !value.diagnosticsTruncated && value.limitations == collection.limitations
      && !value.assessments.contains { $0.diagnostics.contains(where: budgetFailure) }
      && !value.occurrences.contains { $0.diagnostics.contains(where: budgetFailure) }
  }

  private struct RecordStamp: Encodable {
    var path: String
    var identity: MarkdownRecordIdentity?
    var revision: MarkdownRecordRevision?
    var context: MarkdownRecordContext
  }

  private struct Certificate: Encodable {
    var profile = "relationship-cache-1"
    var runtime = IndexFingerprint.runtimeVersion
    var relationships = MarkdownRelationshipEvaluator.profile
    var policies = MarkdownRuleCollectionEvaluator.profile
    var resolver = CollectionWikilinkResolver.profile
    var root: String
    var definitions: String
    var records: [RecordStamp]
    var candidates: [String]
    var exactPaths: [String]
    var sourcesComplete: Bool
    var candidatesComplete: Bool
    var limitations: [String]
    var indexedOnly: Bool
    var scopes: [String]
    var limits: MarkdownRelationshipLimits
  }

  private func verify() throws {
    try Task.checkCancellation()
    try MarkdownRelationshipNativeCollection.verifyCurrent(collection, indexedOnly: indexedOnly, limits: limits)
    guard try IndexProjectEvaluator(root: Path(root), configPath: Path(configPath), includeRules: includeRules).fingerprint == project.fingerprint else {
      throw IndexProjectError("Definitions changed during relationship assessment; retry assessment")
    }
  }

  private func cached<Value: Codable & Sendable>(request: Request, eligible: (Value) -> Bool,
    evaluate: () async throws -> Value,
  ) async throws -> (value: Value, cacheHit: Bool) {
    try Task.checkCancellation()
    // Stable limited coverage is cacheable; read failures and changing snapshots are not.
    guard let database, let epoch, let generation = Int(collection.generation),
      collection.limitations.allSatisfy({ $0 == "New files were not discovered. Coverage is limited to recorded candidates." }) else {
      return (try await evaluate(), false)
    }
    let lease = try await CollectionWriterLease.acquire(root: URL(fileURLWithPath: root))
    defer { withExtendedLifetime(lease) {} }
    try verify()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let requestKey = IndexFingerprint.hash(try encoder.encode(request))
    let certificate = Certificate(root: collection.identity, definitions: project.fingerprint,
      records: collection.records.keys.sorted().compactMap { path in
        collection.records[path].map { RecordStamp(path: path, identity: $0.identity, revision: $0.revision, context: $0.context) }
      }, candidates: collection.resolver.paths.sorted(), exactPaths: collection.resolver.completeExactPaths.sorted(),
      sourcesComplete: collection.sourcesComplete, candidatesComplete: collection.resolver.namespaceComplete,
      limitations: collection.limitations, indexedOnly: indexedOnly, scopes: scopes, limits: limits)
    let fingerprint = IndexFingerprint.hash(try encoder.encode(certificate))
    if let data = try database.relationshipCached(request: requestKey, certificate: fingerprint, epoch: epoch, generation: generation),
       let value = try? JSONDecoder().decode(Value.self, from: data), eligible(value) {
      try verify()
      guard try database.relationshipEpoch(generation: generation) == epoch else {
        throw IndexProjectError("Relationship snapshot predates index rebuild")
      }
      return (value, true)
    }
    let value = try await evaluate()
    try verify()
    guard try database.relationshipEpoch(generation: generation) == epoch else {
      throw IndexProjectError("Relationship snapshot predates index rebuild")
    }
    if eligible(value), let data = try RelationshipCacheEncoding.encode(value) {
      try Task.checkCancellation()
      try database.publishRelationship(request: requestKey, certificate: fingerprint, epoch: epoch,
        generation: generation, data: data, verify: verify)
    }
    return (value, false)
  }
}
