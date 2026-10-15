import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Reuses certified assessments; new query projections remain uncached.
public enum MarkdownCollectionQuerySession {
  public static func run(_ request: MarkdownCollectionQueryRequest, root: Path,
    noIndex: Bool = false, indexedOnly: Bool = false, verifyHashes: Bool = false,
    limits: MarkdownRelationshipLimits = .init(), warning: (String) -> Void = { _ in },
  ) async throws -> (result: MarkdownCollectionQueryResult, complete: Bool) {
    let root = Path(URL(fileURLWithPath: root.absolute().string).resolvingSymlinksInPath().path)
    guard root.isDirectory else { throw IndexProjectError("Collection root is not a directory: \(root.string)") }
    let includeRules = request.types.isEmpty || (request.selectors + request.exclusions).contains {
      switch $0 { case .rule, .requiredType: true; default: false }
    }
    let project = try IndexProjectEvaluator(root: root, configPath: root + ".md-utils/md-utils.json", includeRules: includeRules)
    let provider = IndexJMESPathProvider()
    for selector in request.selectors + request.exclusions {
      switch selector {
      case .type(let name), .requiredType(let name):
        guard project.types.definition(named: name) != nil else { throw IndexProjectError("Unknown type: \(name)") }
      case .rule(let name):
        guard project.rules?.rule(named: name) != nil else { throw IndexProjectError("Unknown rule: \(name)") }
      case .jmespath(let expression): try provider.validateJMESPath(expression)
      default: break
      }
    }
    for name in request.types {
      guard let definition = project.types.definition(named: name) else { throw IndexProjectError("Unknown declaring type: \(name)") }
      if let relation = request.relation, definition.relationships[relation] == nil {
        throw IndexProjectError("Unknown relationship: \(name).\(relation)")
      }
    }
    // An explicitly empty supplied set needs no source evidence. Keep indexed-only
    // on its normal path so its coverage and required-index contract stay explicit.
    if !indexedOnly, request.selectors.count == 1,
      case .files(let paths) = request.selectors[0], paths.isEmpty {
      let empty = MarkdownRelationshipCollection(identity: root.string, generation: "empty-selection",
        records: [:], paths: [], sourcesComplete: true, candidatesComplete: true)
      let evaluation = try await MarkdownRelationshipEvaluator(registry: project.types, limits: limits)
        .evaluate(roots: [], collection: empty)
      return try await MarkdownCollectionQueryEvaluator(types: project.types, rules: project.rules, limits: limits)
        .evaluate(request, collection: empty, evaluation: evaluation, queryProvider: provider)
    }
    let session = try await MarkdownRelationshipAssessmentSession.load(root: root, noIndex: noIndex,
      indexedOnly: indexedOnly, verifyHashes: verifyHashes, limits: limits, includeRules: includeRules, warning: warning)
    guard project.fingerprint == session.project.fingerprint else { throw IndexProjectError("Definitions changed while preparing query; retry.") }
    var roots: [(String, MarkdownTypeName)] = []
    var exhausted = false
    var needed = Set(request.types)
    for selector in request.selectors + request.exclusions {
      if case .type(let name) = selector { needed.insert(name) }
    }
    let definitions = project.types.definitions.filter {
      request.types.isEmpty || includeRules || needed.contains($0.name.rawValue)
    }.sorted { $0.name.rawValue < $1.name.rawValue }
    for path in session.collection.records.keys.sorted() {
      try Task.checkCancellation()
      for definition in definitions {
        guard roots.count < limits.nodes else { exhausted = true; break }
        roots.append((path, definition.name))
      }
      if exhausted { break }
    }
    var evaluation = try await session.relationships(roots: roots).value
    if exhausted {
      evaluation.diagnosticsTruncated = true
      evaluation.limitations.append("Type applicability assessment budget exhausted.")
    }
    return try await MarkdownCollectionQueryEvaluator(types: project.types, rules: project.rules, limits: limits)
      .evaluate(request, collection: session.collection, evaluation: evaluation, queryProvider: provider)
  }
}
