import MarkdownUtilitiesCore

/// Wire contracts for the mutation routes already present in the immutable plan.
enum MarkdownMutationOpenAPI {
  static let revisionDescription = "Versioned canonical revision: r1. followed by standard Base64 of the UTF-8 revision. Native revisions are source SHA-256 hashes. This is not an ETag or publication generation; If-Match is not a substitute."

  static func operation(_ route: EndpointRouteDescription, resource: PlannedMarkdownResource) -> JSONValue {
    var parameters: [JSONValue] = []
    var result: [String: JSONValue] = [
      "operationId": .string(route.operationID),
      "tags": strings([resource.name]),
      "responses": responses(route),
    ]
    if route.kind == .mutationStatus || route.kind == .mutationRecovery {
      parameters.append(parameter("id", location: "path", description: "Durable operation receipt identifier"))
      result["summary"] = .string(route.kind == .mutationStatus ? "Get mutation status" : "Resolve an uncertain mutation")
      if route.kind == .mutationRecovery {
        result["requestBody"] = body(object(["decision": enumeration(["confirmCommitted", "confirmNotCommitted"])], required: ["decision"]), limit: 1024)
      }
    } else if let operation = route.mutationOperation {
      result["summary"] = .string("\(operation.rawValue) \(resource.name)")
      result["description"] = .string("Writes affect the canonical document across resource aliases. Ordinary success requires index and server publication; publication changes invalidate generation-bound cursors. A receipt can report source committed with publication pending. Inspect operationStatus before retrying. UUID repair requires an explicitly selected document and does not rewrite references. DELETE removes the canonical document, not just resource membership.")
      if operation == .create {
        parameters.append(parameter("Idempotency-Key", location: "header",
          description: "Required, 1–256 UTF-8 bytes. Same key and payload replays the original operation; different payload conflicts. Completed receipts are retained for \(resource.mutations?.idempotencyRetentionSeconds ?? 604_800) seconds; unresolved operations are retained.",
          schema: .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(256)])))
      } else {
        parameters.append(parameter("MD-Utils-If-Revision", location: "header", description: revisionDescription, schema: ref("MarkdownRevisionToken")))
        if route.lookupUsesQuery == true {
          parameters.append(parameter(route.lookupName == nil ? "path" : "value", location: "query",
            description: "Exact resource-scoped lookup value, 1–4096 UTF-8 bytes. Supply exactly this query parameter; percent encode URL-sensitive text. Membership and ambiguity checks still apply.",
            schema: .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(4096)])))
        } else {
          parameters.append(parameter("id", location: "path", description: "Exact resource identity or named lookup value. No query parameters are accepted."))
        }
      }
      result["requestBody"] = body(request(operation, resource: resource), required: operation != .delete)
    }
    result["parameters"] = .array(parameters)
    return .object(result)
  }

  private static func request(_ operation: MarkdownMutationOperation, resource: PlannedMarkdownResource) -> JSONValue {
    let fields = Set(resource.writable?.codec.frontmatterFields ?? []).sorted()
    let frontmatter = object(Dictionary(uniqueKeysWithValues: fields.map { ($0, JSONValue.object([:])) }))
    var properties: [String: JSONValue] = [:]
    var required: [String] = []
    switch operation {
    case .create:
      properties = [
        "frontmatter": frontmatter,
        "data": .object(["description": .string("Knap template data; omitted means an empty object. Complete input is validated against the administrator's input schema before rendering.")]),
        "filename": .object(["type": .string("string"), "description": .string("Optional expressive filename, subject to configured allocation and collision policy; not an arbitrary host path.")]),
        "identifiers": object(Dictionary(uniqueKeysWithValues: Set(resource.mutations?.creation?.identifiers ?? []).map { ($0, JSONValue.object([:])) })),
      ]
    case .replace, .patch:
      properties["validationPolicy"] = ref("ResourceMutationValidationPolicy")
      if resource.writable?.codec.bodyWritable == true {
        properties["body"] = text
        if operation == .replace { required.append("body") }
      }
      if operation == .replace {
        properties["frontmatter"] = frontmatter
        required.append("frontmatter")
      } else {
        properties["frontmatter"] = object([
          "set": frontmatter,
          "remove": .object(["type": .string("array"), "uniqueItems": .boolean(true),
            "items": fields.isEmpty ? .boolean(false) : enumeration(fields.sorted())]),
        ])
      }
    case .identity:
      properties = [
        "identifiers": .object([
          "type": .string("object"), "minProperties": .integer(1), "additionalProperties": .boolean(false),
          "properties": .object(Dictionary(uniqueKeysWithValues: Set(resource.mutations?.identityFields ?? []).map { ($0, JSONValue.object([:])) })),
        ]),
        "validationPolicy": ref("ResourceMutationValidationPolicy"),
      ]
      required = ["identifiers"]
    case .delete, .repairUUID: break
    }
    var schema = object(properties, required: required).objectValue ?? [:]
    schema["description"] = .string("Explicit writable envelope. Top-level metadata names are literal; nested values replace the whole field. PATCH omission preserves values, set null stores null where supported, and remove deletes; a field cannot be both set and removed. PUT removes omitted writable metadata. Complete document validation and protected identity constraints are enforced before persistence; schema-valid input can still receive 422. Body-only edits preserve frontmatter bytes; metadata edits preserve body bytes and unaffected values, but may reserialize frontmatter formatting.")
    if operation == .create, let inputSchema = resource.writable?.creation?.inputSchema {
      // The template input schema applies to the assembled frontmatter/data input,
      // including host-owned values, not directly to this HTTP envelope.
      schema["x-md-utils-template-input-schema"] = inputSchema
    }
    return .object(schema)
  }

  private static func responses(_ route: EndpointRouteDescription) -> JSONValue {
    let receipt = ref("MarkdownMutationReceipt")
    let error = ref("MarkdownMutationErrorEnvelope")
    let union = JSONValue.object(["oneOf": .array([receipt, error])])
    var result: [String: JSONValue] = [
      "400": response("Malformed request, invalid revision token, or missing/invalid idempotency key", schema: error),
      "404": response("Resource-scoped record or operation not found", schema: error),
      "409": response("Identity, uniqueness, idempotency, or recovery conflict; an abandoned operation returns its receipt", schema: union),
      "503": response("Unavailable or restart required, or a receipt reporting publication pending/recovery required. Source may already be committed; do not assume rollback.", schema: union, revision: true),
    ]
    if route.kind == .mutationStatus {
      result["200"] = response("Current receipt, including incomplete or abandoned operations", schema: receipt, revision: true)
    } else {
      result["413"] = response("Request body exceeds the byte limit", schema: error)
      if route.mutationOperation != .delete {
        result["415"] = response("Use application/json", schema: error)
      }
      if route.kind == .mutation {
        result["412"] = response("Canonical source revision changed, including external edits", schema: error)
        result["422"] = response("Codec, identity, slug, template, or conformance validation failed. template.<stage> errors retain Knap diagnostic codes and locations; source is unchanged.", schema: error)
        if route.mutationOperation != .create {
          result["428"] = response("MD-Utils-If-Revision is required", schema: error)
        }
        result[route.mutationOperation == .create ? "201" : "200"] = response("Completed mutation receipt. DELETE also returns a JSON receipt with 200.", schema: receipt, revision: true)
      } else {
        result["200"] = response("Resolved completed non-creation operation", schema: receipt, revision: true)
        result["201"] = response("Resolved completed creation", schema: receipt, revision: true)
      }
    }
    return .object(result)
  }

  static var schemas: [String: JSONValue] {
    var receipt = [
      "state": enumeration(["prepared", "committed", "completed", "recoveryRequired", "abandoned"]),
      "sourceCommitted": boolean, "committed": JSONValue.object(["type": strings(["boolean", "null"])]),
      "id": text, "resource": text, "operation": enumeration(MarkdownMutationOperation.allCases.map(\.rawValue)),
      "path": text, "revision": text, "baseline": text, "requestHash": text, "keyHash": text,
      "created": date, "completedAt": date, "record": ref("GenericMarkdownRecord"),
      "lostConformance": list(text), "lostMembership": list(text), "diagnostics": list(ref("MarkdownDiagnostic")),
      "validationPolicy": ref("ResourceMutationValidationPolicy"), "conformanceChanges": list(ref("ResourceConformanceChange")),
      "code": enumeration(["mutation.publication-pending", "mutation.recovery-required", "mutation.abandoned"]),
      "operationStatus": text,
    ]
    receipt["committed"] = .object(["type": strings(["boolean", "null"]), "description": .string("Null means uncertain, true means canonical source committed. This does not imply index publication completed.")])
    let editCases: [JSONValue] = [
      object(["ensureFrontmatter": object([:])], required: ["ensureFrontmatter"]),
      object(["setFrontmatterValue": object(["path": list(text), "value": .object([:])], required: ["path", "value"])], required: ["setFrontmatterValue"]),
      object(["requestFrontmatterValue": object(["path": list(text)], required: ["path"])], required: ["requestFrontmatterValue"]),
      object(["appendHeading": object(["text": text, "level": .object(["type": .string("integer")])], required: ["text", "level"])], required: ["appendHeading"]),
    ]
    return [
      "MarkdownRevisionToken": .object(["type": .string("string"), "minLength": .integer(7), "maxLength": .integer(4096),
        "pattern": .string("^r1\\.[A-Za-z0-9+/]+={0,2}$"), "description": .string(revisionDescription)]),
      "ResourceMutationValidationPolicy": .object(["type": .string("string"),
        "enum": strings(["preserveExistingConformance", "endpointOnly"]), "default": .string("preserveExistingConformance"),
        "description": .string("Preserve all currently passing loaded types/rules by default, including unexposed definitions. endpointOnly permits other conformance losses, but still enforces destination requirements. Losses are reported separately from membership changes.")]),
      "MarkdownMutationReceipt": object(receipt, required: [
        "state", "sourceCommitted", "committed", "id", "resource", "operation", "path", "requestHash", "created",
        "lostConformance", "lostMembership", "diagnostics", "validationPolicy", "conformanceChanges", "operationStatus",
      ]),
      "MarkdownMutationErrorEnvelope": object(["error": object([
        "code": text, "message": text, "diagnostics": list(ref("MarkdownDiagnostic")),
      ], required: ["code", "message", "diagnostics"])], required: ["error"]),
      "MarkdownDiagnostic": object([
        "code": text, "severity": enumeration(["error", "advisory"]),
        "domain": enumeration(["record", "frontmatter", "body", "context", "typeHint"]),
        "constraintID": text, "location": text, "message": text, "fixIts": list(ref("MarkdownFixIt")),
      ], required: ["code", "severity", "domain", "location", "message", "fixIts"]),
      "MarkdownFixIt": object([
        "id": text, "title": text, "safety": enumeration(["automatic", "requiresInput", "advisoryOnly"]),
        "edits": list(.object(["oneOf": .array(editCases)])),
      ], required: ["id", "title", "safety", "edits"]),
      "ResourceConformanceChange": object([
        "kind": enumeration(["type", "rule"]), "name": text, "previouslyPassed": boolean, "passes": boolean,
        "previouslySelected": boolean, "selected": boolean, "diagnostics": list(ref("MarkdownDiagnostic")),
      ], required: ["kind", "name", "previouslyPassed", "passes", "previouslySelected", "selected", "diagnostics"]),
    ]
  }

  static func revisionHeader() -> JSONValue {
    .object(["description": .string(revisionDescription + " Present when a committed revision is available."), "schema": ref("MarkdownRevisionToken")])
  }

  private static let text = JSONValue.object(["type": .string("string")])
  private static let boolean = JSONValue.object(["type": .string("boolean")])
  private static let date = JSONValue.object(["type": .string("number"), "description": .string("Seconds since 2001-01-01T00:00:00Z (Foundation Codable date encoding).")])
  private static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
  private static func enumeration(_ values: [String]) -> JSONValue { .object(["type": .string("string"), "enum": strings(values)]) }
  private static func ref(_ name: String) -> JSONValue { .object(["$ref": .string("#/components/schemas/\(name)")]) }
  private static func list(_ item: JSONValue) -> JSONValue { .object(["type": .string("array"), "items": item]) }
  private static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
    var value: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties), "additionalProperties": .boolean(false)]
    if !required.isEmpty { value["required"] = strings(required) }
    return .object(value)
  }
  private static func parameter(_ name: String, location: String, description: String, schema: JSONValue = text) -> JSONValue {
    .object(["name": .string(name), "in": .string(location), "required": .boolean(true), "description": .string(description), "schema": schema])
  }
  private static func body(_ schema: JSONValue, required: Bool = true, limit: Int = 8 * 1024 * 1024) -> JSONValue {
    .object(["required": .boolean(required), "description": .string("Maximum \(limit) bytes. Unknown envelope fields are rejected."),
      "content": .object(["application/json": .object(["schema": schema])])])
  }
  private static func response(_ description: String, schema: JSONValue, revision: Bool = false) -> JSONValue {
    var value: [String: JSONValue] = ["description": .string(description), "content": .object(["application/json": .object(["schema": schema])])]
    if revision { value["headers"] = .object(["MD-Utils-Revision": revisionHeader()]) }
    return .object(value)
  }
}
