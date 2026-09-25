import Foundation
import Hummingbird
import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates

@available(macOS 14.0, iOS 17.0, tvOS 17.0, *)
enum MarkdownMutationHTTP {
  static func register(route: EndpointRouteDescription, collectionRoute: String, service: any MarkdownMutationService,
    router: Router<BasicRequestContext>,
  ) throws {
    guard let resource = route.resourceName else { throw MarkdownServerReadError.unavailable }
    if route.kind == .mutationRecovery {
      router.post(RouterPath(route.path.rawValue)) { request, context in
        do {
          guard request.headers[.contentType]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            throw MarkdownMutationError(415, "request.media-type", "Use application/json.")
          }
          let bytes = try await request.body.collect(upTo: 1024)
          let values = try JSONDecoder().decode([String: String].self, from: Data(bytes.readableBytesView))
          guard values.count == 1, let raw = values["decision"], let decision = MarkdownRecoveryDecision(rawValue: raw) else {
            throw MarkdownMutationError(400, "recovery.decision", "Supply confirmCommitted or confirmNotCommitted as decision.")
          }
          return try response(await service.resolveOperation(resource: resource, id: context.parameters.get("id") ?? "", decision: decision), collectionRoute: collectionRoute)
        } catch { return try failure(error) }
      }
      return
    }
    if route.kind == .mutationStatus {
      router.get(RouterPath(route.path.rawValue)) { _, context in
        do { return try response(await service.operation(resource: resource, id: context.parameters.get("id") ?? ""), collectionRoute: collectionRoute, statusQuery: true) }
        catch { return try failure(error) }
      }
      return
    }
    guard let operation = route.mutationOperation else { throw MarkdownServerReadError.unavailable }
    guard let method = HTTPRequest.Method(rawValue: route.method.rawValue) else { throw MarkdownServerReadError.unavailable }
    router.on(RouterPath(route.path.rawValue), method: method) { request, context in
      do {
        let revision = operation == .create ? nil : try MarkdownRevisionHeader.decode(header("MD-Utils-If-Revision", request))
        if operation != .delete {
          guard request.headers[.contentType]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            throw MarkdownMutationError(415, "request.media-type", "Use application/json.")
          }
        }
        let bytes = try await request.body.collect(upTo: 8 * 1024 * 1024)
        var input = try MarkdownMutationRequest(operation: operation, data: Data(bytes.readableBytesView))
        input.lookupName = route.lookupName
        var identity = context.parameters.get("id")?.removingPercentEncoding
        var path: MarkdownRecordPath?
        if route.lookupUsesQuery == true {
          guard request.uri.string.utf8.count <= 32_768, let values = URLComponents(string: request.uri.string)?.queryItems,
            values.count == 1, values[0].name == (route.lookupName == nil ? "path" : "value"), let value = values[0].value,
            !value.isEmpty, value.utf8.count <= 4096 else {
            throw MarkdownMutationError(400, "request.path", "Supply exactly one collection-relative path query parameter.")
          }
          if route.lookupName != nil { identity = value }
          else {
            guard let valid = try? MarkdownRecordPath(value) else { throw MarkdownMutationError(400, "request.path", "Invalid collection-relative path.") }
            path = valid
          }
        } else if URLComponents(string: request.uri.string)?.queryItems?.isEmpty == false {
          throw MarkdownMutationError(400, "request.query", "This mutation route does not accept query parameters.")
        }
        let receipt = try await service.mutate(resource: resource, identity: identity, path: path,
          request: input, revision: revision, idempotencyKey: header("Idempotency-Key", request))
        return try response(receipt, collectionRoute: collectionRoute)
      } catch { return try failure(error) }
    }
  }
  private static func header(_ name: String, _ request: Request) -> String? {
    guard let field = HTTPFields.Element.Name(name) else { return nil }
    return request.headers[field]
  }
  private static func response(_ receipt: MarkdownMutationReceipt, collectionRoute: String, statusQuery: Bool = false) throws -> Response {
    var payload = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(receipt))
    payload["committed"] = (receipt.state == .prepared || receipt.state == .recoveryRequired) && !receipt.committed ? .null : .boolean(receipt.committed)
    if receipt.state != .completed {
      payload["code"] = .string(receipt.state == .committed ? "mutation.publication-pending" : receipt.state == .abandoned ? "mutation.abandoned" : "mutation.recovery-required")
    }
    payload["operationStatus"] = .string(collectionRoute + "/_operations/" + receipt.id)
    var result = try json(payload, status: statusQuery ? 200 : receipt.state == .completed ? (receipt.operation == .create ? 201 : 200) : receipt.state == .abandoned ? 409 : 503)
    if let revision = receipt.revision, receipt.committed, let name = HTTPFields.Element.Name("MD-Utils-Revision") {
      result.headers[name] = MarkdownRevisionHeader.encode(revision)
    }
    return result
  }
  private static func failure(_ error: any Error) throws -> Response {
    let problem: MarkdownMutationError
    switch error {
    case let value as MarkdownMutationError: problem = value
    case let value as ResourceCodecError: problem = .init(422, value.diagnostic.code, value.localizedDescription, diagnostics: [value.diagnostic])
    case let value as MarkdownTemplateError:
      problem = .init(422, "template.\(value.stage.rawValue)", value.localizedDescription, diagnostics: value.diagnostics)
    case let value as MarkdownSlugGenerator.Failure: problem = .init(422, "slug.invalid", value.localizedDescription)
    case is DecodingError: problem = .init(400, "request.invalid", "Malformed request envelope.")
    case let value as any HTTPResponseError: problem = .init(value.status.code, "request.body", "Request body exceeds the limit or cannot be read.")
    case MarkdownServerReadError.sourceChanged: problem = .init(412, "revision.stale", "Authoritative source changed; refresh and retry.")
    case MarkdownServerReadError.restartRequired: problem = .init(503, "configuration.changed", "Restart the server after configuration changes.")
    default: problem = .init(503, "mutation.unavailable", "Mutation could not complete; inspect operation status before retrying.")
    }
    struct Detail: Encodable { let code: String; let message: String; let diagnostics: [MarkdownDiagnostic] }
    struct Envelope: Encodable { let error: Detail }
    return try json(Envelope(error: Detail(code: problem.code, message: problem.message, diagnostics: problem.diagnostics)), status: problem.status)
  }
  private static func json<T: Encodable>(_ value: T, status: Int) throws -> Response {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return Response(status: .init(code: status), headers: [.contentType: "application/json; charset=utf-8"],
      body: .init(byteBuffer: ByteBuffer(bytes: try encoder.encode(value))))
  }
}
