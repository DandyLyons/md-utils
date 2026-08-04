import Foundation

/// Controls validation of a frontmatter value used as a slug identity.
public enum MarkdownSlugPolicy: String, Codable, Equatable, Sendable {
  /// Lowercase ASCII letters and digits separated by single hyphens.
  case strictASCII
  /// Lowercase Unicode letters and digits separated by non-adjacent hyphens or underscores.
  case unicode
  /// ASCII letters and digits separated by single hyphens, preserving authored case.
  case preserve
}

/// A supported frontmatter representation for a record identity.
public enum MarkdownRecordIdentityFormat: Codable, Equatable, Sendable {
  case string
  case integer
  case uuid
  case slug(MarkdownSlugPolicy)
}

/// Selects the source of a record's primary identity.
public enum MarkdownRecordIdentitySource: Codable, Equatable, Sendable {
  case existingIdentity
  case logicalPath
  case frontmatter(path: [String], format: MarkdownRecordIdentityFormat)
}

/// Portable policy used to assess primary and fallback record identity.
public struct MarkdownRecordIdentityPolicy: Codable, Equatable, Sendable {
  public let source: MarkdownRecordIdentitySource
  public let logicalPathFallbackEnabled: Bool

  public init(
    source: MarkdownRecordIdentitySource,
    logicalPathFallbackEnabled: Bool = true
  ) {
    self.source = source
    self.logicalPathFallbackEnabled = logicalPathFallbackEnabled
  }
}

/// Collection-wide status of a record's configured primary identity.
public enum MarkdownRecordIdentityStatus: String, Codable, Equatable, Sendable {
  case available
  case missing
  case invalid
  case duplicate
}

/// Stable categories produced while assessing record identity.
public enum MarkdownRecordIdentityDiagnosticCode: String, Codable, Equatable, Sendable {
  case missingExistingIdentity = "identity.existing.missing"
  case missingLogicalPath = "identity.logical-path.missing"
  case invalidFrontmatterPath = "identity.frontmatter.invalid-path"
  case missingFrontmatterValue = "identity.frontmatter.missing"
  case invalidFrontmatter = "identity.frontmatter.invalid"
  case unsupportedFrontmatterValue = "identity.frontmatter.unsupported-value"
  case invalidInteger = "identity.frontmatter.invalid-integer"
  case invalidUUID = "identity.frontmatter.invalid-uuid"
  case invalidSlug = "identity.frontmatter.invalid-slug"
  case duplicatePrimaryIdentity = "identity.primary.duplicate"
  case duplicateLogicalPath = "identity.logical-path.duplicate"
}

/// A structured problem found while deriving or indexing record identity.
public struct MarkdownRecordIdentityDiagnostic: Codable, Equatable, Sendable {
  public let code: MarkdownRecordIdentityDiagnosticCode
  public let location: String
  public let message: String
  public let identity: MarkdownRecordIdentity?
  public let paths: [MarkdownRecordPath]

  public init(
    code: MarkdownRecordIdentityDiagnosticCode,
    location: String,
    message: String,
    identity: MarkdownRecordIdentity? = nil,
    paths: [MarkdownRecordPath] = []
  ) {
    self.code = code
    self.location = location
    self.message = message
    self.identity = identity
    self.paths = paths
  }
}

/// The identity result for one canonical Markdown record.
public struct MarkdownRecordIdentityAssessment: Codable, Equatable, Sendable {
  public let record: MarkdownRecord
  public let primaryIdentity: MarkdownRecordIdentity?
  public let status: MarkdownRecordIdentityStatus
  public let logicalPathFallback: MarkdownRecordPath?
  public let diagnostics: [MarkdownRecordIdentityDiagnostic]

  public init(
    record: MarkdownRecord,
    primaryIdentity: MarkdownRecordIdentity?,
    status: MarkdownRecordIdentityStatus,
    logicalPathFallback: MarkdownRecordPath?,
    diagnostics: [MarkdownRecordIdentityDiagnostic]
  ) {
    self.record = record
    self.primaryIdentity = primaryIdentity
    self.status = status
    self.logicalPathFallback = logicalPathFallback
    self.diagnostics = diagnostics
  }
}

/// One record returned by an identity lookup, including its fallback when enabled.
public struct MarkdownRecordIdentityCandidate: Codable, Equatable, Sendable {
  public let record: MarkdownRecord
  public let primaryIdentity: MarkdownRecordIdentity?
  public let logicalPathFallback: MarkdownRecordPath?

  public init(
    record: MarkdownRecord,
    primaryIdentity: MarkdownRecordIdentity?,
    logicalPathFallback: MarkdownRecordPath?
  ) {
    self.record = record
    self.primaryIdentity = primaryIdentity
    self.logicalPathFallback = logicalPathFallback
  }
}

/// The namespace and value that produced an ambiguous lookup.
public enum MarkdownRecordIdentityLookupKey: Codable, Equatable, Sendable {
  case primary(MarkdownRecordIdentity)
  case logicalPath(MarkdownRecordPath)
}

/// Every candidate associated with an ambiguous identity lookup.
public struct MarkdownRecordIdentityConflict: Codable, Equatable, Sendable {
  public let key: MarkdownRecordIdentityLookupKey
  public let candidates: [MarkdownRecordIdentityCandidate]

  public init(
    key: MarkdownRecordIdentityLookupKey,
    candidates: [MarkdownRecordIdentityCandidate]
  ) {
    self.key = key
    self.candidates = candidates
  }
}

/// Collision-safe result returned by primary-ID and logical-path lookups.
public enum MarkdownRecordIdentityLookupResult: Codable, Equatable, Sendable {
  case notFound
  case record(MarkdownRecordIdentityCandidate)
  case conflict(MarkdownRecordIdentityConflict)
}

/// Immutable collection-wide identity assessments and lookup indexes.
public struct MarkdownRecordIdentityIndex: Equatable, Sendable {
  public let policy: MarkdownRecordIdentityPolicy
  public let assessments: [MarkdownRecordIdentityAssessment]
  public let collisionDiagnostics: [MarkdownRecordIdentityDiagnostic]

  private let primaryLookup: [MarkdownRecordIdentity: [Int]]
  private let logicalPathLookup: [MarkdownRecordPath: [Int]]

  /// Builds an index by assessing each record once and retaining every collision candidate.
  public static func build(
    records: [MarkdownRecord],
    policy: MarkdownRecordIdentityPolicy
  ) async -> MarkdownRecordIdentityIndex {
    var analyzedRecords: [AnalyzedMarkdownRecord] = []
    analyzedRecords.reserveCapacity(records.count)
    for record in records {
      analyzedRecords.append(await MarkdownRecordAnalyzer.analyze(record))
    }
    return await build(analyzedRecords: analyzedRecords, policy: policy)
  }

  /// Builds an identity index from analysis shared with sibling package targets.
  package static func build(
    analyzedRecords: [AnalyzedMarkdownRecord],
    policy: MarkdownRecordIdentityPolicy
  ) async -> MarkdownRecordIdentityIndex {
    var assessments: [MarkdownRecordIdentityAssessment] = []
    assessments.reserveCapacity(analyzedRecords.count)
    for analyzedRecord in analyzedRecords {
      let record = analyzedRecord.record
      var assessment = assess(analyzedRecord, policy: policy)
      if policy.logicalPathFallbackEnabled,
        record.context.path == nil,
        assessment.diagnostics.contains(where: { $0.code == .missingLogicalPath }) == false
      {
        assessment = replacing(
          assessment,
          appending: MarkdownRecordIdentityDiagnostic(
            code: .missingLogicalPath,
            location: "context.path",
            message: "The record has no logical path for fallback lookup"
          )
        )
      }
      assessments.append(assessment)
    }

    let primaryGroups = groupPrimaryIdentities(in: assessments)
    var collisionDiagnostics: [MarkdownRecordIdentityDiagnostic] = []
    for identity in primaryGroups.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let indexes = primaryGroups[identity], indexes.count > 1 else { continue }
      let paths = sortedPaths(indexes.compactMap { assessments[$0].record.context.path })
      let diagnostic = MarkdownRecordIdentityDiagnostic(
        code: .duplicatePrimaryIdentity,
        location: "identity.primary",
        message: "Primary identity \"\(identity.rawValue)\" is used by \(indexes.count) records",
        identity: identity,
        paths: paths
      )
      collisionDiagnostics.append(diagnostic)
      for index in indexes {
        assessments[index] = replacing(
          assessments[index],
          status: .duplicate,
          appending: diagnostic
        )
      }
    }

    let allLogicalPathGroups = groupLogicalPaths(in: assessments)
    for path in allLogicalPathGroups.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let indexes = allLogicalPathGroups[path], indexes.count > 1 else { continue }
      let diagnostic = MarkdownRecordIdentityDiagnostic(
        code: .duplicateLogicalPath,
        location: "context.path",
        message: "Logical path \"\(path.rawValue)\" is used by \(indexes.count) records",
        paths: [path]
      )
      collisionDiagnostics.append(diagnostic)
      for index in indexes {
        assessments[index] = replacing(assessments[index], appending: diagnostic)
      }
    }

    let fallbackLookup = policy.logicalPathFallbackEnabled ? allLogicalPathGroups : [:]
    return MarkdownRecordIdentityIndex(
      policy: policy,
      assessments: assessments,
      collisionDiagnostics: collisionDiagnostics,
      primaryLookup: primaryGroups,
      logicalPathLookup: fallbackLookup
    )
  }

  /// Looks up a configured primary identity without choosing an arbitrary collision candidate.
  public func lookup(primary identity: MarkdownRecordIdentity) -> MarkdownRecordIdentityLookupResult {
    result(for: primaryLookup[identity] ?? [], key: .primary(identity))
  }

  /// Looks up an enabled logical-path fallback without choosing an arbitrary collision candidate.
  public func lookup(logicalPath path: MarkdownRecordPath) -> MarkdownRecordIdentityLookupResult {
    result(for: logicalPathLookup[path] ?? [], key: .logicalPath(path))
  }

  private init(
    policy: MarkdownRecordIdentityPolicy,
    assessments: [MarkdownRecordIdentityAssessment],
    collisionDiagnostics: [MarkdownRecordIdentityDiagnostic],
    primaryLookup: [MarkdownRecordIdentity: [Int]],
    logicalPathLookup: [MarkdownRecordPath: [Int]]
  ) {
    self.policy = policy
    self.assessments = assessments
    self.collisionDiagnostics = collisionDiagnostics
    self.primaryLookup = primaryLookup
    self.logicalPathLookup = logicalPathLookup
  }

  private func result(
    for indexes: [Int],
    key: MarkdownRecordIdentityLookupKey
  ) -> MarkdownRecordIdentityLookupResult {
    let candidates = indexes.map { candidate(for: assessments[$0]) }
    if candidates.isEmpty {
      return .notFound
    }
    if candidates.count == 1, let candidate = candidates.first {
      return .record(candidate)
    }
    return .conflict(MarkdownRecordIdentityConflict(key: key, candidates: candidates))
  }

  private func candidate(
    for assessment: MarkdownRecordIdentityAssessment
  ) -> MarkdownRecordIdentityCandidate {
    MarkdownRecordIdentityCandidate(
      record: assessment.record,
      primaryIdentity: assessment.primaryIdentity,
      logicalPathFallback: assessment.logicalPathFallback
    )
  }

  private static func assess(
    _ analyzed: AnalyzedMarkdownRecord,
    policy: MarkdownRecordIdentityPolicy
  ) -> MarkdownRecordIdentityAssessment {
    let record = analyzed.record
    let fallback = policy.logicalPathFallbackEnabled ? record.context.path : nil
    switch policy.source {
    case .existingIdentity:
      guard let identity = record.identity else {
        return missingAssessment(
          record: record,
          fallback: fallback,
          code: .missingExistingIdentity,
          location: "identity",
          message: "The record has no existing identity"
        )
      }
      return availableAssessment(record: record, identity: identity, fallback: fallback)

    case .logicalPath:
      guard let path = record.context.path else {
        return missingAssessment(
          record: record,
          fallback: fallback,
          code: .missingLogicalPath,
          location: "context.path",
          message: "The record has no logical path"
        )
      }
      return availableAssessment(
        record: record,
        identity: MarkdownRecordIdentity(rawValue: path.rawValue),
        fallback: fallback
      )

    case .frontmatter(let path, let format):
      guard path.isEmpty == false, path.allSatisfy({ $0.isEmpty == false }) else {
        return invalidAssessment(
          record: record,
          fallback: fallback,
          code: .invalidFrontmatterPath,
          location: "identity.policy.frontmatter.path",
          message: "A frontmatter identity path must contain only nonempty components"
        )
      }
      if let parseDiagnostic = analyzed.parseDiagnostics.first(where: { $0.domain == .frontmatter }) {
        return invalidAssessment(
          record: record,
          fallback: fallback,
          code: .invalidFrontmatter,
          location: path.joined(separator: "."),
          message: parseDiagnostic.message
        )
      }
      guard let value = value(at: path, in: analyzed.userFrontmatter) else {
        return missingAssessment(
          record: record,
          fallback: fallback,
          code: .missingFrontmatterValue,
          location: path.joined(separator: "."),
          message: "No identity value exists at frontmatter path \"\(path.joined(separator: "."))\""
        )
      }
      return formattedAssessment(
        record: record,
        fallback: fallback,
        value: value,
        path: path,
        format: format
      )
    }
  }

  private static func formattedAssessment(
    record: MarkdownRecord,
    fallback: MarkdownRecordPath?,
    value: JSONValue,
    path: [String],
    format: MarkdownRecordIdentityFormat
  ) -> MarkdownRecordIdentityAssessment {
    let location = path.joined(separator: ".")
    let rawIdentity: String
    switch format {
    case .string:
      guard case .string(let value) = value else {
        return unsupportedAssessment(record: record, fallback: fallback, location: location, value: value)
      }
      rawIdentity = value

    case .integer:
      guard case .integer(let value) = value else {
        let code: MarkdownRecordIdentityDiagnosticCode
        if case .number = value {
          code = .invalidInteger
        } else {
          code = .unsupportedFrontmatterValue
        }
        return invalidAssessment(
          record: record,
          fallback: fallback,
          code: code,
          location: location,
          message: "Identity value at \"\(location)\" must be a lossless integer"
        )
      }
      rawIdentity = String(value)

    case .uuid:
      guard case .string(let value) = value else {
        return unsupportedAssessment(record: record, fallback: fallback, location: location, value: value)
      }
      guard let uuid = UUID(uuidString: value) else {
        return invalidAssessment(
          record: record,
          fallback: fallback,
          code: .invalidUUID,
          location: location,
          message: "Identity value at \"\(location)\" is not a valid UUID"
        )
      }
      rawIdentity = uuid.uuidString.lowercased()

    case .slug(let policy):
      guard case .string(let value) = value else {
        return unsupportedAssessment(record: record, fallback: fallback, location: location, value: value)
      }
      guard isValidSlug(value, policy: policy) else {
        return invalidAssessment(
          record: record,
          fallback: fallback,
          code: .invalidSlug,
          location: location,
          message: "Identity value at \"\(location)\" is not a valid \(policy.rawValue) slug"
        )
      }
      rawIdentity = value
    }

    return availableAssessment(
      record: record,
      identity: MarkdownRecordIdentity(rawValue: rawIdentity),
      fallback: fallback
    )
  }

  private static func value(
    at path: [String],
    in frontmatter: [String: JSONValue]?
  ) -> JSONValue? {
    guard let frontmatter else { return nil }
    var current = JSONValue.object(frontmatter)
    for component in path {
      guard case .object(let object) = current, let next = object[component] else { return nil }
      current = next
    }
    guard current != .null else { return nil }
    return current
  }

  private static func isValidSlug(_ value: String, policy: MarkdownSlugPolicy) -> Bool {
    guard value.isEmpty == false else { return false }
    switch policy {
    case .strictASCII:
      return validSeparatedASCII(value, permitsUppercase: false)
    case .preserve:
      return validSeparatedASCII(value, permitsUppercase: true)
    case .unicode:
      guard value == value.lowercased() else { return false }
      var previousWasSeparator = false
      var foundAlphanumeric = false
      for character in value {
        let isSeparator = character == "-" || character == "_"
        if isSeparator {
          if previousWasSeparator || foundAlphanumeric == false { return false }
          previousWasSeparator = true
        } else {
          guard character.isLetter || character.isNumber else { return false }
          foundAlphanumeric = true
          previousWasSeparator = false
        }
      }
      return foundAlphanumeric && previousWasSeparator == false
    }
  }

  private static func validSeparatedASCII(_ value: String, permitsUppercase: Bool) -> Bool {
    var previousWasHyphen = false
    var foundAlphanumeric = false
    for scalar in value.unicodeScalars {
      let isLowercase = (97...122).contains(scalar.value)
      let isUppercase = permitsUppercase && (65...90).contains(scalar.value)
      let isDigit = (48...57).contains(scalar.value)
      if scalar == "-" {
        if previousWasHyphen || foundAlphanumeric == false { return false }
        previousWasHyphen = true
      } else {
        guard isLowercase || isUppercase || isDigit else { return false }
        foundAlphanumeric = true
        previousWasHyphen = false
      }
    }
    return foundAlphanumeric && previousWasHyphen == false
  }

  private static func unsupportedAssessment(
    record: MarkdownRecord,
    fallback: MarkdownRecordPath?,
    location: String,
    value: JSONValue
  ) -> MarkdownRecordIdentityAssessment {
    invalidAssessment(
      record: record,
      fallback: fallback,
      code: .unsupportedFrontmatterValue,
      location: location,
      message: "Identity value at \"\(location)\" has unsupported type \(typeName(of: value))"
    )
  }

  private static func typeName(of value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case .boolean: return "boolean"
    case .integer: return "integer"
    case .number: return "number"
    case .string: return "string"
    case .array: return "array"
    case .object: return "object"
    }
  }

  private static func availableAssessment(
    record: MarkdownRecord,
    identity: MarkdownRecordIdentity,
    fallback: MarkdownRecordPath?
  ) -> MarkdownRecordIdentityAssessment {
    MarkdownRecordIdentityAssessment(
      record: record,
      primaryIdentity: identity,
      status: .available,
      logicalPathFallback: fallback,
      diagnostics: []
    )
  }

  private static func missingAssessment(
    record: MarkdownRecord,
    fallback: MarkdownRecordPath?,
    code: MarkdownRecordIdentityDiagnosticCode,
    location: String,
    message: String
  ) -> MarkdownRecordIdentityAssessment {
    MarkdownRecordIdentityAssessment(
      record: record,
      primaryIdentity: nil,
      status: .missing,
      logicalPathFallback: fallback,
      diagnostics: [MarkdownRecordIdentityDiagnostic(code: code, location: location, message: message)]
    )
  }

  private static func invalidAssessment(
    record: MarkdownRecord,
    fallback: MarkdownRecordPath?,
    code: MarkdownRecordIdentityDiagnosticCode,
    location: String,
    message: String
  ) -> MarkdownRecordIdentityAssessment {
    MarkdownRecordIdentityAssessment(
      record: record,
      primaryIdentity: nil,
      status: .invalid,
      logicalPathFallback: fallback,
      diagnostics: [MarkdownRecordIdentityDiagnostic(code: code, location: location, message: message)]
    )
  }

  private static func replacing(
    _ assessment: MarkdownRecordIdentityAssessment,
    status: MarkdownRecordIdentityStatus? = nil,
    appending diagnostic: MarkdownRecordIdentityDiagnostic
  ) -> MarkdownRecordIdentityAssessment {
    MarkdownRecordIdentityAssessment(
      record: assessment.record,
      primaryIdentity: assessment.primaryIdentity,
      status: status ?? assessment.status,
      logicalPathFallback: assessment.logicalPathFallback,
      diagnostics: assessment.diagnostics + [diagnostic]
    )
  }

  private static func groupPrimaryIdentities(
    in assessments: [MarkdownRecordIdentityAssessment]
  ) -> [MarkdownRecordIdentity: [Int]] {
    var result: [MarkdownRecordIdentity: [Int]] = [:]
    for (index, assessment) in assessments.enumerated() {
      guard let identity = assessment.primaryIdentity else { continue }
      result[identity, default: []].append(index)
    }
    for key in result.keys {
      result[key]?.sort { candidateSortKey(assessments[$0]) < candidateSortKey(assessments[$1]) }
    }
    return result
  }

  private static func groupLogicalPaths(
    in assessments: [MarkdownRecordIdentityAssessment]
  ) -> [MarkdownRecordPath: [Int]] {
    var result: [MarkdownRecordPath: [Int]] = [:]
    for (index, assessment) in assessments.enumerated() {
      guard let path = assessment.record.context.path else { continue }
      result[path, default: []].append(index)
    }
    for key in result.keys {
      result[key]?.sort { candidateSortKey(assessments[$0]) < candidateSortKey(assessments[$1]) }
    }
    return result
  }

  private static func candidateSortKey(_ assessment: MarkdownRecordIdentityAssessment) -> String {
    let record = assessment.record
    return [
      record.context.path?.rawValue ?? "",
      record.identity?.rawValue ?? "",
      record.revision?.rawValue ?? "",
      record.content,
    ].joined(separator: "\u{0}")
  }

  private static func sortedPaths(_ paths: [MarkdownRecordPath]) -> [MarkdownRecordPath] {
    paths.sorted { $0.rawValue < $1.rawValue }
  }
}
