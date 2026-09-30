import MarkdownUtilitiesCore

/// Wire contracts for the mutation routes already present in the immutable plan.
///
/// Builds OpenAPI description objects and JSON Schema objects, rather than actual
/// request or response payloads. ``MarkdownServerOpenAPIGenerator`` installs the
/// operation objects under `paths[path][method]` and merges ``schemas`` into
/// `components.schemas`, then validates the complete document.
///
/// Helpers assume compiler-validated resource configuration. They describe the
/// transport implemented by `MarkdownMutationHTTP`; they do not enable routes,
/// validate incoming requests, or persist records. See <doc:GeneratedOpenAPI>.
enum MarkdownMutationOpenAPI {
  /// Shared prose for revision parameter/header descriptions and the token schema.
  ///
  /// This is a description string, not an encoded revision or a schema object.
  static let revisionDescription = "Versioned canonical revision: r1. followed by standard Base64 of the UTF-8 revision. Native revisions are source SHA-256 hashes. This is not an ETag or publication generation; If-Match is not a substitute."

  /// Builds the OpenAPI Operation Object for a mutation, status, or recovery route.
  ///
  /// The returned object always contains `operationId: string`, `tags: [string]`,
  /// `summary: string`, `parameters: [Parameter Object]`, and
  /// `responses: {statusCode: Response Object}`. Mutation operations also include
  /// `description`. Mutation and recovery routes include `requestBody`; status
  /// reads omit it. The HTTP method and route path are supplied by the caller's
  /// enclosing Path Item Object, not embedded in this value.
  ///
  /// Creation requires an idempotency header. Other mutations require a revision
  /// header and either an identity path parameter or an exact lookup query value.
  /// Status/recovery routes address a receipt by its `id` path parameter.
  ///
  /// - Parameters:
  ///   - route: A planned mutation-family route with its operation and lookup metadata.
  ///   - resource: The matching resource with explicit mutation configuration.
  /// - Returns: An object-valued OpenAPI operation, not a complete path or document.
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

  /// Describes the JSON request envelope accepted by one configured mutation.
  ///
  /// Returns a Schema Object with `type: "object"`, `properties: {field: schema}`,
  /// `additionalProperties: false`, and `description`. A `required: [string]`
  /// array is included only when at least one envelope field is mandatory:
  ///
  /// - Create permits optional `frontmatter`, `data`, `filename`, and `identifiers`.
  /// - Replace requires `frontmatter` and, when writable, `body`.
  /// - Patch permits `frontmatter: {set: object, remove: [string]}` and writable `body`.
  /// - Identity editing requires a nonempty `identifiers` object.
  /// - Delete and UUID repair permit only an empty object. DELETE's body may be
  ///   omitted; that distinction is expressed by the enclosing Request Body Object.
  ///
  /// Replace, patch, and identity editing also permit `validationPolicy` via a
  /// component reference. Metadata and identifier property names are restricted
  /// to their configured fields, but their values use the unconstrained schema
  /// `{}`: complete-record validation remains a separate runtime check. Patch
  /// removal names are unique; when no fields are writable, `items: false`
  /// permits only an empty removal array. Set/remove overlap is checked at runtime.
  ///
  /// A creation template's input schema is preserved in
  /// `x-md-utils-template-input-schema`. It applies to assembled template input,
  /// including host-owned values, rather than directly constraining this envelope.
  ///
  /// - Returns: The envelope's schema, without an `application/json` content wrapper.
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

  /// Maps the route's documented HTTP statuses to OpenAPI Response Objects.
  ///
  /// The shape is `{"200": {"description": ..., "content": ...}, ...}`;
  /// keys are decimal status strings, not integers. Every response describes
  /// `application/json`. Successful writes reference `MarkdownMutationReceipt`:
  /// create uses `201`, and other mutations (including DELETE) use `200`.
  /// Status reads use `200` even for unfinished receipts; recovery can use either
  /// success code depending on the original operation.
  ///
  /// Ordinary errors reference `MarkdownMutationErrorEnvelope`. `409` and `503`
  /// use `oneOf` with receipt and error-envelope references because abandoned,
  /// uncertain, or committed-but-unpublished operations can return a receipt.
  /// Selected responses describe the optional canonical revision header.
  ///
  /// - Returns: An object-valued Responses Object for a mutation-family route.
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

  /// Named JSON Schema components merged directly into `components.schemas`.
  ///
  /// Each dictionary value is an object-valued schema, not an instance of the
  /// corresponding Swift type. Keys define the names used by local `$ref` values:
  ///
  /// - `MarkdownRevisionToken`: a bounded string with the `r1.` Base64 token pattern.
  /// - `ResourceMutationValidationPolicy`: a string enum with the preservation default.
  /// - `MarkdownMutationReceipt`: the Codable receipt fields plus the HTTP adapter's
  ///   `committed`, `operationStatus`, and optional `code` fields. `committed` can
  ///   be null when the source outcome is uncertain. Optional Codable fields are
  ///   omitted when absent; they are not generally represented by explicit null.
  /// - `MarkdownMutationErrorEnvelope`: `{error: {code, message, diagnostics}}`.
  /// - `MarkdownDiagnostic`: shared diagnostic fields, including `fixIts`.
  /// - `MarkdownFixIt`: `{id, title, safety, edits}`. Each edit is a `oneOf` of
  ///   Swift's synthesized enum objects, such as `{"ensureFrontmatter": {}}` or
  ///   `{"appendHeading": {"text": "Book", "level": 1}}`.
  /// - `ResourceConformanceChange`: before/after pass and selection flags with diagnostics.
  ///
  /// Receipt dates use numeric Foundation reference-date seconds. Receipt records
  /// reference `GenericMarkdownRecord`, which the parent generator must also supply.
  /// Object schemas reject unknown fields; individual `required` arrays preserve
  /// the distinction between required, omitted, and nullable values.
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
      "provenanceEpoch": text, "provenanceOperatorConfirmed": boolean,
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

  /// Describes `MD-Utils-Revision` for an OpenAPI response's `headers` map.
  ///
  /// - Returns: `{"description": string, "schema": {"$ref":
  ///   "#/components/schemas/MarkdownRevisionToken"}}`. The caller supplies the
  ///   header name as the map key. No `required` flag is emitted because a response
  ///   includes this header only when a committed revision is available.
  static func revisionHeader() -> JSONValue {
    .object(["description": .string(revisionDescription + " Present when a committed revision is available."), "schema": ref("MarkdownRevisionToken")])
  }

  /// Non-null string schema: `{"type": "string"}`; not a string instance.
  private static let text = JSONValue.object(["type": .string("string")])

  /// Non-null Boolean schema: `{"type": "boolean"}`; not a Boolean instance.
  private static let boolean = JSONValue.object(["type": .string("boolean")])

  /// Numeric date schema: `{"type": "number", "description": string}`.
  ///
  /// Matches the receipt encoder's seconds since 2001-01-01 UTC, including
  /// fractional seconds. It does not advertise an ISO 8601 `date-time` string.
  private static let date = JSONValue.object(["type": .string("number"), "description": .string("Seconds since 2001-01-01T00:00:00Z (Foundation Codable date encoding).")])

  /// Converts strings to a literal JSON array, preserving order and duplicates.
  ///
  /// - Returns: `["first", "second", ...]`, used for keyword values such as
  ///   `required`, `enum`, or `type`; this is not an array schema.
  private static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }

  /// Builds `{"type": "string", "enum": [string, ...]}` from allowed values.
  ///
  /// Callers supply a nonempty set of allowed spellings; this helper neither
  /// deduplicates nor validates them. It does not add a default or permit null.
  private static func enumeration(_ values: [String]) -> JSONValue { .object(["type": .string("string"), "enum": strings(values)]) }

  /// Builds a local schema reference: `{"$ref": "#/components/schemas/<name>"}`.
  ///
  /// - Parameter name: An existing component key safe to embed as a JSON Pointer
  ///   segment. No escaping or existence check is performed here; these callers
  ///   use fixed component names, and the complete document is validated later.
  private static func ref(_ name: String) -> JSONValue { .object(["$ref": .string("#/components/schemas/\(name)")]) }

  /// Builds `{"type": "array", "items": itemSchema}` without length constraints.
  ///
  /// - Parameter item: An object or Boolean JSON Schema describing each element,
  ///   not a sample element. The value is embedded unchanged.
  private static func list(_ item: JSONValue) -> JSONValue { .object(["type": .string("array"), "items": item]) }

  /// Builds a closed object schema from property schemas and required field names.
  ///
  /// - Parameters:
  ///   - properties: Literal field names mapped to schemas, not instance values.
  ///     An empty schema `{}` allows any JSON value for that field.
  ///   - required: Names that must be present; callers ensure they exist in
  ///     `properties`. An empty list omits the `required` keyword entirely.
  /// - Returns: `{"type": "object", "properties": {...},
  ///   "additionalProperties": false}` with an optional `required: [string]`.
  ///   Empty properties therefore describe an empty object, not an arbitrary map.
  private static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
    var value: [String: JSONValue] = ["type": .string("object"), "properties": .object(properties), "additionalProperties": .boolean(false)]
    if !required.isEmpty { value["required"] = strings(required) }
    return .object(value)
  }
  /// Builds an inline, required OpenAPI Parameter Object.
  ///
  /// - Parameters:
  ///   - name: The HTTP header, path placeholder, or query parameter name.
  ///   - location: The OpenAPI `in` value; callers use `header`, `path`, or `query`.
  ///   - description: Human-readable parameter semantics.
  ///   - schema: A schema or schema reference; defaults to a non-null string schema.
  /// - Returns: `{"name": string, "in": string, "required": true,
  ///   "description": string, "schema": schema}`. This helper cannot describe
  ///   an optional parameter and does not check location/name consistency.
  private static func parameter(_ name: String, location: String, description: String, schema: JSONValue = text) -> JSONValue {
    .object(["name": .string(name), "in": .string(location), "required": .boolean(true), "description": .string(description), "schema": schema])
  }
  /// Wraps an envelope schema in an OpenAPI Request Body Object for JSON input.
  ///
  /// - Parameters:
  ///   - schema: The schema of the complete JSON body, embedded unchanged.
  ///   - required: Whether an HTTP body must be supplied. This does not control
  ///     which properties inside that body are required.
  ///   - limit: Transport byte limit to describe: 8 MiB for mutations or 1 KiB
  ///     for recovery. It is documentation, not an enforced JSON Schema constraint.
  /// - Returns: `{"required": boolean, "description": string,
  ///   "content": {"application/json": {"schema": schema}}}`.
  private static func body(_ schema: JSONValue, required: Bool = true, limit: Int = 8 * 1024 * 1024) -> JSONValue {
    .object(["required": .boolean(required), "description": .string("Maximum \(limit) bytes. Unknown envelope fields are rejected."),
      "content": .object(["application/json": .object(["schema": schema])])])
  }
  /// Wraps a response payload schema in an OpenAPI Response Object.
  ///
  /// - Parameters:
  ///   - description: Meaning of the HTTP outcome, including any recovery semantics.
  ///   - schema: Schema of the complete JSON payload, commonly a component reference
  ///     or a `oneOf` of receipt and error-envelope references.
  ///   - revision: Whether to describe the optional `MD-Utils-Revision` header.
  ///     This does not assert that every response carries a revision.
  /// - Returns: `{"description": string, "content": {"application/json":
  ///   {"schema": schema}}}`. When requested, adds `headers: {"MD-Utils-Revision":
  ///   Header Object}`. The caller supplies the HTTP status as the enclosing map key.
  private static func response(_ description: String, schema: JSONValue, revision: Bool = false) -> JSONValue {
    var value: [String: JSONValue] = ["description": .string(description), "content": .object(["application/json": .object(["schema": schema])])]
    if revision { value["headers"] = .object(["MD-Utils-Revision": revisionHeader()]) }
    return .object(value)
  }
}
