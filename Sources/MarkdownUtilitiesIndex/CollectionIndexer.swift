import Crypto
import Foundation

/// Stable SHA-256 fingerprints for content and evaluator cache provenance.
public enum IndexFingerprint {
    /// Bump when extraction or evaluator semantics change, independently of database migrations.
    public static let runtimeVersion = "collection-extraction-evaluation-1"

    /// Returns the lowercase hexadecimal SHA-256 digest of the exact supplied bytes.
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Combines ordered configuration and schema components with ``runtimeVersion``.
    ///
    /// Components are length-prefixed to preserve boundaries. Callers must use
    /// deterministic ordering and include all transitive evaluator dependencies.
    public static func combined(_ components: [String]) -> String {
        // Encoding boundaries prevents ambiguous concatenations.
        hash(Data(([runtimeVersion] + components).map { "\($0.utf8.count):\($0)" }.joined().utf8))
    }
}

/// Work counts and recoverable failures from a committed collection refresh.
///
/// Counts are per scope-candidate pair, so overlapping scopes can count one file
/// multiple times. A successful return does not imply an error-free scan.
public struct IndexUpdateReport: Sendable {
    /// Number of completed evaluator calls, including returned parse or validation failures.
    public var evaluated = 0
    /// Number of candidates whose prior assessment was reused.
    public var cached = 0
    /// Number of successful file reads hashed during this refresh.
    public var hashed = 0
    /// Incomplete scopes and read, parse, or evaluation failures requiring attention.
    public var errors: [String] = []
}

/// Refreshes persisted text collections using host-supplied extraction and assessment.
///
/// Scans are best-effort filesystem observations, not atomic filesystem snapshots.
/// Evaluation occurs outside SQLite; committing uses an optimistic generation check.
/// See <doc:RefreshingCollections> for scope retention and recovery semantics.
public struct CollectionIndexer {
    /// Checked SQLite connection receiving transactional collection updates.
    public let database: SQLiteIndexDatabase
    /// Canonical project directory used to resolve all saved relative scope paths.
    public let root: URL

    /// Binds a checked database to its canonical project root and applies migrations.
    ///
    /// - Throws: Migration errors, unsupported newer schemas, or a different persisted root.
    public init(database: SQLiteIndexDatabase, root: URL) throws {
        self.database = database
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try database.prepareCollection(root: self.root.path)
    }

    /// Refreshes every persisted scope, optionally registering another selection.
    ///
    /// Hidden entries and symlinks are skipped. Missing entries are pruned only after
    /// successful enumeration of their scope. Rebuild keeps saved scopes, SQL field
    /// indexes, and views, and ignores all cached candidate assessments.
    ///
    /// - Parameters:
    ///   - scope: Optional additional declaration; existing scopes remain registered.
    ///   - fingerprint: Combined configuration, schema, and evaluator provenance.
    ///   - rebuild: Reevaluate every candidate regardless of cached state.
    ///   - verifyHashes: Read and hash candidates even when mtime and size are unchanged.
    ///   - evaluate: Receives the scope, root-relative path, decoded UTF-8 source,
    ///     and observed modification date. Return extracted content and assessment.
    /// - Returns: Per-scope work counts and recoverable failures. Inspect
    ///   ``IndexUpdateReport/errors`` before treating the refresh as successful.
    /// - Throws: Invalid scopes, cancellation, database failures, or a superseded
    ///   update generation. Other evaluator errors become persisted diagnostics.
    public func update(
        adding scope: IndexScope? = nil,
        fingerprint: String,
        rebuild: Bool = false,
        verifyHashes: Bool = false,
        evaluate: (IndexScope, String, String, Date) async throws -> IndexEvaluation
    ) async throws -> IndexUpdateReport {
        var scopes = try database.scopes()
        if let scope, !scopes.contains(scope) { scopes.append(scope) }
        guard !scopes.isEmpty else { throw SQLiteIndexError(message: "No index scopes registered. Supply a directory to index update.") }
        for scope in scopes { try validate(scope) }
        let snapshot = try database.begin(scopes: scopes, fingerprint: fingerprint)
        var report = IndexUpdateReport()
        var results: [IndexScopeChange] = []
        for scope in scopes {
            try Task.checkCancellation()
            var result = IndexScopeChange(scope: scope, seen: [], changes: [])
            let files: [URL]
            do {
                files = try enumerate(scope)
            } catch {
                result.error = "\(scope.path): \(error)"
                report.errors.append(result.error ?? "Incomplete scope")
                results.append(result)
                continue
            }
            for file in files {
                try Task.checkCancellation()
                let path = String(file.path.dropFirst(root.path.count + 1))
                result.seen.insert(path)
                var mtime = 0.0
                var size: Int64 = 0
                var hash = ""
                do {
                    let before = try stat(file)
                    mtime = before.0
                    size = before.1
                    let old = snapshot.files[path]
                    let reusable = !rebuild && old?.state == "ok"
                        && old?.mtime == mtime && old?.size == size
                        && snapshot.assessments[scope.id]?.contains(path) == true
                    if reusable && !verifyHashes {
                        report.cached += 1
                        continue
                    }
                    let data = try Data(contentsOf: file)
                    hash = IndexFingerprint.hash(data)
                    report.hashed += 1
                    let afterRead = try stat(file)
                    guard before == afterRead, Int64(data.count) == size else {
                        throw SQLiteIndexError(message: "File changed while reading; retry update: \(path)")
                    }
                    if reusable && hash == old?.hash {
                        report.cached += 1
                        continue
                    }
                    guard let content = String(data: data, encoding: .utf8) else {
                        throw SQLiteIndexError(message: "File is not UTF-8 text: \(path)")
                    }
                    let evaluation = try await evaluate(scope, path, content, Date(timeIntervalSince1970: mtime))
                    guard try stat(file) == before else {
                        throw SQLiteIndexError(message: "File changed during evaluation; retry update: \(path)")
                    }
                    result.changes.append(IndexFileChange(path: path, mtime: mtime, size: size, hash: hash, evaluation: evaluation))
                    report.evaluated += 1
                    if evaluation.parseState != "ok" || evaluation.assessment.status == "evaluation-error" {
                        report.errors.append("\(path): \(evaluation.assessment.status) (\(evaluation.parseState))")
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    report.errors.append("\(path): \(error)")
                    let diagnostic = IndexDiagnostic(category: "evaluation", severity: "error", code: "index.read-or-evaluate",
                        location: path, message: String(describing: error))
                    let evaluation = IndexEvaluation(metadata: "{}", body: "", parseState: "error",
                        assessment: IndexAssessment(selected: false, status: "evaluation-error", diagnostics: [diagnostic]))
                    result.changes.append(IndexFileChange(path: path, mtime: mtime, size: size, hash: hash, evaluation: evaluation))
                }
            }
            results.append(result)
        }
        try Task.checkCancellation()
        try database.commit(results, fingerprint: fingerprint, generation: snapshot.generation)
        return report
    }

    private func validate(_ scope: IndexScope) throws {
        let components = scope.path.split(separator: "/", omittingEmptySubsequences: false)
        guard scope.path.isEmpty || (!scope.path.hasPrefix("/") && scope.path.hasSuffix("/")
            && components.dropLast().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })) else {
            throw SQLiteIndexError(message: "Scope must be a project-relative directory with a trailing slash: \(scope.path)")
        }
    }

    private func stat(_ file: URL) throws -> (Double, Int64) {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let modified = attributes[.modificationDate] as? Date,
            let size = attributes[.size] as? NSNumber else {
            throw SQLiteIndexError(message: "Not a regular file or metadata unavailable: \(file.path)")
        }
        return (modified.timeIntervalSince1970, size.int64Value)
    }

    private func enumerate(_ scope: IndexScope) throws -> [URL] {
        let directory = root.appendingPathComponent(scope.path, isDirectory: true)
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == root.path || canonical.path.hasPrefix(root.path + "/") else {
            throw SQLiteIndexError(message: "Scope escapes project root: \(scope.path)")
        }
        var files: [URL] = []
        // Throwing traversal is deliberate: Foundation's default enumerator can silently skip errors.
        func visit(_ directory: URL) throws {
            for file in try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                // Do not follow symlinks into other scopes or cycles.
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true { try visit(file) }
                else if values.isRegularFile == true,
                    scope.includeNonMarkdown || ["md", "markdown"].contains(file.pathExtension.lowercased()) {
                    files.append(file)
                }
            }
        }
        try visit(directory)
        return files.sorted { $0.path < $1.path }
    }
}
