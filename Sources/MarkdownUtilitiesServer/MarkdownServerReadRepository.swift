import Foundation
import MarkdownUtilitiesCore

/// A validated, bounded collection request shared by native and portable adapters.
public struct MarkdownServerReadQuery: Codable, Equatable, Sendable {
  public internal(set) var limit: Int
  public internal(set) var cursor: String?
  public internal(set) var pathPrefix: String?
  public internal(set) var valid: Bool?
  public internal(set) var filter: [String: JSONValue]
  public internal(set) var search: String?

  public init(limit: Int = 100, cursor: String? = nil, pathPrefix: String? = nil,
    valid: Bool? = nil, filter: [String: JSONValue] = [:], search: String? = nil) throws {
    guard (1...1_000).contains(limit) else {
      throw MarkdownServerReadError.invalidQuery("limit must be between 1 and 1000")
    }
    for value in filter.values {
      switch value {
      case .array, .object: throw MarkdownServerReadError.invalidQuery("filter values must be JSON scalars")
      default: break
      }
    }
    if let pathPrefix, MarkdownSearchRoot(rawValue: pathPrefix) == nil {
      throw MarkdownServerReadError.invalidQuery("pathPrefix must be a collection-relative directory ending in /")
    }
    guard try JSONEncoder().encode(filter).count + (search?.utf8.count ?? 0) + (pathPrefix?.utf8.count ?? 0) <= 4_096 else {
      throw MarkdownServerReadError.invalidQuery("Combined filter, search, and path parameters exceed 4096 bytes")
    }
    self.limit = limit
    self.cursor = cursor
    self.pathPrefix = pathPrefix == "." ? nil : pathPrefix
    self.valid = valid
    self.filter = filter
    self.search = search
  }

  public func matches(_ record: GenericMarkdownRecord) -> Bool {
    if let pathPrefix, record.logicalPath?.rawValue.hasPrefix(pathPrefix) != true { return false }
    if let valid, record.valid != valid { return false }
    return filter.allSatisfy { record.frontmatter?[$0.key] == $0.value }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(limit: values.decode(Int.self, forKey: .limit),
      cursor: values.decodeIfPresent(String.self, forKey: .cursor),
      pathPrefix: values.decodeIfPresent(String.self, forKey: .pathPrefix),
      valid: values.decodeIfPresent(Bool.self, forKey: .valid),
      filter: values.decode([String: JSONValue].self, forKey: .filter),
      search: values.decodeIfPresent(String.self, forKey: .search))
  }
}

/// One generation-consistent page. A byte bound may produce fewer than `limit` records.
public struct MarkdownServerReadPage: Codable, Equatable, Sendable {
  public let records: [GenericMarkdownRecord]
  public let generation: String
  public let nextCursor: String?

  public init(records: [GenericMarkdownRecord], generation: String, nextCursor: String?) {
    self.records = records
    self.generation = generation
    self.nextCursor = nextCursor
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(records, forKey: .records)
    try container.encode(generation, forKey: .generation)
    try container.encode(nextCursor, forKey: .nextCursor)
  }
}

/// Stable read failures, independent of HTTP and database implementations.
public enum MarkdownServerReadError: Error, Equatable, Sendable {
  case invalidQuery(String)
  case generationChanged
  case searchUnavailable
  case sourceChanged
  case restartRequired
  case responseTooLarge
  case unavailable
}

/// HTTP reads remain independent of native persistence and refresh scheduling.
public protocol MarkdownServerReadRepository: Sendable {
  var resourceNames: [String] { get }
  func page(resource: String, query: MarkdownServerReadQuery) async throws -> MarkdownServerReadPage
  func lookup(resource: String, identity: MarkdownRecordIdentity) async throws -> MarkdownServerReadLookupResult
  func lookup(path: MarkdownRecordPath) async throws -> MarkdownServerReadLookupResult
  /// Whether reads are using the last successful publication after a refresh failure.
  func isStale() async -> Bool
}

extension MarkdownServerReadRepository {
  public func isStale() async -> Bool { false }
}

/// Cursor contents are opaque to clients and bind continuation to an exact query.
public struct MarkdownServerReadCursor: Codable, Sendable {
  public let resource: String
  public let generation: String
  public let query: MarkdownServerReadQuery
  public let after: String

  public init(resource: String, generation: String, query: MarkdownServerReadQuery, after: String) {
    self.resource = resource
    self.generation = generation
    var query = query
    query.cursor = nil
    self.query = query
    self.after = after
  }

  public func encoded() throws -> String {
    let value = try JSONEncoder().encode(self).base64EncodedString()
    guard value.utf8.count <= 16_384 else { throw MarkdownServerReadError.invalidQuery("Continuation exceeds the cursor size limit") }
    return value
  }

  public static func position(resource: String, generation: String, query: MarkdownServerReadQuery) throws -> String? {
    guard let raw = query.cursor else { return nil }
    guard raw.utf8.count <= 16_384, let data = Data(base64Encoded: raw),
      let cursor = try? JSONDecoder().decode(Self.self, from: data) else {
      throw MarkdownServerReadError.invalidQuery("Invalid cursor")
    }
    var expected = query
    expected.cursor = nil
    guard cursor.resource == resource, cursor.query == expected else {
      throw MarkdownServerReadError.invalidQuery("Cursor belongs to another query")
    }
    guard cursor.generation == generation else { throw MarkdownServerReadError.generationChanged }
    return cursor.after
  }
}

/// Adapts existing immutable fixtures and custom stores to the paged contract.
public struct MarkdownSnapshotReadRepository: MarkdownServerReadRepository {
  public let snapshot: MarkdownServerReadSnapshot
  public let generation: String
  public var resourceNames: [String] { snapshot.resources.map(\.name) }

  public init(snapshot: MarkdownServerReadSnapshot, generation: String = UUID().uuidString) {
    self.snapshot = snapshot
    self.generation = generation
  }

  public func page(resource: String, query: MarkdownServerReadQuery) async throws -> MarkdownServerReadPage {
    guard query.search == nil else { throw MarkdownServerReadError.searchUnavailable }
    let after = try MarkdownServerReadCursor.position(resource: resource, generation: generation, query: query)
    guard let selected = snapshot.resources.first(where: { $0.name == resource }) else {
      throw MarkdownServerReadError.unavailable
    }
    let sorted = selected.records.enumerated().sorted {
      let left = Array(($0.element.logicalPath?.rawValue ?? "").utf8)
      let right = Array(($1.element.logicalPath?.rawValue ?? "").utf8)
      return left == right ? $0.offset < $1.offset : left.lexicographicallyPrecedes(right)
    }
    let position = after.flatMap(Int.init)
    if after != nil, position == nil || position.map({ $0 < 0 || $0 >= sorted.count }) == true {
      throw MarkdownServerReadError.invalidQuery("Invalid snapshot position")
    }
    var records: [GenericMarkdownRecord] = []
    var bytes = 32_768
    var next: String?
    var lastPosition: Int?
    for (index, entry) in sorted.enumerated() {
      let record = entry.element
      if let position, index <= position { continue }
      guard query.matches(record) else { continue }
      if records.count == query.limit, let lastPosition {
        next = try MarkdownServerReadCursor(resource: resource, generation: generation, query: query, after: String(lastPosition)).encoded()
        break
      }
      let size = try markdownServerEncodedRecordSize(record)
      guard size <= 64 * 1_024 * 1_024 - 32_768 else { throw MarkdownServerReadError.responseTooLarge }
      if records.count == query.limit || bytes + size > 64 * 1_024 * 1_024 {
        if let lastPosition {
          next = try MarkdownServerReadCursor(resource: resource, generation: generation, query: query, after: String(lastPosition)).encoded()
        }
        break
      }
      records.append(record)
      lastPosition = index
      bytes += size + 1
    }
    return MarkdownServerReadPage(records: records, generation: generation, nextCursor: next)
  }

  public func lookup(resource: String, identity: MarkdownRecordIdentity) async throws -> MarkdownServerReadLookupResult {
    snapshot.resources.first(where: { $0.name == resource })?.lookup(primary: identity) ?? .notFound
  }

  public func lookup(path: MarkdownRecordPath) async throws -> MarkdownServerReadLookupResult {
    snapshot.lookup(logicalPath: path)
  }
}

/// Counts body escaping before allocating the encoded body-bearing representation.
/// Metadata is already bounded independently by the native projection reader.
package func markdownServerEncodedRecordSize(_ record: GenericMarkdownRecord) throws -> Int {
  let empty = GenericMarkdownRecord(canonicalIdentity: record.canonicalIdentity, identityStatus: record.identityStatus,
    logicalPath: record.logicalPath, revision: record.revision, memberships: record.memberships,
    valid: record.valid, frontmatter: record.frontmatter, body: "", diagnostics: record.diagnostics)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.withoutEscapingSlashes]
  var size = try encoder.encode(empty).count
  for byte in record.body.utf8 {
    switch byte {
    case 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x22, 0x5C: size += 2
    case 0..<0x20: size += 6
    default: size += 1
    }
    if size > 64 * 1_024 * 1_024 - 32_768 { throw MarkdownServerReadError.responseTooLarge }
  }
  return size
}
