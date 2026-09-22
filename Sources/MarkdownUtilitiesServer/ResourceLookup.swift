import Foundation
import MarkdownUtilitiesCore

/// Named lookup configuration. Lookup availability does not imply uniqueness or edit protection.
public struct MarkdownResourceLookup: Codable, Equatable, Sendable {
  public enum Source: String, Codable, Sendable { case frontmatter, filename, logicalPath, persistentIdentity }
  public enum Format: String, Codable, Sendable { case string, integer, uuid, slug }
  public let name: String
  public let source: Source
  public let path: [String]?
  public let format: Format?
  public let slugPolicy: MarkdownSlugPolicy?
  public let protectedIdentifier: Bool

  public init(name: String, source: Source, path: [String]? = nil, format: Format? = nil,
    slugPolicy: MarkdownSlugPolicy? = nil, protectedIdentifier: Bool = false,
  ) {
    self.name = name; self.source = source; self.path = path; self.format = format
    self.slugPolicy = slugPolicy; self.protectedIdentifier = protectedIdentifier
  }

  public init(from decoder: Decoder) throws {
    try rejectUnknownLookupKeys(decoder, allowed: ["name", "source", "path", "format", "slugPolicy", "protectedIdentifier"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(name: c.decode(String.self, forKey: .name), source: c.decode(Source.self, forKey: .source),
      path: c.decodeIfPresent([String].self, forKey: .path), format: c.decodeIfPresent(Format.self, forKey: .format),
      slugPolicy: c.decodeIfPresent(MarkdownSlugPolicy.self, forKey: .slugPolicy),
      protectedIdentifier: c.decodeIfPresent(Bool.self, forKey: .protectedIdentifier) ?? false,
    )
  }

  package func policy(persistentIdentity: MarkdownPersistentIdentity?) -> MarkdownRecordIdentityPolicy? {
    let identitySource: MarkdownRecordIdentitySource
    switch source {
    case .filename: identitySource = .filename
    case .logicalPath: identitySource = .logicalPath
    case .persistentIdentity:
      guard let persistentIdentity else { return nil }
      identitySource = .frontmatter(path: persistentIdentity.path, format: .uuid)
    case .frontmatter:
      guard let path, let format else { return nil }
      let identityFormat: MarkdownRecordIdentityFormat
      switch format {
      case .string: identityFormat = .string
      case .integer: identityFormat = .integer
      case .uuid: identityFormat = .uuid
      case .slug:
        guard let slugPolicy else { return nil }
        identityFormat = .slug(slugPolicy)
      }
      identitySource = .frontmatter(path: path, format: identityFormat)
    }
    return MarkdownRecordIdentityPolicy(source: identitySource, logicalPathFallbackEnabled: false)
  }

  package func queryValue(_ value: String) -> String {
    if source == .persistentIdentity || format == .uuid {
      return UUID(uuidString: value)?.uuidString.lowercased() ?? value
    }
    return value
  }
}

/// One optional server-wide UUID field; existing documents need not contain it.
public struct MarkdownPersistentIdentity: Codable, Equatable, Sendable {
  public let path: [String]
  public init(path: [String]) { self.path = path }
  public init(from decoder: Decoder) throws {
    try rejectUnknownLookupKeys(decoder, allowed: ["path"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    path = try c.decode([String].self, forKey: .path)
  }
}

public struct MarkdownLookupConstraint: Codable, Equatable, Sendable {
  public enum Scope: String, Codable, Sendable { case resource, server }
  public let lookup: String
  public let uniqueWithin: Scope?
  public let requireValue: Bool
  public init(lookup: String, uniqueWithin: Scope? = nil, requireValue: Bool = false) {
    self.lookup = lookup; self.uniqueWithin = uniqueWithin; self.requireValue = requireValue
  }
  public init(from decoder: Decoder) throws {
    try rejectUnknownLookupKeys(decoder, allowed: ["lookup", "uniqueWithin", "requireValue"])
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(lookup: c.decode(String.self, forKey: .lookup),
      uniqueWithin: c.decodeIfPresent(Scope.self, forKey: .uniqueWithin),
      requireValue: c.decodeIfPresent(Bool.self, forKey: .requireValue) ?? false,
    )
  }
}

private struct LookupCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}

func rejectUnknownLookupKeys(_ decoder: Decoder, allowed: Set<String>) throws {
  let container = try decoder.container(keyedBy: LookupCodingKey.self)
  let unknown = Set(container.allKeys.map(\.stringValue)).subtracting(allowed)
  if !unknown.isEmpty {
    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
      debugDescription: "Unknown configuration fields: \(unknown.sorted().joined(separator: ", "))"))
  }
}

/// Derived evidence for mutation planning; does not itself authorize persistence.
public struct MarkdownLookupEvidence: Codable, Equatable, Sendable {
  public let lookup: String
  public let value: String?
  public let status: MarkdownRecordIdentityStatus
  public let protectedIdentifier: Bool
  public let uniqueWithin: MarkdownLookupConstraint.Scope?
  public let requireValue: Bool
  public let diagnostics: [MarkdownRecordIdentityDiagnostic]

  /// Ambiguity alone is not a required uniqueness constraint.
  public var violatesConstraint: Bool {
    status == .invalid || (requireValue && status == .missing) || (uniqueWithin != nil && status == .duplicate)
  }

  package func checking(count: Int) -> Self {
    let duplicate = value != nil && count > 1
    let code = duplicate ? "identity.lookup.duplicate" : "identity.lookup.missing"
    var problems = diagnostics
    // Missing optional values are ordinary absence, not a contract violation.
    if status == .missing && !requireValue { problems = [] }
    if duplicate {
      problems.append(MarkdownRecordIdentityDiagnostic(code: .duplicatePrimaryIdentity,
        location: "lookups.\(lookup)", message: "Lookup \(lookup) has \(count) matching documents (\(code)).",
        identity: value.map { MarkdownRecordIdentity(rawValue: $0) },
      ))
    }
    return Self(lookup: lookup, value: value, status: duplicate ? .duplicate : status,
      protectedIdentifier: protectedIdentifier, uniqueWithin: uniqueWithin, requireValue: requireValue,
      diagnostics: problems,
    )
  }
}

extension PlannedMarkdownResource {
  package func assessmentLookups(persistentIdentity: MarkdownPersistentIdentity?) -> [MarkdownResourceLookup] {
    guard persistentIdentity != nil else { return lookups }
    return lookups + [MarkdownResourceLookup(name: "$uuid", source: .persistentIdentity)]
  }
  public func constraint(for lookup: MarkdownResourceLookup) -> MarkdownLookupConstraint {
    if lookup.source == .persistentIdentity {
      return MarkdownLookupConstraint(lookup: lookup.name, uniqueWithin: .server)
    }
    return constraints.first { $0.lookup == lookup.name } ?? MarkdownLookupConstraint(lookup: lookup.name)
  }

  /// Identity fields to protect across aliases when this resource selects a document.
  public func protectedIdentityFields(persistentIdentity: MarkdownPersistentIdentity?) -> Set<String> {
    var fields = Set<String>()
    if case .frontmatter(let path, _) = identityPolicy.source, let field = path.first { fields.insert(field) }
    if let field = persistentIdentity?.path.first { fields.insert(field) }
    for lookup in lookups where lookup.protectedIdentifier {
      if let field = lookup.path?.first { fields.insert(field) }
    }
    return fields
  }

  package func lookupEvidence(analyzed: AnalyzedMarkdownRecord,
    persistentIdentity: MarkdownPersistentIdentity?,
  ) -> [MarkdownLookupEvidence] {
    assessmentLookups(persistentIdentity: persistentIdentity).compactMap { lookup in
      guard let policy = lookup.policy(persistentIdentity: persistentIdentity) else { return nil }
      let assessment = MarkdownRecordIdentityIndex.assess(analyzed, policy: policy)
      let constraint = constraint(for: lookup)
      return MarkdownLookupEvidence(lookup: lookup.name, value: assessment.primaryIdentity?.rawValue,
        status: assessment.status,
        protectedIdentifier: lookup.source == .persistentIdentity || lookup.protectedIdentifier
          || lookup.path?.first.map({ protectedIdentityFields(persistentIdentity: persistentIdentity).contains($0) }) == true,
        uniqueWithin: constraint.uniqueWithin, requireValue: constraint.requireValue,
        diagnostics: assessment.diagnostics,
      )
    }
  }
}

extension GenericMarkdownRecord {
  package func addingLookupEvidence(_ evidence: [MarkdownLookupEvidence]) -> Self {
    var diagnostics = self.diagnostics
    for item in evidence where item.violatesConstraint {
      for problem in item.diagnostics {
        let diagnostic = MarkdownServerRecordDiagnostic(code: "identity.lookup.\(item.status.rawValue)",
          severity: .error, source: .identity, location: "lookups.\(item.lookup)",
          message: problem.message, identity: problem.identity,
        )
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
      }
    }
    return Self(canonicalIdentity: canonicalIdentity, identityStatus: identityStatus,
      logicalPath: logicalPath, revision: revision, memberships: memberships, valid: valid,
      frontmatter: frontmatter, body: body, diagnostics: diagnostics,
    )
  }
}
