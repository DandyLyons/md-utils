import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesIndex
import PathKit

extension RulesValidatorRunner {
  /// Reuses indexed source evidence but never cached cross-document assessments.
  static func validateRelationships(config: MdUtilsConfig, configPath: Path, ruleName: String?, root: Path,
    noIndex: Bool, indexedOnly: Bool, verifyHashes: Bool, includeNonMarkdown: Bool, warning: (String) -> Void,
  ) async throws -> RuleValidationSummary {
    let registry = try config.compiledRuleRegistry(root: root)
    var checker = MarkdownRuleChecker(registry: registry)
    var names = ruleName.map { [$0] } ?? config.schemaRules.map(\.name)
    var uncovered: [String] = []
    if indexedOnly {
      let path = root + ".md-utils/index.sqlite"
      guard path.exists else { throw IndexProjectError("--indexed-only requires an existing compatible index") }
      let registered = try SQLiteIndexDatabase(path: path.string).scopes()
      uncovered = names.filter { !registered.contains(.init(kind: .rule, name: $0, includeNonMarkdown: includeNonMarkdown)) }
      if ruleName != nil && !uncovered.isEmpty { throw IndexProjectError("Rule scope is not registered: \(uncovered.joined(separator: ", "))") }
      names.removeAll { uncovered.contains($0) }
      guard !names.isEmpty else { throw IndexProjectError("No requested rule scopes registered") }
    }
    var scopes = names.map { IndexScope(kind: .rule, name: $0, includeNonMarkdown: includeNonMarkdown) }
    if !indexedOnly { scopes.append(.init(includeNonMarkdown: includeNonMarkdown)) }
    let collection = try await MarkdownRelationshipNativeCollection.load(root: root, noIndex: noIndex,
      indexedOnly: indexedOnly, verifyHashes: verifyHashes, includeNonMarkdown: includeNonMarkdown,
      requestedScopes: scopes, configPath: configPath, warning: warning)
    var limitations = collection.limitations
    var resolved: [String: [MarkdownTypeName: MarkdownTypeAssessment]] = [:]
    if let types = registry.typeRegistry {
      let selectedTypes = Set(names.flatMap { registry.rule(named: $0)?.definition.referencedTypes ?? [] })
      let definitions = types.definitions.filter { selectedTypes.contains($0.name) && !$0.relationships.isEmpty }
      let roots = collection.records.keys.sorted().flatMap { path in
        definitions.compactMap { definition in collection.records[path].map { ($0, definition.name) } }
      }
      let evaluation = try await MarkdownRelationshipEvaluator(registry: types).evaluate(roots: roots, collection: collection)
      limitations = evaluation.limitations
      for node in evaluation.assessments {
        guard let definition = types.definition(named: node.type) else { continue }
        resolved[node.source, default: [:]][definition.name] = .init(type: definition.name, version: definition.version,
          diagnostics: node.diagnostics, outcome: node.outcome)
      }
    }
    var results: [RuleValidationResult] = []
    for path in collection.records.keys.sorted() {
      guard let record = collection.records[path] else { continue }
      let analyzed = await MarkdownRecordAnalyzer.analyze(record, contentKind: .rulesKind(forFileName: path))
      checker.relationshipAssessments = resolved[path] ?? [:]
      for name in names {
        guard let rule = registry.rule(named: name) else { throw IndexProjectError("Unknown rule: \(name)") }
        let assessment = try checker.assess(analyzed, against: rule)
        if assessment.status == .notApplicable { continue }
        results.append(.init(ruleName: name, schemaPath: "", filePath: path,
          status: assessment.status == .passed ? .ok : (assessment.status == .skipped ? .skipped : .error),
          errors: (assessment.applicabilityDiagnostics + assessment.diagnostics).map {
            .init(path: $0.location, message: validationMessage(code: $0.code, message: $0.message))
          }))
      }
    }
    for limitation in limitations where !limitation.hasPrefix("New files were not discovered") {
      results.append(.init(ruleName: ruleName ?? "relationships", schemaPath: "", filePath: "<collection>",
        status: .error, errors: [.init(path: "relationships", message: "relationship.context.unavailable: " + limitation)]))
    }
    return .init(results: results, totalFiles: collection.records.count, indexedOnly: indexedOnly, uncoveredRules: uncovered)
  }
}
