import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import PathKit

/// A per-file result keeps lexical repairs separate from whole-type assessment.
public struct WikilinkContractConversionResult: Sendable {
  public let plan: WikilinkContractPlan
  public let assessment: MarkdownTypeAssessment
  public let blockers: [String]
  public let applied: Bool
}

/// Uses authoritative bounded snapshots and the existing conformance-preserving
/// Fix-It transition evaluator. Preview never refreshes or creates an index.
public enum WikilinkContractConversionSession {
  public static func run(file: Path, root: Path, type: String,
    preferences: WikilinkContractPreferences = .init(), apply: Bool = false,
  ) async throws -> WikilinkContractConversionResult {
    try await execute(file: file, root: root, type: type, preferences: preferences, apply: apply)
  }

  /// The checkpoint permits deterministic tests of external edits at the write boundary.
  package static func execute(file: Path, root: Path, type: String,
    preferences: WikilinkContractPreferences = .init(), apply: Bool = false,
    beforeVerification: (@Sendable () throws -> Void)? = nil,
  ) async throws -> WikilinkContractConversionResult {
    let rootURL = URL(fileURLWithPath: root.absolute().string).standardizedFileURL
    let sourceURL = URL(fileURLWithPath: file.absolute().string).standardizedFileURL
    let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard sourceURL.path.hasPrefix(prefix), sourceURL.resolvingSymlinksInPath() == sourceURL,
      rootURL.resolvingSymlinksInPath() == rootURL else { throw IndexProjectError("Input must be inside --root without symlink ancestors") }
    let relative = String(sourceURL.path.dropFirst(prefix.count))
    let lease = apply ? try await CollectionWriterLease.acquire(root: rootURL) : nil
    defer { withExtendedLifetime(lease) {} }
    let config = root + ".md-utils/md-utils.json"
    let evaluator = try IndexProjectEvaluator(root: root, configPath: config)
    guard evaluator.types.definition(named: type) != nil else { throw IndexProjectError("Unknown type: \(type)") }
    let collection = try await MarkdownRelationshipNativeCollection.readOnly(root: rootURL)
    guard let source = collection.records[relative] else { throw IndexProjectError("Selected source is unavailable: \(relative)") }
    guard source.content.utf8.count <= 8 * 1024 * 1024 else { throw IndexProjectError("Conversion source exceeds the shared 8 MiB mutation limit") }
    var plan = try await WikilinkContractConversion.plan(record: source, type: type, registry: evaluator.types,
      resolver: collection.resolver, preferences: preferences)
    guard plan.proposed.content.utf8.count <= 8 * 1024 * 1024 else { throw IndexProjectError("Conversion output exceeds the shared 8 MiB mutation limit") }
    var blockers: [String] = []
    if plan.hasChanges {
      let rules = try evaluator.rules ?? MarkdownRuleCompiler(typeRegistry: evaluator.types).compile([])
      let overlay = MarkdownRelationshipFixPlanner.replacing([relative: plan.proposed], in: collection)
      blockers = try await MarkdownRelationshipFixPlanner(registry: rules).assessTransition(from: collection, to: overlay).blockers
      let reassessed = try await WikilinkContractConversion.plan(record: plan.proposed, type: type, registry: evaluator.types,
        resolver: collection.resolver, preferences: preferences)
      for change in plan.changes where change.replacement != nil {
        guard let after = reassessed.changes.first(where: { $0.path == change.path }), after.status == "unchanged",
          after.declarations == change.declarations else {
          blockers.append("Combined edits changed schema applicability or left a requested lexical repair unresolved")
          continue
        }
      }
      if !blockers.isEmpty { plan.reject(blockers.joined(separator: "; ")) }
    }
    let proposedCollection = MarkdownRelationshipFixPlanner.replacing([relative: plan.proposed], in: collection)
    let assessment = try await MarkdownTypeChecker(registry: evaluator.types).assess(plan.proposed, as: type, collection: proposedCollection)
    if apply && plan.hasChanges {
      try Task.checkCancellation()
      try beforeVerification?()
      let current = try IndexProjectEvaluator(root: root, configPath: config)
      guard current.fingerprint == evaluator.fingerprint else { throw IndexProjectError("Definitions changed during conversion; preview again") }
      try MarkdownRelationshipNativeCollection.verifyCurrent(collection, indexedOnly: false, limits: .init())
      try FrontMatterFileWriter.write(plan.proposed.content, to: file, expectedSource: source.content)
    }
    return .init(plan: plan, assessment: assessment, blockers: blockers, applied: apply && plan.hasChanges)
  }
}
