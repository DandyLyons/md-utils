import Foundation
import Hummingbird
import MarkdownUtilitiesCore

/// Stable machine-readable details for an HTTP failure.
public struct MarkdownServerHTTPError: Codable, Equatable, Sendable {
  public let totalCandidates: Int?
  public let truncated: Bool?
  /// Stable error code suitable for client branching.
  public let code: String
  /// Human-readable explanation of the failure.
  public let message: String
  /// Every ambiguous record when a lookup cannot choose one canonical result.
  public let candidates: [GenericMarkdownRecord]?

  /// Creates a structured HTTP error.
  public init(
    code: String,
    message: String,
    candidates: [GenericMarkdownRecord]? = nil,
    totalCandidates: Int? = nil,
    truncated: Bool? = nil
  ) {
    self.code = code
    self.message = message
    self.candidates = candidates
    self.totalCandidates = totalCandidates
    self.truncated = truncated
  }
}

/// Top-level JSON error envelope returned by every md-utils server failure.
public struct MarkdownServerHTTPErrorEnvelope: Codable, Equatable, Sendable {
  /// Structured error details.
  public let error: MarkdownServerHTTPError

  /// Creates a top-level error envelope.
  public init(error: MarkdownServerHTTPError) {
    self.error = error
  }
}

/// Startup failures detected while adapting an endpoint plan to Hummingbird.
public enum MarkdownServerHTTPAdapterError: Error, Equatable, LocalizedError, Sendable {
  /// The immutable endpoint plan and read snapshot describe different resources.
  case resourceSnapshotMismatch(planned: [String], available: [String])
  /// A route references no resource or a resource absent from the validated plan.
  case missingRouteResource(operationID: String, resourceName: String?)
  /// The plan contains a method unsupported by the read-only adapter.
  case unsupportedMethod(operationID: String, method: EndpointHTTPMethod)

  /// Human-readable startup failure description.
  public var errorDescription: String? {
    switch self {
    case .resourceSnapshotMismatch(let planned, let available):
      return "Endpoint plan resources \(planned) do not match read snapshot resources \(available)"
    case .missingRouteResource(let operationID, let resourceName):
      return "Route \"\(operationID)\" references unavailable resource \"\(resourceName ?? "nil")\""
    case .unsupportedMethod(let operationID, let method):
      return "Route \"\(operationID)\" uses unsupported HTTP method \"\(method.rawValue)\""
    }
  }
}

/// Registers generic Hummingbird 2 handlers directly from an immutable endpoint plan.
@available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
public enum MarkdownServerHTTPAdapter {
  /// Installs every planned collection, item, and reserved logical-path route.
  ///
  /// Registration validates that the supplied snapshot was built for the same resource
  /// set. No resource-specific Swift source is generated and no request reparses records.
  ///
  /// - Parameters:
  ///   - plan: Validated source of route truth.
  ///   - snapshot: Immutable read-side state used by every handler.
  ///   - router: Hummingbird router that receives the planned routes.
  /// - Returns: Every route successfully installed, preserving endpoint-plan order.
  /// - Throws: ``MarkdownServerHTTPAdapterError`` when the plan and snapshot drift.
  @discardableResult
  public static func register(
    plan: EndpointPlan,
    snapshot: MarkdownServerReadSnapshot,
    on router: Router<BasicRequestContext>
  ) throws -> [EndpointRouteDescription] {
    try register(plan: plan, repository: MarkdownSnapshotReadRepository(snapshot: snapshot), on: router)
  }

  /// Registers the same contract against a generation-aware, bounded read repository.
  @discardableResult
  public static func register(
    plan: EndpointPlan,
    repository: any MarkdownServerReadRepository,
    on router: Router<BasicRequestContext>
  ) throws -> [EndpointRouteDescription] {
    let plannedNames = plan.resources.map(\.name).sorted()
    let snapshotNames = repository.resourceNames.sorted()
    guard plannedNames == snapshotNames else {
      throw MarkdownServerHTTPAdapterError.resourceSnapshotMismatch(
        planned: plannedNames,
        available: snapshotNames
      )
    }

    let openAPIDocument = try MarkdownServerOpenAPIGenerator.generate(from: plan)
    let openAPIJSON = try openAPIDocument.serialized(format: .json)
    let resources = Dictionary(uniqueKeysWithValues: plan.resources.map { ($0.name, $0) })
    var installedRoutes: [EndpointRouteDescription] = []
    for route in plan.routes {
      guard route.method == .get else {
        throw MarkdownServerHTTPAdapterError.unsupportedMethod(
          operationID: route.operationID,
          method: route.method
        )
      }

      switch route.kind {
      case .collection:
        let resource = try routeResource(route, resources: resources)
        router.get(RouterPath(route.path.rawValue)) { request, _ in
          do {
            let query = try readQuery(request.uri.string)
            guard query.search == nil || resource.searchEnabled else { throw MarkdownServerReadError.searchUnavailable }
            let page = try await repository.page(resource: resource.name, query: query)
            return await readHeaders(try jsonResponse(page, status: .ok), repository: repository, generation: page.generation)
          } catch { return try readErrorResponse(error) }
        }

      case .item:
        let resource = try routeResource(route, resources: resources)
        router.get(RouterPath(route.path.rawValue)) { _, context in
          guard let encodedIdentity = context.parameters.get("id"),
                let identity = encodedIdentity.removingPercentEncoding
          else {
            return try errorResponse(
              status: .badRequest,
              code: "request.invalid-identity",
              message: "The item identity is missing or has invalid percent encoding"
            )
          }
          do { return await readHeaders(try lookupResponse(
            try await repository.lookup(resource: resource.name, identity: MarkdownRecordIdentity(rawValue: identity)),
            notFoundMessage: "No record exists with primary identity \"\(identity)\"",
            conflictCode: "record.identity-conflict",
            conflictMessage: "Several records share the requested primary identity"
          ), repository: repository) } catch { return try readErrorResponse(error) }
        }

      case .logicalPath:
        router.get(RouterPath(hummingbirdPath(for: route))) { _, context in
          let encodedPath = context.parameters.getCatchAll().joined(separator: "/")
          guard let pathString = encodedPath.removingPercentEncoding,
                let path = try? MarkdownRecordPath(pathString)
          else {
            return try errorResponse(
              status: .badRequest,
              code: "request.invalid-logical-path",
              message: "The logical path must be a valid collection-relative record path"
            )
          }
          do { return await readHeaders(try lookupResponse(
            try await repository.lookup(path: path),
            notFoundMessage: "No record exists at logical path \"\(path.rawValue)\"",
            conflictCode: "record.logical-path-conflict",
            conflictMessage: "Several records share the requested logical path"
          ), repository: repository) } catch { return try readErrorResponse(error) }
        }

      case .openAPI:
        router.get(RouterPath(route.path.rawValue)) { _, _ in
          Response(
            status: .ok,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(bytes: openAPIJSON))
          )
        }
      }
      installedRoutes.append(route)
    }
    return installedRoutes
  }

  private static func routeResource(
    _ route: EndpointRouteDescription,
    resources: [String: PlannedMarkdownResource]
  ) throws -> PlannedMarkdownResource {
    guard let name = route.resourceName, let resource = resources[name] else {
      throw MarkdownServerHTTPAdapterError.missingRouteResource(
        operationID: route.operationID,
        resourceName: route.resourceName
      )
    }
    return resource
  }

  private static func hummingbirdPath(for route: EndpointRouteDescription) -> String {
    switch route.kind {
    case .logicalPath:
      return "/_md-utils/path/**"
    case .collection, .item, .openAPI:
      return route.path.rawValue
    }
  }

  private static func lookupResponse(
    _ result: MarkdownServerReadLookupResult,
    notFoundMessage: String,
    conflictCode: String,
    conflictMessage: String
  ) throws -> Response {
    switch result {
    case .record(let record):
      _ = try markdownServerEncodedRecordSize(record)
      return try jsonResponse(record, status: .ok)
    case .notFound:
      return try errorResponse(
        status: .notFound,
        code: "record.not-found",
        message: notFoundMessage
      )
    case .conflict(let conflict):
      var candidates: [GenericMarkdownRecord] = []
      var bytes = 32_768
      for record in conflict.candidates.prefix(1_000) {
        let size: Int
        do { size = try markdownServerEncodedRecordSize(record) }
        catch MarkdownServerReadError.responseTooLarge { break }
        guard bytes + size <= 64 * 1_024 * 1_024 else { break }
        candidates.append(record)
        bytes += size + 1
      }
      return try errorResponse(
        status: .conflict,
        code: conflictCode,
        message: conflictMessage,
        candidates: candidates,
        totalCandidates: conflict.totalCandidates,
        truncated: candidates.count < conflict.totalCandidates
      )
    }
  }

  private static func errorResponse(
    status: HTTPResponse.Status,
    code: String,
    message: String,
    candidates: [GenericMarkdownRecord]? = nil,
    totalCandidates: Int? = nil,
    truncated: Bool? = nil
  ) throws -> Response {
    try jsonResponse(
      MarkdownServerHTTPErrorEnvelope(error: MarkdownServerHTTPError(
        code: code,
        message: message,
        candidates: candidates,
        totalCandidates: totalCandidates,
        truncated: truncated
      )),
      status: status
    )
  }

  private static func jsonResponse<Value: Encodable>(
    _ value: Value,
    status: HTTPResponse.Status
  ) throws -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard data.count <= 64 * 1_024 * 1_024 else { throw MarkdownServerReadError.responseTooLarge }
    return Response(
      status: status,
      headers: [.contentType: "application/json; charset=utf-8"],
      body: .init(byteBuffer: ByteBuffer(bytes: data))
    )
  }

  private static func readQuery(_ uri: String) throws -> MarkdownServerReadQuery {
    guard uri.utf8.count <= 32_768, let components = URLComponents(string: uri) else {
      throw MarkdownServerReadError.invalidQuery("Invalid request URI")
    }
    var values: [String: String] = [:]
    for item in components.queryItems ?? [] {
      guard ["limit", "cursor", "pathPrefix", "valid", "filter", "q"].contains(item.name),
        values[item.name] == nil, let value = item.value else {
        throw MarkdownServerReadError.invalidQuery("Unknown, repeated, or empty query parameter")
      }
      values[item.name] = value
    }
    let limit: Int
    if let raw = values["limit"] {
      guard let parsed = Int(raw) else { throw MarkdownServerReadError.invalidQuery("Invalid limit") }
      limit = parsed
    } else { limit = 100 }
    var valid: Bool?
    if let raw = values["valid"] {
      guard raw == "true" || raw == "false" else { throw MarkdownServerReadError.invalidQuery("Invalid valid flag") }
      valid = raw == "true"
    }
    var filter: [String: JSONValue] = [:]
    if let raw = values["filter"] {
      guard let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: Data(raw.utf8)) else {
        throw MarkdownServerReadError.invalidQuery("filter must be a JSON object")
      }
      filter = decoded
    }
    return try MarkdownServerReadQuery(limit: limit, cursor: values["cursor"], pathPrefix: values["pathPrefix"],
      valid: valid, filter: filter, search: values["q"])
  }

  private static func readErrorResponse(_ error: any Error) throws -> Response {
    let status: HTTPResponse.Status
    let code: String
    let message: String
    switch error {
    case MarkdownServerReadError.invalidQuery(let detail):
      status = .badRequest; code = "request.invalid-query"; message = detail
    case MarkdownServerReadError.generationChanged:
      status = .conflict; code = "request.generation-changed"; message = "Restart pagination against the current generation"
    case MarkdownServerReadError.searchUnavailable:
      status = .badRequest; code = "request.search-unavailable"; message = "Search is not enabled for this resource"
    case MarkdownServerReadError.sourceChanged:
      status = .serviceUnavailable; code = "record.source-changed"; message = "Authoritative files changed; refresh the index and retry"
    case MarkdownServerReadError.restartRequired:
      status = .serviceUnavailable; code = "server.restart-required"; message = "Server definitions changed; restart to load the new contract"
    case MarkdownServerReadError.responseTooLarge:
      status = .contentTooLarge; code = "record.response-too-large"; message = "The record exceeds the response byte limit"
    default:
      status = .serviceUnavailable; code = "server.unavailable"; message = "The read repository is unavailable"
    }
    return try errorResponse(status: status, code: code, message: message)
  }

  private static func readHeaders(_ response: Response, repository: any MarkdownServerReadRepository,
    generation: String? = nil) async -> Response {
    var response = response
    if let name = HTTPFields.Element.Name("X-Md-Utils-Stale") {
      response.headers[name] = await repository.isStale() ? "true" : "false"
    }
    if let generation, let name = HTTPFields.Element.Name("X-Md-Utils-Generation") {
      response.headers[name] = generation
    }
    return response
  }
}
