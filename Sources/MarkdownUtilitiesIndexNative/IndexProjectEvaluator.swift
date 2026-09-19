import Foundation
import JMESPath
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

public struct IndexProjectError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Adapts the same parsed records and full evaluators used by types find and rules validate.
public struct IndexProjectEvaluator: Sendable {
    /// Native type definitions with all schema references resolved before scanning.
    public let types: MarkdownTypeRegistry
    /// Full native rule runtime, including JMESPath, when a config exists.
    public let rules: MarkdownRuleRegistry?
    /// Combined configuration and transitive-schema provenance used for broad invalidation.
    public let fingerprint: String

    /// Loads definitions and compiles the existing runtime before any candidate is assessed.
    public init(root: Path, configPath: Path) throws {
        types = (root + MarkdownTypeFileRegistryLoader.relativeTypesDirectory).exists
            ? try MarkdownTypeFileRegistryLoader.load(projectRoot: root) : try MarkdownTypeRegistry(definitions: [])
        var standalone: MarkdownStandaloneRuleProject?
        if configPath.exists {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath.string))
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["configVersion"] as? String == "0.3.0" {
                let project = try MarkdownStandaloneRuleProject(configPath: configPath, projectRoot: root, typeRegistry: types)
                standalone = project
                rules = try project.compile(capabilities: [.modificationDate, .frontmatterJMESPath],
                    queryProvider: IndexJMESPathProvider())
            } else {
                let configuration = try MarkdownRuleConfigurationDecoder.decode(String(decoding: data, as: UTF8.self))
                let directory = Path(configuration.schemaDirectory).isAbsolute
                    ? Path(configuration.schemaDirectory) : root + Path(configuration.schemaDirectory)
                let source = URL(fileURLWithPath: (directory + "__md-utils-rule-source.json").string).absoluteString
                let definitions = configuration.rules.map { value in
                    var value = value
                    value.source = source
                    return value
                }
                rules = try MarkdownRuleCompiler(capabilities: [.modificationDate, .frontmatterJMESPath],
                    typeRegistry: types, schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: root),
                    queryProvider: IndexJMESPathProvider()).compile(definitions)
            }
        } else { rules = nil }
        var components = [configPath.string]
        if configPath.exists { components.append(try configPath.read(.utf8)) }
        if let project = standalone {
            for file in project.files { components.append(try Path(file.source).read(.utf8)) }
        }
        // Resolved schemas include transitive resources, including resources outside .md-utils/.
        for registry in [types, rules?.typeRegistry].compactMap({ $0 }) {
            for definition in registry.definitions {
                components.append(try Self.json(IndexDefinitionPayload(definition: definition)))
                if let resolved = registry.resolvedFrontmatterSchema(for: definition.name) {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.sortedKeys]
                    components.append(String(decoding: try encoder.encode(resolved), as: UTF8.self))
                }
            }
        }
        if let rules {
            for definition in rules.definitions {
                if let rule = rules.rule(named: definition.name) {
                    components.append(try Self.json(rule.resolvedSchemas))
                }
            }
        }
        fingerprint = IndexFingerprint.combined(components)
    }

    /// Rejects unknown type or rule names before starting a scan.
    public func validate(_ scope: IndexScope) throws {
        if scope.kind == .type, types.definition(named: scope.name) == nil { throw IndexProjectError("Unknown type: \(scope.name)") }
        if scope.kind == .rule, rules?.rule(named: scope.name) == nil { throw IndexProjectError("Unknown rule: \(scope.name)") }
    }

    /// Extracts one record and applies every requested scope without reparsing it.
    public func evaluate(scopes: [IndexScope], path: String, content: String, modified: Date) async throws
        -> [String: IndexEvaluation] {
        let record = MarkdownRecord(content: content,
            context: MarkdownRecordContext(path: try MarkdownRecordPath(path), modificationDate: modified))
        let analyzed = await MarkdownRecordAnalyzer.analyze(record,
            contentKind: .rulesKind(forFileName: URL(fileURLWithPath: path).lastPathComponent))
        var evaluations: [String: IndexEvaluation] = [:]
        for scope in scopes {
            evaluations[scope.id] = try evaluation(scope: scope, path: path, analyzed: analyzed)
        }
        return evaluations
    }

    /// Evaluates one scope for callers that do not need cross-scope extraction reuse.
    public func evaluate(scope: IndexScope, path: String, content: String, modified: Date) async throws -> IndexEvaluation {
        let evaluations = try await evaluate(scopes: [scope], path: path, content: content, modified: modified)
        guard let evaluation = evaluations[scope.id] else {
            throw IndexProjectError("Evaluator returned no result for scope \(scope.id).")
        }
        return evaluation
    }

    /// Preserves membership, validation, and branch evidence as separate persisted facts.
    private func evaluation(scope: IndexScope, path: String, analyzed: AnalyzedMarkdownRecord) throws -> IndexEvaluation {
        var assessment: IndexAssessment
        switch scope.kind {
        case .directory:
            assessment = IndexAssessment(selected: true, status: analyzed.parseDiagnostics.isEmpty ? "selected" : "parse-error")
        case .type:
            let result = try MarkdownTypeChecker(registry: types).assess(analyzed, as: MarkdownTypeName(rawValue: scope.name))
            let failedEvaluation = !analyzed.parseDiagnostics.isEmpty || result.diagnostics.contains(where: Self.isEvaluationError)
            assessment = IndexAssessment(selected: result.conforms,
                status: failedEvaluation ? "evaluation-error" : (result.conforms ? "conforms" : "nonconforming"),
                detail: try Self.json(IndexTypePayload(result, path: path)),
                diagnostics: result.diagnostics.map { Self.diagnostic($0, category: "validation") })
        case .rule:
            guard let rules, let rule = rules.rule(named: scope.name) else { throw IndexProjectError("Unknown rule: \(scope.name)") }
            let result = try MarkdownRuleChecker(registry: rules).assess(analyzed, against: rule)
            let evaluationError = !result.applicabilityDiagnostics.isEmpty
                || result.typeExpressionAssessment?.status == .unavailable
                || result.diagnostics.contains { Self.isEvaluationError($0) }
            assessment = IndexAssessment(selected: result.applicable && result.applicabilityDiagnostics.isEmpty,
                status: evaluationError ? "evaluation-error" : result.status.rawValue,
                detail: try Self.json(IndexRulePayload(result: result)),
                diagnostics: result.applicabilityDiagnostics.map { Self.diagnostic($0, category: "selection") }
                    + result.diagnostics.map { Self.diagnostic($0, category: "validation") })
        }
        assessment.diagnostics.append(contentsOf: analyzed.parseDiagnostics.map { Self.diagnostic($0, category: "parse") })
        return IndexEvaluation(metadata: try Self.json(analyzed.userFrontmatter ?? [:]),
            body: analyzed.body, parseState: analyzed.parseDiagnostics.isEmpty ? "ok" : "error", assessment: assessment)
    }

    private static func isEvaluationError(_ diagnostic: MarkdownDiagnostic) -> Bool {
        diagnostic.code.hasSuffix(".engine-error") || diagnostic.code.hasSuffix(".unavailable")
            || diagnostic.code.hasSuffix(".schema-engine") || diagnostic.code == "record.frontmatter.syntax-unavailable"
            || diagnostic.code == "record.markdown-structure.unsupported"
    }

    private static func diagnostic(_ diagnostic: MarkdownDiagnostic, category: String) -> IndexDiagnostic {
        IndexDiagnostic(category: diagnostic.severity == .advisory ? "advisory" : (isEvaluationError(diagnostic) ? "evaluation" : category),
            severity: diagnostic.severity.rawValue, code: diagnostic.code, location: diagnostic.location, message: diagnostic.message)
    }

    private static func json<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// Serialized native bridge for the non-Sendable JMESPath implementation.
private final class IndexJMESPathProvider:
  MarkdownRuleQueryCapabilityProvider,
  @unchecked Sendable
{
  let capabilities: Set<MarkdownRuleRuntimeCapability> = [.frontmatterJMESPath]
  private let lock = NSLock()

  func validateJMESPath(_ expression: String) throws {
    lock.lock()
    defer { lock.unlock() }
    _ = try JMESExpression.compile(expression)
  }

  func evaluateJMESPath(
    _ expression: String,
    frontmatter: JSONValue
  ) throws -> JSONValue? {
    lock.lock()
    defer { lock.unlock() }
    let compiled = try JMESExpression.compile(expression)
    guard let result = try compiled.search(object: frontmatter.foundationValue) else {
      return nil
    }
    return try JSONValue(any: result)
  }
}
