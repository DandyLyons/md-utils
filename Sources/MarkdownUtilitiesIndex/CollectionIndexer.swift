import Crypto
import Foundation
import GRDB

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

/// Memory bounds for filesystem discovery and individual source reads.
public struct IndexRefreshLimits: Equatable, Sendable {
    /// Number of staged candidate paths fetched from SQLite at once.
    public var candidateBatchCount: Int
    /// Maximum discovered paths retained before staging them.
    public var discoveryBatchCount: Int
    /// Maximum UTF-8 bytes retained while batching discovered paths.
    public var discoveryBatchBytes: Int
    /// Maximum bytes read for one source file.
    public var fileBytes: Int64

    public init(candidateBatchCount: Int = 256, discoveryBatchCount: Int = 1_024,
        discoveryBatchBytes: Int = 256 * 1_024,
        fileBytes: Int64 = 64 * 1_024 * 1_024) {
        self.candidateBatchCount = candidateBatchCount
        self.discoveryBatchCount = discoveryBatchCount
        self.discoveryBatchBytes = discoveryBatchBytes
        self.fileBytes = fileBytes
    }
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
        limits: IndexRefreshLimits = IndexRefreshLimits(),
        evaluate: (IndexScope, String, String, Date) async throws -> IndexEvaluation
    ) async throws -> IndexUpdateReport {
        try await updateMany(adding: scope, fingerprint: fingerprint, rebuild: rebuild,
            verifyHashes: verifyHashes, limits: limits) { scopes, path, content, modified in
            var evaluations: [String: IndexEvaluation] = [:]
            for scope in scopes {
                evaluations[scope.id] = try await evaluate(scope, path, content, modified)
            }
            return evaluations
        }
    }

    /// Refreshes persisted scopes while extracting each changed source only once.
    ///
    /// The evaluator receives every scope needing a fresh assessment for the file.
    /// Returning results keyed by ``IndexScope/id`` lets a host parse or otherwise
    /// extract the source once and apply multiple selection policies to that result.
    public func updateMany(
        adding scope: IndexScope? = nil,
        fingerprint: String,
        rebuild: Bool = false,
        verifyHashes: Bool = false,
        limits: IndexRefreshLimits = IndexRefreshLimits(),
        evaluate: ([IndexScope], String, String, Date) async throws -> [String: IndexEvaluation]
    ) async throws -> IndexUpdateReport {
        guard limits.candidateBatchCount > 0, limits.discoveryBatchCount > 0,
            limits.discoveryBatchBytes > 0, limits.fileBytes > 0,
            let maximumRead = Int(exactly: limits.fileBytes), maximumRead < Int.max else {
            throw SQLiteIndexError(message: "Refresh limits must be positive.")
        }
        var scopes = try database.scopes()
        if let scope, !scopes.contains(scope) { scopes.append(scope) }
        guard !scopes.isEmpty else { throw SQLiteIndexError(message: "No index scopes registered. Supply a directory to index update.") }
        for scope in scopes { try validate(scope) }
        let generation = try database.beginStagedRefresh(scopes: scopes, fingerprint: fingerprint)
        var report = IndexUpdateReport()
        var scopeErrors: [String: String] = [:]
        let scopesByID = Dictionary(uniqueKeysWithValues: scopes.map { ($0.id, $0) })
        for scope in scopes {
            try Task.checkCancellation()
            var paths: [String] = []
            var pathBytes = 0
            func flush() throws {
                try database.stageSeen(generation: generation, scopeID: scope.id, paths: paths)
                paths.removeAll(keepingCapacity: true)
                pathBytes = 0
            }
            do {
                try enumerate(scope) { file in
                    let path = String(file.path.dropFirst(root.path.count + 1))
                    paths.append(path)
                    pathBytes += path.utf8.count
                    if paths.count >= limits.discoveryBatchCount || pathBytes >= limits.discoveryBatchBytes {
                        try flush()
                    }
                }
                try flush()
            } catch {
                let message = "\(scope.path): \(error)"
                scopeErrors[scope.id] = message
                report.errors.append(message)
            }
        }
        var after: String?
        while true {
            let paths = try database.stagedCandidatePaths(generation: generation, after: after,
                limit: limits.candidateBatchCount)
            guard !paths.isEmpty else { break }
            for path in paths {
                try Task.checkCancellation()
                let file = root.appendingPathComponent(path)
                let scopeIDs = try database.stagedScopeIDs(generation: generation, path: path)
                var mtime = 0.0
                var size: Int64 = 0
                var hash = ""
                do {
                    let before = try stat(file)
                    mtime = before.0
                    size = before.1
                    guard size <= limits.fileBytes else {
                        throw SQLiteIndexError(message: "File exceeds the \(limits.fileBytes)-byte refresh limit: \(path)")
                    }
                    var cache: [String: CachedIndexCandidate] = [:]
                    for scopeID in scopeIDs {
                        cache[scopeID] = try database.cachedCandidate(
                            generation: generation, scopeID: scopeID, path: path)
                    }
                    let reusable: (String) -> Bool = { scopeID in
                        guard !rebuild, let candidate = cache[scopeID], let old = candidate.file else { return false }
                        return candidate.assessmentReusable && old.state == "ok" && old.mtime == mtime && old.size == size
                    }
                    if !verifyHashes && scopeIDs.allSatisfy(reusable) {
                        report.cached += scopeIDs.count
                        continue
                    }
                    let handle = try FileHandle(forReadingFrom: file)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: maximumRead + 1) ?? Data()
                    guard data.count <= maximumRead else {
                        throw SQLiteIndexError(message: "File exceeds the \(limits.fileBytes)-byte refresh limit: \(path)")
                    }
                    hash = IndexFingerprint.hash(data)
                    report.hashed += 1
                    let afterRead = try stat(file)
                    guard before == afterRead, Int64(data.count) == size else {
                        throw SQLiteIndexError(message: "File changed while reading; retry update: \(path)")
                    }
                    guard let content = String(data: data, encoding: .utf8) else {
                        throw SQLiteIndexError(message: "File is not UTF-8 text: \(path)")
                    }
                    var scopesToEvaluate: [IndexScope] = []
                    for scopeID in scopeIDs {
                        if reusable(scopeID), cache[scopeID]?.file?.hash == hash {
                            report.cached += 1
                            continue
                        }
                        guard let scope = scopesByID[scopeID] else {
                            throw SQLiteIndexError(message: "Refresh staging references an unknown scope: \(scopeID)")
                        }
                        scopesToEvaluate.append(scope)
                    }
                    let evaluations = try await evaluate(scopesToEvaluate, path, content,
                        Date(timeIntervalSince1970: mtime))
                    for scope in scopesToEvaluate {
                        guard let evaluation = evaluations[scope.id] else {
                            throw SQLiteIndexError(message: "Evaluator returned no result for scope \(scope.id) and path \(path).")
                        }
                        let change = IndexFileChange(path: path, mtime: mtime, size: size, hash: hash, evaluation: evaluation)
                        try database.stageChange(generation: generation, scopeID: scope.id, file: change)
                        report.evaluated += 1
                        if evaluation.parseState != "ok" || evaluation.assessment.status == "evaluation-error" {
                            report.errors.append("\(path): \(evaluation.assessment.status) (\(evaluation.parseState))")
                        }
                    }
                    guard try stat(file) == before else {
                        throw SQLiteIndexError(message: "File changed during evaluation; retry update: \(path)")
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as DatabaseError {
                    // Staging/schema failures are atomic database failures, not source diagnostics.
                    throw error
                } catch {
                    report.errors.append("\(path): \(error)")
                    let diagnostic = IndexDiagnostic(category: "evaluation", severity: "error", code: "index.read-or-evaluate",
                        location: path, message: String(describing: error))
                    let evaluation = IndexEvaluation(metadata: "{}", body: "", parseState: "error",
                        assessment: IndexAssessment(selected: false, status: "evaluation-error", diagnostics: [diagnostic]))
                    for scopeID in scopeIDs {
                        try database.stageChange(generation: generation, scopeID: scopeID,
                            file: IndexFileChange(path: path, mtime: mtime, size: size, hash: hash, evaluation: evaluation))
                    }
                }
            }
            after = paths.last
        }
        try Task.checkCancellation()
        try database.commitStagedRefresh(scopes: scopes, errors: scopeErrors,
            fingerprint: fingerprint, generation: generation)
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

    private func enumerate(_ scope: IndexScope, visitFile: (URL) throws -> Void) throws {
        let directory = root.appendingPathComponent(scope.path, isDirectory: true)
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == root.path || canonical.path.hasPrefix(root.path + "/") else {
            throw SQLiteIndexError(message: "Scope escapes project root: \(scope.path)")
        }
        // Throwing traversal is deliberate: Foundation's default enumerator can silently skip errors.
        func visit(_ directory: URL) throws {
            let entries = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                .sorted { $0.path < $1.path }
            for file in entries {
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                // Do not follow symlinks into other scopes or cycles.
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true { try visit(file) }
                else if values.isRegularFile == true,
                    scope.includeNonMarkdown || ["md", "markdown"].contains(file.pathExtension.lowercased()) {
                    try visitFile(file)
                }
            }
        }
        try visit(directory)
    }
}
