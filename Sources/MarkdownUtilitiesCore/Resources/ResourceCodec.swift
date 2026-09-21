import Foundation
import Parsing
import Yams

/// Administrator-owned creation template. Clients supply data, never template source.
public struct ResourceCreationTemplate: Codable, Equatable, Sendable {
  public let template: String
  public let inputSchema: JSONValue?

  public init(template: String, inputSchema: JSONValue? = nil) {
    self.template = template
    self.inputSchema = inputSchema
  }
}

/// Explicit codec declaration; absence means a resource has no writable contract.
public struct WritableResourceConfiguration: Codable, Equatable, Sendable {
  public let codec: ResourceCodecConfiguration
  /// Omission disables creation while allowing edit planning.
  public let creation: ResourceCreationTemplate?

  public init(codec: ResourceCodecConfiguration, creation: ResourceCreationTemplate? = nil) {
    self.codec = codec
    self.creation = creation
  }
}

/// Explicit writable projection, independent of the read representation.
public struct ResourceCodecConfiguration: Codable, Equatable, Sendable {
  public let frontmatterFields: [String]
  public let bodyWritable: Bool
  /// Additional top-level fields protected by the host (including identity fields).
  public let protectedFields: [String]

  public init(frontmatterFields: [String], bodyWritable: Bool, protectedFields: [String] = []) {
    self.frontmatterFields = frontmatterFields
    self.bodyWritable = bodyWritable
    self.protectedFields = protectedFields
  }

  public func validate() throws {
    guard Set(frontmatterFields).count == frontmatterFields.count,
          frontmatterFields.allSatisfy({ !$0.isEmpty && $0 != "$md-utils" }),
          Set(frontmatterFields).isDisjoint(with: protectedFields) else {
      throw ResourceCodecError("configuration", "Writable fields must be unique, nonempty, and unprotected.")
    }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(frontmatterFields: try values.decode([String].self, forKey: .frontmatterFields),
      bodyWritable: try values.decode(Bool.self, forKey: .bodyWritable),
      protectedFields: try values.decodeIfPresent([String].self, forKey: .protectedFields) ?? [])
    try validate()
  }
}

/// Explicit deletion is distinct from storing JSON null.
public enum ResourceFieldPatch: Equatable, Sendable {
  case set(JSONValue)
  case remove
}

/// Transport-neutral mutation inputs; body omission in a patch means unchanged.
public enum ResourceEdit: Equatable, Sendable {
  case replace(frontmatter: [String: JSONValue], body: String?)
  case patch(frontmatter: [String: ResourceFieldPatch], body: String?)
}

/// Complete authoritative source fetched by a host with its canonical revision.
///
/// The host must perform bounded authoritative reads, never reconstruct this from
/// metadata or FTS caches. The revision is opaque: native SHA-256, not an ETag or
/// publication generation. Persistence must compare it again atomically.
public struct ResourceMutationSource: Equatable, Sendable {
  public let record: MarkdownRecord
  public let expectedRevision: MarkdownRecordRevision

  public init(record: MarkdownRecord, expectedRevision: MarkdownRecordRevision) throws {
    guard record.identity != nil else { throw ResourceCodecError("identity", "Canonical identity is required.") }
    guard let revision = record.revision else { throw ResourceCodecError("revision", "Canonical revision is required.") }
    guard revision == expectedRevision else { throw ResourceCodecError("revision", "Canonical revision does not match the precondition.") }
    self.record = record
    self.expectedRevision = expectedRevision
  }
}

/// Proposed source, not a committed record or proof of conformance.
public struct ResourceMutationProposal: Equatable, Sendable {
  public let record: MarkdownRecord
  public let original: MarkdownRecord?
  public let baselineRevision: MarkdownRecordRevision?

  public init(created record: MarkdownRecord) throws {
    guard record.identity != nil, record.revision == nil else {
      throw ResourceCodecError("identity", "Creation requires a host identity and no caller-assigned revision.")
    }
    self.record = record
    original = nil
    baselineRevision = nil
  }

  public init(content: String, source: ResourceMutationSource) {
    var proposed = source.record
    proposed.content = content
    proposed.revision = nil
    record = proposed
    original = source.record
    baselineRevision = source.expectedRevision
  }
}

/// Structured codec failures use the same diagnostic vocabulary as assessments.
public struct ResourceCodecError: Error, Sendable, LocalizedError {
  public let diagnostic: MarkdownDiagnostic
  public var errorDescription: String? { diagnostic.message }

  public init(_ code: String, _ message: String, location: String = "record") {
    diagnostic = MarkdownDiagnostic(code: "resource.codec.\(code)", severity: .error,
      domain: .record, location: location, message: message)
  }
}

/// A writable representation must explicitly implement planning without persistence.
public protocol ResourceCodec: Sendable {
  func plan(_ edit: ResourceEdit, source: ResourceMutationSource) throws -> ResourceMutationProposal
}

/// Top-level metadata and whole-body edits for canonical Markdown.
///
/// Metadata edits may reserialize the entire block: comments, order, and original
/// formatting are not retained. Unchanged body bytes are retained exactly.
public struct MarkdownResourceCodec: ResourceCodec {
  public let configuration: ResourceCodecConfiguration

  public init(configuration: ResourceCodecConfiguration) throws {
    try configuration.validate()
    self.configuration = configuration
  }

  public func plan(_ edit: ResourceEdit, source: ResourceMutationSource) throws -> ResourceMutationProposal {
    do {
      return try propose(edit, source: source)
    } catch let error as ResourceCodecError {
      throw error
    } catch {
      throw ResourceCodecError("encoding", error.localizedDescription)
    }
  }

  private func propose(_ edit: ResourceEdit, source: ResourceMutationSource) throws -> ResourceMutationProposal {
    try Self.validatePath(source.record.context.path)
    let original = try Self.document(source.record.content)
    var metadata = original.frontMatter
    let body: String
    switch edit {
    case .replace(let values, let requestedBody):
      try validateFields(values.keys)
      if configuration.bodyWritable && requestedBody == nil {
        throw ResourceCodecError("body-required", "Replacement requires the writable body.")
      }
      try validateBody(requestedBody)
      for field in configuration.frontmatterFields { metadata[field] = nil }
      for (field, value) in values { metadata[field] = try Self.convert(value) }
      body = requestedBody ?? original.body
    case .patch(let changes, let requestedBody):
      try validateFields(changes.keys)
      try validateBody(requestedBody)
      for (field, change) in changes {
        switch change {
        case .set(let value): metadata[field] = try Self.convert(value)
        case .remove: metadata[field] = nil
        }
      }
      body = requestedBody ?? original.body
    }

    let metadataChanged = Self.normalized(metadata) != Self.normalized(original.frontMatter)
    let content: String
    if !metadataChanged {
      // UTF-8 slicing avoids changing normalization, CRLF body bytes, or comments.
      let prefixCount = source.record.content.utf8.count - original.body.utf8.count
      content = String(decoding: source.record.content.utf8.prefix(prefixCount), as: UTF8.self) + body
    } else {
      let format = original.frontMatterFormat ?? .yaml
      if original.frontMatterFormat == .yaml {
        var input = source.record.content[...]
        let raw = try FrontMatterParser().parse(&input).rawFrontMatter
        if let node = try Yams.compose(yaml: raw) { try Self.validateYAML(node) }
      }
      let serialized: String
      if format == .yaml {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        serialized = try encoder.encode(metadata)
      } else {
        serialized = try FrontMatterConversion.serialize(Self.normalized(metadata), format: format)
      }
      content = format.delimiter + "\n" + serialized
        + (serialized.hasSuffix("\n") ? "" : "\n") + format.delimiter + "\n" + body
    }
    let verified = try Self.document(content)
    guard Self.normalized(verified.frontMatter) == Self.normalized(metadata),
          verified.body.utf8.elementsEqual(body.utf8),
          verified.frontMatterFormat == (metadataChanged ? original.frontMatterFormat ?? .yaml : original.frontMatterFormat) else {
      throw ResourceCodecError("round-trip", "Encoding changed metadata values or document boundaries.")
    }
    return ResourceMutationProposal(content: content, source: source)
  }

  /// Validates client-supplied creation fields; protected values belong to the host.
  public func validateFields<S: Sequence>(_ fields: S) throws where S.Element == String {
    let writable = Set(configuration.frontmatterFields)
    for field in fields.sorted() where !writable.contains(field) {
      throw ResourceCodecError("field", "Unknown or read-only field: \(field)", location: "frontmatter.\(field)")
    }
  }

  private func validateBody(_ body: String?) throws {
    if body != nil && !configuration.bodyWritable {
      throw ResourceCodecError("body-read-only", "The body is read-only.")
    }
  }

  package static func validatePath(_ path: MarkdownRecordPath?) throws {
    guard let path else { return }
    let fileName = path.rawValue.split(separator: "/").last.map(String.init) ?? path.rawValue
    guard case .markdown = MarkdownRecordContentKind.rulesKind(forFileName: fileName) else {
      throw ResourceCodecError("source", "Only Markdown source files are supported.")
    }
  }

  /// A strict boundary check around the existing LF-only document parser.
  /// Delimiter-like or unterminated blocks must not be mistaken for absent metadata.
  package static func document(_ content: String) throws -> MarkdownDocument {
    var input = content[...]
    let opening = Parse(input: Substring.self) {
      Skip { Optionally { "\u{FEFF}" } }
      OneOf { "---"; "+++" }
    }
    if (try? opening.parse(&input)) != nil {
      var block = content[...]
      let delimiter = content.hasPrefix("---") ? "---" : "+++"
      let boundary = Parse(input: Substring.self) {
        delimiter
        "\n"
        PrefixUpTo("\n" + delimiter).map(String.init)
        "\n"
        delimiter
        OneOf { "\n"; End() }
      }
      // Empty frontmatter has no intervening content line.
      let empty = Parse(input: Substring.self) {
        delimiter
        "\n"
        delimiter
        OneOf { "\n"; End() }
      }
      var emptyInput = content[...]
      guard (try? boundary.parse(&block)) != nil || (try? empty.parse(&emptyInput)) != nil else {
        throw ResourceCodecError("boundary", "Unsupported or malformed frontmatter boundary; LF delimiters are required.")
      }
    }
    return try MarkdownDocument(content: content)
  }

  private static func normalized(_ value: FrontMatter) -> FrontMatter {
    MarkdownCodecSupport.sortedRecursively(value)
  }

  private static func validateYAML(_ node: Yams.Node) throws {
    let tags: [Tag.Name] = [.map, .seq, .str, .bool, .int, .float, .null, .timestamp]
    guard tags.contains(where: { node.tag == Tag($0) }) else {
      throw ResourceCodecError("yaml", "Metadata edits do not support YAML merge keys or custom tags.")
    }
    if let mapping = node.mapping {
      for (key, value) in mapping {
        guard key.tag == Tag(.str) else {
          throw ResourceCodecError("yaml", "Metadata keys must be strings.")
        }
        try validateYAML(value)
      }
    }
    if let sequence = node.sequence { for value in sequence { try validateYAML(value) } }
  }

  private static func convert(_ value: JSONValue) throws -> FrontMatterValue {
    switch value {
    case .null: return .null
    case .boolean(let value): return .boolean(value)
    case .integer(let value): return .integer(Int64(value))
    case .number(let value):
      guard value.isFinite else { throw ResourceCodecError("value", "Non-finite numbers are unsupported.") }
      return .number(value)
    case .string(let value): return .string(value)
    case .array(let values): return .array(try values.map(convert))
    case .object(let values): return .object(FrontMatter(try values.mapValues(convert)))
    }
  }
}
