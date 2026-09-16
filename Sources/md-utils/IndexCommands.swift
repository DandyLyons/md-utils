import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

extension CLIEntry {
    /// Groups SQLite collection registration, refresh, and rebuild commands.
    ///
    /// See <doc:IndexCommands> for scope and freshness semantics.
    struct Index: AsyncParsableCommand {
        /// Registers directory, type, and rule selection entry points.
        static let configuration = CommandConfiguration(commandName: "index",
            abstract: "Maintain a rebuildable SQLite collection cache",
            subcommands: [Update.self, SelectType.self, SelectRule.self])

        /// Refreshes every saved scope and optionally registers a directory collection.
        struct Update: AsyncParsableCommand {
            /// Exposes `index update` with optional scope registration.
            static let configuration = CommandConfiguration(abstract: "Refresh all saved scopes, optionally adding a directory")
            /// Working-directory-relative scope to add, or `nil` to refresh existing scopes.
            @Argument(help: "Directory to register, such as ./notes/; omit to refresh saved scopes") var directory: String?
            /// Project resolution and content-verification settings.
            @OptionGroup var options: IndexOptions
            /// Forces reevaluation while retaining saved declarations and SQL schema objects.
            @Flag(help: "Regenerate all saved scopes while preserving field indexes and views") var rebuild = false
            /// Resolves the project and commits a refresh, reporting partial failures.
            mutating func run() async throws {
                try await options.run(kind: .directory, directory: directory, name: "", rebuild: rebuild)
            }
        }

        /// Registers a collection containing only records that conform to a named type.
        struct SelectType: AsyncParsableCommand {
            /// Exposes `index type` with a type name and recursive directory scope.
            static let configuration = CommandConfiguration(commandName: "type", abstract: "Index documents conforming to a type")
            /// Case-sensitive name loaded from the project's type registry.
            @Argument(help: "Type name") var name: String
            /// Directory resolved from the working directory before scope persistence.
            @Argument(help: "Directory to scan, such as ./notes/") var directory: String = "."
            /// Project resolution and content-verification settings.
            @OptionGroup var options: IndexOptions
            /// Registers this selection and refreshes all existing scopes.
            mutating func run() async throws {
                try await options.run(kind: .type, directory: directory, name: name)
            }
        }

        /// Registers project-wide rule membership independently of validation success.
        struct SelectRule: AsyncParsableCommand {
            /// Exposes `index rule` using the existing configured rule evaluator.
            static let configuration = CommandConfiguration(commandName: "rule", abstract: "Index rule-selected documents, including invalid members")
            /// Case-sensitive name from the compiled rule registry.
            @Argument(help: "Rule name") var name: String
            /// Project resolution and content-verification settings.
            @OptionGroup var options: IndexOptions
            /// Registers the named rule and refreshes all saved scopes.
            mutating func run() async throws {
                try await options.run(kind: .rule, directory: nil, name: name)
            }
        }
    }
}

/// Shared project resolution and verification settings for index commands.
struct IndexOptions: ParsableArguments {
    /// Explicit config file, persisted for subsequent refreshes of this cache.
    @Option(help: "Path to project config; saved for subsequent updates") var config: String?
    /// Required root override for a nonstandard config path.
    @Option(help: "Project root directory (defaults to current directory or conventional config root)") var projectRoot: String?
    /// Saved per newly registered scope; existing declarations retain their setting.
    @Flag(name: .customLong("include-non-md"), help: "Include other UTF-8 text files with existing wrapper/comment extraction") var includeNonMD = false
    /// Enables content verification for all scopes in this invocation.
    @Flag(help: "Hash every candidate, detecting content changes even when mtime and size are unchanged") var verifyHashes = false

    /// Resolves and validates the project, refreshes the cache, and reports CLI status.
    ///
    /// Configuration failures invalidate existing scopes. Recoverable scan failures
    /// commit explicit diagnostics and then produce a failing process exit status.
    func run(kind: IndexScope.Kind, directory: String?, name: String, rebuild: Bool = false) async throws {
        let explicitConfig = config.map { Path($0).absolute().normalize() }
        let root: Path
        if let projectRoot { root = Path(projectRoot).absolute().normalize() }
        else if let explicitConfig, explicitConfig.lastComponent == "md-utils.json", explicitConfig.parent().lastComponent == ".md-utils" {
            root = explicitConfig.parent().parent()
        } else {
            guard explicitConfig == nil else { throw ValidationError("A nonstandard config location requires --project-root.") }
            root = Path.current.absolute().normalize()
        }
        let canonicalRoot = URL(fileURLWithPath: root.string).resolvingSymlinksInPath()
        guard root.isDirectory else { throw ValidationError("Project root must be an existing directory: \(root.string)/") }
        let cacheDirectory = canonicalRoot.appendingPathComponent(".md-utils/", isDirectory: true)
        guard cacheDirectory.resolvingSymlinksInPath().path.hasPrefix(canonicalRoot.path + "/") else {
            throw ValidationError("The .md-utils/ directory must remain inside the project root.")
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let database = try SQLiteIndexDatabase(path: cacheDirectory.appendingPathComponent("index.sqlite").path)
        let indexer = try CollectionIndexer(database: database, root: canonicalRoot)
        let persistedConfig = try database.configurationPath(explicitConfig?.string)
        let configPath = Path(persistedConfig ?? cacheDirectory.appendingPathComponent("md-utils.json").path)
        let scope: IndexScope?
        if let directory {
            let selected = URL(fileURLWithPath: Path(directory).absolute().normalize().string).resolvingSymlinksInPath()
            guard selected.path == canonicalRoot.path || selected.path.hasPrefix(canonicalRoot.path + "/") else {
                throw ValidationError("Index scope must be inside --project-root.")
            }
            let relative = selected.path == canonicalRoot.path ? "" : String(selected.path.dropFirst(canonicalRoot.path.count + 1)) + "/"
            scope = IndexScope(kind: kind, path: relative, name: name, includeNonMarkdown: includeNonMD)
        } else if kind == .rule {
            scope = IndexScope(kind: kind, name: name, includeNonMarkdown: includeNonMD)
        } else { scope = nil }
        let evaluator: IndexProjectEvaluator
        do {
            evaluator = try IndexProjectEvaluator(root: Path(canonicalRoot.path), configPath: configPath)
            for candidate in try database.scopes() + (scope.map { [$0] } ?? []) { try evaluator.validate(candidate) }
        } catch {
            try database.invalidate(message: String(describing: error))
            throw error
        }
        let report = try await indexer.update(adding: scope, fingerprint: evaluator.fingerprint,
            rebuild: rebuild, verifyHashes: verifyHashes, evaluate: evaluator.evaluate)
        print("Index: \(report.evaluated) evaluated, \(report.cached) cached, \(report.hashed) hashed; \(try database.selectedPaths().count) current documents.")
        for error in report.errors { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
        if !report.errors.isEmpty { throw ExitCode.failure }
    }
}

/// Adapts the same parsed records and full evaluators used by types find and rules validate.
struct IndexProjectEvaluator {
    /// Native type definitions with all schema references resolved before scanning.
    let types: MarkdownTypeRegistry
    /// Full native rule runtime, including JMESPath, when a config exists.
    let rules: MarkdownRuleRegistry?
    /// Combined configuration and transitive-schema provenance used for broad invalidation.
    let fingerprint: String

    /// Loads definitions and compiles the existing runtime before any candidate is assessed.
    init(root: Path, configPath: Path) throws {
        types = (root + MarkdownTypeFileRegistryLoader.relativeTypesDirectory).exists
            ? try TypesProject.load(root: root) : try MarkdownTypeRegistry(definitions: [])
        let config = configPath.exists ? try MdUtilsConfig.load(from: configPath, projectRoot: root) : nil
        rules = try config?.compiledRuleRegistry(root: root)
        var components = [configPath.string]
        if configPath.exists { components.append(try configPath.read(.utf8)) }
        if let project = config?.standaloneProject {
            for file in project.files { components.append(try Path(file.source).read(.utf8)) }
        }
        // Resolved schemas include transitive resources, including resources outside .md-utils/.
        for registry in [types, rules?.typeRegistry].compactMap({ $0 }) {
            for definition in registry.definitions {
                components.append(try Self.json(TypesRenderer.definitionObject(definition)))
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
                    components.append(try Self.json(rule.resolvedSchemas.mapValues(\.foundationValue)))
                }
            }
        }
        fingerprint = IndexFingerprint.combined(components)
    }

    /// Rejects unknown type or rule names before starting a scan.
    func validate(_ scope: IndexScope) throws {
        if scope.kind == .type, types.definition(named: scope.name) == nil { throw ValidationError("Unknown type: \(scope.name)") }
        if scope.kind == .rule, rules?.rule(named: scope.name) == nil { throw ValidationError("Unknown rule: \(scope.name)") }
    }

    /// Extracts one record and preserves membership, validation, and branch evidence separately.
    func evaluate(scope: IndexScope, path: String, content: String, modified: Date) async throws -> IndexEvaluation {
        let record = MarkdownRecord(content: content,
            context: MarkdownRecordContext(path: try MarkdownRecordPath(path), modificationDate: modified))
        let analyzed = await MarkdownRecordAnalyzer.analyze(record,
            contentKind: .rulesKind(forFileName: URL(fileURLWithPath: path).lastPathComponent))
        var assessment: IndexAssessment
        switch scope.kind {
        case .directory:
            assessment = IndexAssessment(selected: true, status: analyzed.parseDiagnostics.isEmpty ? "selected" : "parse-error")
        case .type:
            let result = try MarkdownTypeChecker(registry: types).assess(analyzed, as: MarkdownTypeName(rawValue: scope.name))
            let failedEvaluation = !analyzed.parseDiagnostics.isEmpty || result.diagnostics.contains(where: Self.isEvaluationError)
            assessment = IndexAssessment(selected: result.conforms,
                status: failedEvaluation ? "evaluation-error" : (result.conforms ? "conforms" : "nonconforming"),
                detail: try Self.json(TypesRenderer.assessmentObject(result, path: path)),
                diagnostics: result.diagnostics.map { Self.diagnostic($0, category: "validation") })
        case .rule:
            guard let rules, let rule = rules.rule(named: scope.name) else { throw ValidationError("Unknown rule: \(scope.name)") }
            let result = try MarkdownRuleChecker(registry: rules).assess(analyzed, against: rule)
            let evaluationError = !result.applicabilityDiagnostics.isEmpty
                || result.typeExpressionAssessment?.status == .unavailable
                || result.diagnostics.contains { Self.isEvaluationError($0) }
            assessment = IndexAssessment(selected: result.applicable && result.applicabilityDiagnostics.isEmpty,
                status: evaluationError ? "evaluation-error" : result.status.rawValue,
                detail: try Self.json([
                    "status": result.status.rawValue,
                    "evidence": try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.evidence)),
                    "typeAssessments": result.typeAssessments.mapValues { TypesRenderer.assessmentObject($0, path: nil) },
                    "typeExpression": result.typeExpressionAssessment.map(Self.expressionObject) ?? [:],
                ]), diagnostics: result.applicabilityDiagnostics.map { Self.diagnostic($0, category: "selection") }
                    + result.diagnostics.map { Self.diagnostic($0, category: "validation") })
        }
        assessment.diagnostics.append(contentsOf: analyzed.parseDiagnostics.map { Self.diagnostic($0, category: "parse") })
        return IndexEvaluation(metadata: try Self.json((analyzed.userFrontmatter ?? [:]).mapValues(\.foundationValue)),
            body: analyzed.body, parseState: analyzed.parseDiagnostics.isEmpty ? "ok" : "error", assessment: assessment)
    }

    private static func expressionObject(_ expression: MarkdownRuleTypeExpressionAssessment) -> [String: Any] {
        var object: [String: Any] = ["location": expression.location, "status": expression.status.rawValue,
            "children": expression.children.map(expressionObject)]
        if let reference = expression.reference { object["reference"] = reference }
        if let assessment = expression.assessment { object["assessment"] = TypesRenderer.assessmentObject(assessment, path: nil) }
        return object
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

    private static func json(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
    }
}
