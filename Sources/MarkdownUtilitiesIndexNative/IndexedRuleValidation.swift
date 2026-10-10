import Foundation
import GRDB
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

/// A current rule assessment, independent of selection and parsed-document views.
public struct IndexedRuleValidationResult: Sendable {
    public var ruleName: String
    public var path: String
    public var status: MarkdownRuleAssessmentStatus
    public var diagnostics: [IndexDiagnostic]
}

/// Results and work counts from one committed rule-validation refresh.
public struct IndexedRuleValidation: Sendable {
    public var results: [IndexedRuleValidationResult]
    public var totalFiles: Int
    public var report: IndexUpdateReport

    /// Registers and refreshes only the requested project-wide rule scopes.
    /// Unavailable cached data throws so callers can validate authoritative files.
    public static func validate(database: SQLiteIndexDatabase, root: Path, configPath: Path,
        ruleNames: [String], includeNonMarkdown: Bool, verifyHashes: Bool) async throws -> Self {
        let evaluator = try IndexProjectEvaluator(root: root, configPath: configPath)
        let scopes = ruleNames.map { IndexScope(kind: .rule, name: $0, includeNonMarkdown: includeNonMarkdown) }
        for scope in scopes { try evaluator.validate(scope) }
        guard !scopes.isEmpty else {
            return Self(results: [], totalFiles: 0, report: IndexUpdateReport())
        }
        let url = URL(fileURLWithPath: root.string).resolvingSymlinksInPath()
        let lease = try await CollectionWriterLease.acquire(root: url)
        defer { withExtendedLifetime(lease) {} }
        let indexer = try CollectionIndexer(database: database, root: url)
        try database.validateSavedConfiguration()
        _ = try database.configurationPath(configPath.absolute().normalize().string)
        let directories = Dictionary(uniqueKeysWithValues: scopes.map { ($0.id, evaluator.discoveryDirectories(for: $0)) })
        let report = try await indexer.updateMany(refreshing: scopes, discoveryDirectories: directories, writerLease: lease,
            fingerprint: evaluator.fingerprint, verifyHashes: verifyHashes, evaluate: evaluator.evaluate)
        try Task.checkCancellation()
        guard report.errors.isEmpty && report.omittedErrorCount == 0 else {
            throw IndexProjectError(report.errors.first ?? "Index refresh failed.")
        }
        return try snapshot(database: database, scopes: scopes, fingerprint: evaluator.fingerprint, report: report)
    }

    /// Checks freshness and reads assessments and diagnostics in one serialized snapshot.
    package static func snapshot(database: SQLiteIndexDatabase, scopes: [IndexScope],
        fingerprint: String, report: IndexUpdateReport) throws -> Self {
        try database.serverRead { db in
            guard try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='generation'") == report.generation,
                try Int.fetchOne(db, sql: "SELECT value FROM index_metadata WHERE key='published_generation'") == report.generation else {
                throw IndexProjectError("Index validation snapshot was superseded; retry validation.")
            }
            for scope in scopes {
                guard try Bool.fetchOne(db, sql: "SELECT state='complete' AND fingerprint=? FROM scopes WHERE id=?",
                    arguments: [fingerprint, scope.id]) == true else {
                    throw IndexProjectError("Rule scope is unavailable: \(scope.name)")
                }
            }
            let placeholders = scopes.map { _ in "?" }.joined(separator: ",")
            let arguments = StatementArguments(scopes.map(\.id))
            let total = try Int.fetchOne(db, sql: "SELECT count(DISTINCT path) FROM assessments WHERE scope_id IN (\(placeholders))",
                arguments: arguments) ?? 0
            let names = Dictionary(uniqueKeysWithValues: scopes.map { ($0.id, $0.name) })
            let cursor = try Row.fetchCursor(db, sql: """
                SELECT a.scope_id,a.path,a.status,d.category,d.severity,d.code,d.location,d.message
                FROM assessments a LEFT JOIN diagnostics d
                  ON d.scope_id=a.scope_id AND d.path=a.path AND d.category!='parse'
                WHERE a.scope_id IN (\(placeholders))
                ORDER BY a.path,a.scope_id,d.rowid
                """, arguments: arguments)
            var results: [IndexedRuleValidationResult] = []
            var previous: (String, String)?
            var activeIndex: Int?
            while let row = try cursor.next() {
                try Task.checkCancellation()
                let scopeID: String = row["scope_id"]
                let path: String = row["path"]
                if previous?.0 != scopeID || previous?.1 != path {
                    guard let status = MarkdownRuleAssessmentStatus(rawValue: row["status"]) else {
                        throw IndexProjectError("Rule assessment is unavailable: \(path)")
                    }
                    activeIndex = nil
                    if status != .notApplicable {
                        guard let name = names[scopeID] else { throw IndexProjectError("Unknown validation scope.") }
                        results.append(IndexedRuleValidationResult(ruleName: name, path: path, status: status, diagnostics: []))
                        activeIndex = results.count - 1
                    }
                    previous = (scopeID, path)
                }
                if let index = activeIndex, let category: String = row["category"] {
                    results[index].diagnostics.append(IndexDiagnostic(category: category, severity: row["severity"],
                        code: row["code"], location: row["location"], message: row["message"]))
                }
            }
            return Self(results: results, totalFiles: total, report: report)
        }
    }
}
