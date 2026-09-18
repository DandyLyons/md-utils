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
            subcommands: [Update.self, SelectType.self, SelectRule.self, Query.self, Explain.self,
                Field.self, Search.self, Status.self])

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
            /// Explicit compatibility recovery from authoritative files.
            @Option(help: "Use text with --rebuild to recover a JSONB cache on older SQLite") var metadataEncoding: String?
            /// Resolves the project and commits a refresh, reporting partial failures.
            mutating func run() async throws {
                if let metadataEncoding {
                    guard rebuild, metadataEncoding == "text" else {
                        throw ValidationError("--metadata-encoding accepts text and requires --rebuild.")
                    }
                    let context = try options.context(prepare: false)
                    try await context.database.rebuildAsText(root: context.canonicalRoot.path,
                        scratchDirectory: context.canonicalRoot.appendingPathComponent(".md-utils/rebuild/")) { copy in
                        try await options.run(kind: .directory, directory: directory, name: "", rebuild: true,
                            databaseOverride: copy)
                    }
                } else {
                    try await options.run(kind: .directory, directory: directory, name: "", rebuild: rebuild)
                }
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

        /// Refreshes every scope, then executes one bounded read-only SQL statement.
        struct Query: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Refresh the index and run read-only SQL")
            @Argument(help: "One read-only SQL statement") var sql: String
            @OptionGroup var options: IndexOptions
            @Option(help: "Maximum rows to return") var limit = 1_000
            @Option(help: "Maximum aggregate SQLite value bytes") var maxBytes = 64 * 1_024 * 1_024
            @Option(help: "Maximum bytes in one text or BLOB value") var maxValueBytes = 16 * 1_024 * 1_024
            @Option(help: "Output format: json, jsonl, csv, or nul") var format: IndexQueryFormat = .json

            mutating func run() async throws {
                let database = try await options.run(kind: .directory, directory: nil, name: "", quiet: true)
                try IndexStreamingQueryRenderer.render(database: database, sql: sql, format: format,
                    limits: IndexQueryLimits(rows: limit, bytes: maxBytes, valueBytes: maxValueBytes),
                    shouldCancel: { Task.isCancelled })
            }
        }

        /// Refreshes every scope and prints SQLite's plan for a read-only statement.
        struct Explain: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Refresh the index and explain a read-only SQL query")
            @Argument(help: "Read-only SQL statement to explain") var sql: String
            @OptionGroup var options: IndexOptions
            @Option(help: "Maximum plan rows to return") var limit = 1_000
            @Option(help: "Maximum aggregate SQLite value bytes") var maxBytes = 64 * 1_024 * 1_024
            @Option(help: "Maximum bytes in one text or BLOB value") var maxValueBytes = 16 * 1_024 * 1_024
            @Option(help: "Output format: json, jsonl, csv, or nul") var format: IndexQueryFormat = .json

            mutating func run() async throws {
                let database = try await options.run(kind: .directory, directory: nil, name: "", quiet: true)
                try IndexStreamingQueryRenderer.render(database: database, sql: "EXPLAIN QUERY PLAN \(sql)", format: format,
                    limits: IndexQueryLimits(rows: limit, bytes: maxBytes, valueBytes: maxValueBytes),
                    shouldCancel: { Task.isCancelled })
            }
        }

        /// Manages explicit JSON expression indexes and type-view projections.
        struct Field: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Manage JSON field indexes",
                subcommands: [Add.self, Remove.self, List.self])

            struct Add: ParsableCommand {
                @Argument(help: "SQLite JSON path, such as $.status") var jsonPath: String
                @Option(help: "Projected SQL column name (lowercase letters, numbers, underscores)") var name: String?
                @OptionGroup var options: IndexOptions
                mutating func run() throws {
                    let field = try options.context().database.addField(jsonPath: jsonPath, columnName: name)
                    print("\(field.columnName)\t\(field.queryExpression)\t\(field.name)")
                }
            }

            struct Remove: ParsableCommand {
                @Argument(help: "JSON path or projected column name") var field: String
                @OptionGroup var options: IndexOptions
                mutating func run() throws {
                    guard try options.context().database.removeField(field) else {
                        throw ValidationError("No managed field found for \(field).")
                    }
                }
            }

            struct List: ParsableCommand {
                @OptionGroup var options: IndexOptions
                mutating func run() throws {
                    for field in try options.context().database.fields() {
                        print("\(field.columnName)\t\(field.jsonPath)\t\(field.queryExpression)\t\(field.name)")
                    }
                }
            }
        }

        /// Manages opt-in body retention and FTS5 search.
        struct Search: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Manage optional full-text body indexing",
                subcommands: [Enable.self, Disable.self, Status.self])

            struct Enable: AsyncParsableCommand {
                @OptionGroup var options: IndexOptions
                mutating func run() async throws {
                    let database = try options.context().database
                    try database.setBodyMode(.fts)
                    guard !(try database.scopes()).isEmpty else {
                        print("FTS enabled; register a scope to populate search content.")
                        return
                    }
                    _ = try await options.run(kind: .directory, directory: nil, name: "", rebuild: true)
                }
            }

            struct Disable: ParsableCommand {
                @OptionGroup var options: IndexOptions
                @Flag(help: "Run VACUUM after removing cached bodies and FTS pages") var vacuum = false
                mutating func run() throws {
                    let database = try options.context().database
                    try database.setBodyMode(.metadataOnly)
                    if vacuum { try database.vacuum() }
                }
            }

            struct Status: ParsableCommand {
                @OptionGroup var options: IndexOptions
                mutating func run() throws {
                    let policy = try options.context().database.storagePolicy()
                    print("body-mode: \(policy.bodyMode.rawValue)")
                    print("metadata-encoding: \(policy.metadataEncoding.rawValue)")
                }
            }
        }

        /// Shows whether all saved scopes completed and when refreshes ran.
        struct Status: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Inspect index freshness and saved scopes")
            @OptionGroup var options: IndexOptions
            mutating func run() throws {
                let status = try options.context().database.freshness()
                print("current: \(status.isCurrent ? "yes" : "no")")
                print("generation: \(status.generation)")
                print("failures: \(status.hasFailures ? "yes" : "no")")
                print("last-started: \(status.lastStartedAt.map { String($0) } ?? "never")")
                print("last-completed: \(status.lastCompletedAt.map { String($0) } ?? "never")")
                for scope in status.scopes {
                    let label = scope.definition.name.isEmpty ? scope.definition.path : scope.definition.name
                    print("\(scope.definition.kind.rawValue)\t\(label)\t\(scope.state)\t\(scope.error ?? "")")
                }
            }
        }
    }
}

enum IndexQueryFormat: String, ExpressibleByArgument {
    case json
    case jsonl
    case csv
    case nul
}

enum IndexQueryValueRenderer {
    static func textValue(_ value: IndexQueryValue) -> String {
        switch value {
        case .null: ""
        case .integer(let value): String(value)
        case .real(let value): String(value)
        case .text(let value): value
        case .blob(let data): data.base64EncodedString()
        }
    }

    static func csv(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum IndexStreamingQueryRenderer {
    static func render(database: SQLiteIndexDatabase, sql: String, format: IndexQueryFormat,
        limits: IndexQueryLimits, shouldCancel: () -> Bool,
        output: FileHandle = .standardOutput) throws {
        var columnNames: [String] = []
        var firstJSONRow = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let summary = try database.streamQuery(sql, limits: limits, shouldCancel: shouldCancel, columns: { columns in
            columnNames = columns
            switch format {
            case .json:
                let encoded = try encoder.encode(columns)
                write(Data("{\"columns\":".utf8), to: output)
                write(encoded, to: output)
                write(Data(",\"rows\":[".utf8), to: output)
            case .jsonl:
                guard Set(columns).count == columns.count else {
                    throw ValidationError("JSONL output requires unique SQL column names; add aliases to duplicate columns.")
                }
            case .csv:
                write(Data((columns.map(IndexQueryValueRenderer.csv).joined(separator: ",") + "\n").utf8), to: output)
            case .nul:
                guard columns.count == 1 else { throw ValidationError("NUL output requires exactly one SQL column.") }
            }
        }, yield: { row in
            switch format {
            case .json:
                if !firstJSONRow { write(Data(",".utf8), to: output) }
                write(try encoder.encode(row.map { IndexQueryJSONValue(value: $0) }), to: output)
                firstJSONRow = false
            case .jsonl:
                let object = Dictionary(uniqueKeysWithValues: zip(columnNames, row.map { IndexQueryJSONValue(value: $0) }))
                write(try encoder.encode(object), to: output)
                write(Data("\n".utf8), to: output)
            case .csv:
                let line = row.map(IndexQueryValueRenderer.textValue).map(IndexQueryValueRenderer.csv).joined(separator: ",") + "\n"
                write(Data(line.utf8), to: output)
            case .nul:
                guard case .text(let path) = row[0] else {
                    throw ValidationError("NUL output requires a text path column.")
                }
                write(Data(path.utf8), to: output)
                write(Data([0]), to: output)
            }
        })
        if format == .json {
            write(Data("],\"truncated\":\(summary.truncated ? "true" : "false")}\n".utf8), to: output)
        }
    }

    private static func write(_ data: Data, to output: FileHandle) { output.write(data) }
}

/// Shared project resolution and verification settings for index commands.
struct IndexOptions: ParsableArguments {
    /// Explicit config file, persisted for subsequent refreshes of this cache.
    @Option(help: "Path to project config; saved for subsequent updates") var config: String?
    /// Required root override for a nonstandard config path.
    @Option(help: "Project root directory (defaults to current directory or conventional config root)") var projectRoot: String?
    /// Alternate SQLite cache path; the stored root must match this project.
    @Option(help: "SQLite index path (defaults to <project-root>/.md-utils/index.sqlite)") var database: String?
    /// Saved per newly registered scope; existing declarations retain their setting.
    @Flag(name: .customLong("include-non-md"), help: "Include other UTF-8 text files with existing wrapper/comment extraction") var includeNonMD = false
    /// Enables content verification for all scopes in this invocation.
    @Flag(help: "Hash every candidate, detecting content changes even when mtime and size are unchanged") var verifyHashes = false

    /// Resolves and validates the project, refreshes the cache, and reports CLI status.
    ///
    /// Configuration failures invalidate existing scopes. Recoverable scan failures
    /// commit explicit diagnostics and then produce a failing process exit status.
    @discardableResult
    func run(kind: IndexScope.Kind, directory: String?, name: String, rebuild: Bool = false,
        quiet: Bool = false, databaseOverride: SQLiteIndexDatabase? = nil) async throws -> SQLiteIndexDatabase {
        let context = try context(prepare: false, databaseOverride: databaseOverride)
        let root = context.root
        let canonicalRoot = context.canonicalRoot
        let database = context.database
        let indexer = try CollectionIndexer(database: database, root: canonicalRoot)
        let configPath = context.configPath
        let persistedConfig = try database.configurationPath(context.explicitConfig?.string)
        let resolvedConfigPath = Path(persistedConfig ?? configPath.string)
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
            evaluator = try IndexProjectEvaluator(root: root, configPath: resolvedConfigPath)
            for candidate in try database.scopes() + (scope.map { [$0] } ?? []) { try evaluator.validate(candidate) }
        } catch {
            try database.invalidate(message: String(describing: error))
            throw error
        }
        let report = try await indexer.updateMany(adding: scope, fingerprint: evaluator.fingerprint,
            rebuild: rebuild, verifyHashes: verifyHashes, evaluate: evaluator.evaluate)
        if !quiet {
            print("Index: \(report.evaluated) evaluated, \(report.cached) cached, \(report.hashed) hashed; \(try database.selectedCount()) current documents.")
        }
        for error in report.errors { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
        if report.omittedErrorCount > 0 {
            FileHandle.standardError.write(Data("\(report.omittedErrorCount) additional failures; inspect persisted index diagnostics.\n".utf8))
        }
        if !report.errors.isEmpty { throw ExitCode.failure }
        return database
    }

    func context(prepare: Bool = true, databaseOverride: SQLiteIndexDatabase? = nil) throws -> IndexCommandContext {
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
        let databasePath = database.map { Path($0).absolute().normalize().string }
            ?? cacheDirectory.appendingPathComponent("index.sqlite").path
        let indexDatabase = try databaseOverride ?? SQLiteIndexDatabase(path: databasePath)
        if prepare { try indexDatabase.prepareCollection(root: canonicalRoot.path) }
        return IndexCommandContext(root: Path(canonicalRoot.path), canonicalRoot: canonicalRoot,
            database: indexDatabase,
            configPath: Path(cacheDirectory.appendingPathComponent("md-utils.json").path), explicitConfig: explicitConfig)
    }
}

struct IndexCommandContext {
    let root: Path
    let canonicalRoot: URL
    let database: SQLiteIndexDatabase
    let configPath: Path
    let explicitConfig: Path?
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
    func validate(_ scope: IndexScope) throws {
        if scope.kind == .type, types.definition(named: scope.name) == nil { throw ValidationError("Unknown type: \(scope.name)") }
        if scope.kind == .rule, rules?.rule(named: scope.name) == nil { throw ValidationError("Unknown rule: \(scope.name)") }
    }

    /// Extracts one record and applies every requested scope without reparsing it.
    func evaluate(scopes: [IndexScope], path: String, content: String, modified: Date) async throws
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
    func evaluate(scope: IndexScope, path: String, content: String, modified: Date) async throws -> IndexEvaluation {
        let evaluations = try await evaluate(scopes: [scope], path: path, content: content, modified: modified)
        guard let evaluation = evaluations[scope.id] else {
            throw ValidationError("Evaluator returned no result for scope \(scope.id).")
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
            guard let rules, let rule = rules.rule(named: scope.name) else { throw ValidationError("Unknown rule: \(scope.name)") }
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
