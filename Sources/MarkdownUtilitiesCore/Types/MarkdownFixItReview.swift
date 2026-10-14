import Foundation
import Parsing

/// Host-supplied evidence for a review. Fingerprints must describe content, not
/// transient index generations or modification times alone. Core performs no I/O.
public struct MarkdownFixItReviewEvidence: Codable, Equatable, Sendable {
  public let collection: String
  /// Includes all loaded definitions, their dependencies, and configuration.
  public let configuration: String
  /// Includes supporting records, not just the destinations of proposed edits.
  public let records: [String: MarkdownRecordRevision]
  /// Includes candidate paths and completeness, including negative resolution evidence.
  public let resolution: String
  /// Includes rule selection, membership, selected/reachable scope, and coverage.
  public let scope: String

  public init(
    collection: String,
    configuration: String,
    records: [String: MarkdownRecordRevision],
    resolution: String,
    scope: String,
  ) {
    self.collection = collection
    self.configuration = configuration
    self.records = records
    self.resolution = resolution
    self.scope = scope
  }
}

/// An existing shared fix-it addressed to one record, with its diagnostic origin.
/// A proposal is not permission to write and does not establish domain truth.
public struct MarkdownFixItProposal: Encodable, Sendable {
  public let path: MarkdownRecordPath
  public let fixIt: MarkdownFixIt
  public let diagnostic: MarkdownDiagnostic
  public let rule: String?
  /// Proposals in the same group are mutually exclusive, even across files.
  public let alternativeGroup: String?
  public let changes: [MarkdownFixItPropertyChange]

  public init(
    path: MarkdownRecordPath,
    fixIt: MarkdownFixIt,
    diagnostic: MarkdownDiagnostic,
    rule: String? = nil,
    alternativeGroup: String? = nil,
    changes: [MarkdownFixItPropertyChange] = [],
  ) {
    self.path = path
    self.fixIt = fixIt
    self.diagnostic = diagnostic
    self.rule = rule
    self.alternativeGroup = alternativeGroup
    self.changes = changes
  }
}

/// Exact decoded frontmatter values affected by a proposal; nil denotes absence.
public struct MarkdownFixItPropertyChange: Codable, Sendable {
  public let path: [WikilinkPropertyComponent]
  public let before: JSONValue?
  public let after: JSONValue?
  public init(path: [WikilinkPropertyComponent], before: JSONValue?, after: JSONValue?) {
    self.path = path; self.before = before; self.after = after
  }

  public var location: String {
    "/" + path.map {
      switch $0 {
      case .key(let key): key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
      case .index(let index): String(index)
      }
    }.joined(separator: "/")
  }
}

/// Immutable, numbered review data shared by type and rule fix workflows.
/// Hosts must rebuild evidence from authoritative sources before application,
/// compare review tokens, then use coordinated revision-checked persistence.
public struct MarkdownFixItReview: Encodable, Sendable {
  public let version = 1
  public let evidence: MarkdownFixItReviewEvidence
  /// The supplied order is the displayed numbering and is bound into the token.
  /// Producers must supply a deterministic order; selection never renumbers it.
  public let proposals: [MarkdownFixItProposal]

  public init(evidence: MarkdownFixItReviewEvidence, proposals: [MarkdownFixItProposal]) throws {
    guard proposals.count <= 10_000, evidence.records.count <= 10_000 else {
      throw MarkdownFixItReviewError.limitExceeded
    }
    guard [evidence.collection, evidence.configuration, evidence.resolution, evidence.scope]
      .allSatisfy({ $0.isEmpty == false }) else { throw MarkdownFixItReviewError.incompleteEvidence }
    for (path, revision) in evidence.records {
      _ = try MarkdownRecordPath(path)
      guard revision.rawValue.isEmpty == false else { throw MarkdownFixItReviewError.missingRevision(path) }
    }
    var editCount = 0
    for proposal in proposals {
      editCount += proposal.fixIt.edits.count
      guard editCount <= 100_000 else { throw MarkdownFixItReviewError.limitExceeded }
      guard let revision = evidence.records[proposal.path.rawValue], revision.rawValue.isEmpty == false else {
        throw MarkdownFixItReviewError.missingRevision(proposal.path.rawValue)
      }
      for edit in proposal.fixIt.edits {
        switch edit {
        case .setFrontmatterValue(let path, _), .requestFrontmatterValue(let path):
          guard path.isEmpty == false else { throw MarkdownTypeFixerError.emptyPath }
          guard path.count <= 128 else { throw MarkdownFixItReviewError.limitExceeded }
        case .setFrontmatterOccurrence(let path, _), .removeFrontmatterOccurrence(let path):
          guard !path.isEmpty else { throw MarkdownTypeFixerError.emptyPath }
          guard path.count <= 128 else { throw MarkdownFixItReviewError.limitExceeded }
        case .ensureFrontmatter, .appendHeading:
          break
        }
      }
    }
    self.evidence = evidence
    self.proposals = proposals
  }

  /// Canonical bytes for native cryptographic review tokens. This does not save a
  /// review or certify that the host supplied complete evidence.
  public func canonicalData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(self)
    guard data.count <= 64 * 1_024 * 1_024 else { throw MarkdownFixItReviewError.limitExceeded }
    return data
  }

  /// Resolve explicit choices plus optional automatic choices without granting
  /// write permission. Known-value input-required fixes still need a number.
  public func select(
    numbers: [Int] = [],
    automatic: Bool = false,
    includeRecommendations: Bool = false,
  ) throws -> [Int] {
    var selected = Set(numbers)
    for number in selected.sorted() {
      guard number > 0, number <= proposals.count else {
        throw MarkdownFixItReviewError.unknownSelection(number)
      }
      let proposal = proposals[number - 1]
      guard includeRecommendations || proposal.diagnostic.severity != .advisory else {
        throw MarkdownFixItReviewError.recommendationRequiresOptIn(number)
      }
      guard proposal.fixIt.safety != .advisoryOnly, proposal.fixIt.edits.isEmpty == false else {
        throw MarkdownFixItReviewError.explanatoryOnly(number)
      }
    }
    if automatic {
      for (index, proposal) in proposals.enumerated() {
        guard proposal.fixIt.safety == .automatic, proposal.fixIt.edits.isEmpty == false,
          includeRecommendations || proposal.diagnostic.severity != .advisory else { continue }
        // An automatic label must never implicitly accept a request for input.
        guard proposal.fixIt.edits.contains(where: {
          if case .requestFrontmatterValue = $0 { return true }
          return false
        }) == false else { continue }
        selected.insert(index + 1)
      }
    }
    let result = selected.sorted()
    try checkConflicts(result)
    return result
  }

  /// Parse repeated --select arguments with the project's shared parser library.
  /// Empty items, signs, zero, overflow, ranges, and trailing text are errors.
  public static func parseSelections(_ arguments: [String]) throws -> [Int] {
    guard arguments.count <= 10_000 else { throw MarkdownFixItReviewError.limitExceeded }
    let number = Parsing.Prefix<Substring>(1...) { character in
      character >= "0" && character <= "9"
    }
    let parser = Parse {
      Many(1...) { number } separator: { "," }
      End()
    }
    var result = Set<Int>()
    for argument in arguments {
      guard argument.utf8.count <= 64 * 1_024,
        let items = try? parser.parse(argument[...]) else {
        throw MarkdownFixItReviewError.invalidSelection(argument)
      }
      for item in items {
        guard let value = Int(item), value > 0 else {
          throw MarkdownFixItReviewError.invalidSelection(argument)
        }
        result.insert(value)
        guard result.count <= 10_000 else { throw MarkdownFixItReviewError.limitExceeded }
      }
    }
    return result.sorted()
  }

  private func checkConflicts(_ numbers: [Int]) throws {
    var alternatives: [String: Int] = [:]
    var writes: [String: [[WikilinkPropertyComponent]: Int]] = [:]
    var descendants: [String: [[WikilinkPropertyComponent]: Int]] = [:]
    for number in numbers {
      let proposal = proposals[number - 1]
      if let group = proposal.alternativeGroup {
        if let previous = alternatives[group] {
          throw MarkdownFixItReviewError.conflictingSelections(previous, number)
        }
        alternatives[group] = number
      }
      for edit in proposal.fixIt.edits {
        let path: [WikilinkPropertyComponent]
        switch edit {
        case .setFrontmatterValue(let location, _), .requestFrontmatterValue(let location):
          path = location.map(WikilinkPropertyComponent.key)
        case .setFrontmatterOccurrence(let location, _), .removeFrontmatterOccurrence(let location):
          path = location
        case .ensureFrontmatter, .appendHeading:
          continue
        }
        // Treat same-property and ancestor/descendant edits as conflicts, even
        // with equal values. Prefix lookup avoids comparing every pair of edits.
        for length in 1...path.count {
          if let previousNumber = writes[proposal.path.rawValue]?[Array(path.prefix(length))] {
            throw MarkdownFixItReviewError.conflictingSelections(previousNumber, number)
          }
        }
        if let previousNumber = descendants[proposal.path.rawValue]?[path] {
          throw MarkdownFixItReviewError.conflictingSelections(previousNumber, number)
        }
        writes[proposal.path.rawValue, default: [:]][path] = number
        for length in 1..<path.count {
          descendants[proposal.path.rawValue, default: [:]][Array(path.prefix(length))] = number
        }
      }
    }
  }
}

public enum MarkdownFixItReviewError: Error, Equatable, LocalizedError {
  case limitExceeded
  case incompleteEvidence
  case missingRevision(String)
  case invalidSelection(String)
  case unknownSelection(Int)
  case recommendationRequiresOptIn(Int)
  case explanatoryOnly(Int)
  case conflictingSelections(Int, Int)
  case staleReview

  public var errorDescription: String? {
    switch self {
    case .limitExceeded: "Fix-it review exceeds its evidence or selection limit."
    case .incompleteEvidence: "Fix-it review requires collection, configuration, resolution, and scope evidence."
    case .missingRevision(let path): "No baseline revision is available for \(path)."
    case .invalidSelection(let value): "Invalid fix selection '\(value)'; use positive numbers separated by commas."
    case .unknownSelection(let number): "Fix \(number) is not present in this review."
    case .recommendationRequiresOptIn(let number): "Fix \(number) requires --include-recommendations."
    case .explanatoryOnly(let number): "Fix \(number) is explanatory and cannot be applied."
    case .conflictingSelections(let first, let second): "Fixes \(first) and \(second) conflict; review and select an alternative."
    case .staleReview: "The reviewed proposals or supporting evidence changed; preview again before applying."
    }
  }
}
