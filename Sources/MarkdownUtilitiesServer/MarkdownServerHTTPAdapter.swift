import Foundation
import Hummingbird
import MarkdownUtilitiesCore

/// Stable machine-readable details for an HTTP failure.
public struct MarkdownServerHTTPError: Codable, Equatable, Sendable {
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
    candidates: [GenericMarkdownRecord]? = nil
  ) {
    self.code = code
    self.message = message
    self.candidates = candidates
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
  /// - Throws: ``MarkdownServerHTTPAdapterError`` when the plan and snapshot drift.
  public static func register(
    plan: EndpointPlan,
    snapshot: MarkdownServerReadSnapshot,
    on router: Router<BasicRequestContext>
  ) throws {
    let plannedNames = plan.resources.map(\.name).sorted()
    let snapshotNames = snapshot.resources.map(\.name).sorted()
    guard plannedNames == snapshotNames else {
      throw MarkdownServerHTTPAdapterError.resourceSnapshotMismatch(
        planned: plannedNames,
        available: snapshotNames
      )
    }

    let resources = Dictionary(uniqueKeysWithValues: snapshot.resources.map { ($0.name, $0) })
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
        router.get(RouterPath(route.path.rawValue)) { _, _ in
          try jsonResponse(resource.records, status: .ok)
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
          return try lookupResponse(
            resource.lookup(primary: MarkdownRecordIdentity(rawValue: identity)),
            notFoundMessage: "No record exists with primary identity \"\(identity)\"",
            conflictCode: "record.identity-conflict",
            conflictMessage: "Several records share the requested primary identity"
          )
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
          return try lookupResponse(
            snapshot.lookup(logicalPath: path),
            notFoundMessage: "No record exists at logical path \"\(path.rawValue)\"",
            conflictCode: "record.logical-path-conflict",
            conflictMessage: "Several records share the requested logical path"
          )
        }
      }
    }
  }

  private static func routeResource(
    _ route: EndpointRouteDescription,
    resources: [String: MarkdownResourceReadSnapshot]
  ) throws -> MarkdownResourceReadSnapshot {
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
    case .collection, .item:
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
      return try jsonResponse(record, status: .ok)
    case .notFound:
      return try errorResponse(
        status: .notFound,
        code: "record.not-found",
        message: notFoundMessage
      )
    case .conflict(let conflict):
      return try errorResponse(
        status: .conflict,
        code: conflictCode,
        message: conflictMessage,
        candidates: conflict.candidates
      )
    }
  }

  private static func errorResponse(
    status: HTTPResponse.Status,
    code: String,
    message: String,
    candidates: [GenericMarkdownRecord]? = nil
  ) throws -> Response {
    try jsonResponse(
      MarkdownServerHTTPErrorEnvelope(error: MarkdownServerHTTPError(
        code: code,
        message: message,
        candidates: candidates
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
    return Response(
      status: status,
      headers: [.contentType: "application/json; charset=utf-8"],
      body: .init(byteBuffer: ByteBuffer(bytes: data))
    )
  }
}
