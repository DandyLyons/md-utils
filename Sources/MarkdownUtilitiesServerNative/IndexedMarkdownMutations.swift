import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer
import MarkdownUtilitiesTemplates

enum MutationBoundary: Equatable, Sendable { case prepared, persisted, committed, published }

extension IndexedMarkdownRepository: MarkdownMutationService {
  /// The same entry point is available to non-HTTP clients such as index apply.
  public func mutate(resource name: String, identity: String?, path requestedPath: MarkdownRecordPath?,
    request: MarkdownMutationRequest, revision: MarkdownRecordRevision?, idempotencyKey: String?,
  ) async throws -> MarkdownMutationReceipt {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    try checkConfiguration()
    guard let resource = plan.resources.first(where: { $0.name == name }),
      let settings = resource.mutations, settings.operations.contains(request.operation) else {
      throw MarkdownMutationError(405, "operation.disabled", "This resource does not enable the requested mutation.")
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let fingerprint = IndexFingerprint.hash(try encoder.encode(request.payload))
    let keyHash: String?
    if request.operation == .create {
      guard let key = idempotencyKey, !key.isEmpty, key.utf8.count <= 256 else {
        throw MarkdownMutationError(400, "idempotency.required", "Creation requires an Idempotency-Key of 1–256 bytes.")
      }
      keyHash = IndexFingerprint.combined([name, request.operation.rawValue, key])
    } else { keyHash = nil }
    var pendingPaths = Set<String>()
    for url in try journalFiles() {
      let receipt = try readReceipt(url)
      if (receipt.state == .completed || receipt.state == .abandoned),
        let retention = plan.resources.first(where: { $0.name == receipt.resource })?.mutations?.idempotencyRetentionSeconds,
        Date().timeIntervalSince(receipt.completedAt ?? receipt.created) > Double(retention) {
        try FileManager.default.removeItem(at: url)
        continue
      }
      if receipt.state != .completed && receipt.state != .abandoned { pendingPaths.insert(receipt.path.rawValue) }
      if receipt.keyHash == keyHash, keyHash != nil {
        guard receipt.requestHash == fingerprint else { throw MarkdownMutationError(409, "idempotency.mismatch", "This key belongs to a different request.") }
        return receipt
      }
    }
    // Reconcile the entire configured collection before relying on constraint evidence.
    try await refresh(lease: lease)
    let planner = ResourceMutationPlanner(types: evaluator.types, rules: try evaluator.rules ?? MarkdownRuleCompiler().compile([]))
    let proposal: ResourceMutationProposal?
    let validation: ResourceMutationValidation?
    let source: MarkdownRecord?
    let target: MarkdownRecordPath
    var explicitlyEditing = Set<String>()
    if request.operation == .create {
      let creation = try await prepareCreation(request: request, resource: resource, planner: planner)
      proposal = creation.proposal; validation = creation
      guard let allocated = creation.proposal.record.context.path else { throw RecordStoreError.unavailable }
      target = allocated; source = nil
    } else {
      guard let revision else { throw MarkdownMutationError(428, "revision.required", "Canonical revision is required.") }
      let resolved: MarkdownServerReadLookupResult
      if let requestedPath { resolved = try await lookup(path: requestedPath) }
      else if let identity, let alias = request.lookupName { resolved = try await lookup(resource: name, lookup: alias, value: identity) }
      else if let identity { resolved = try await lookup(resource: name, identity: .init(rawValue: identity)) }
      else { throw MarkdownMutationError(400, "request.identity", "Supply a primary identity or exact path.") }
      let projected: GenericMarkdownRecord
      switch resolved {
      case .record(let record): projected = record
      case .notFound: throw MarkdownMutationError(404, "record.not-found", "No selected record exists.")
      case .conflict: throw MarkdownMutationError(409, "identity.ambiguous", "Select the intended document using its exact resource-scoped path.")
      }
      guard projected.memberships.contains(where: { $0.resourceName == name }), let path = projected.logicalPath else {
        throw MarkdownMutationError(404, "record.not-found", "The resource does not select this document.")
      }
      target = path
      let original = try await record(for: .init(rawValue: path.rawValue))
      guard original.revision == revision else { throw MarkdownMutationError(412, "revision.stale", "The canonical revision has changed.") }
      source = original
      let mutationSource = try ResourceMutationSource(record: original, expectedRevision: revision)
      var proposedContext = original.context
      proposedContext.modificationDate = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
      switch request.operation {
      case .delete: proposal = nil; validation = nil
      case .replace, .patch:
        let result = try await planner.plan(request.edit(), source: mutationSource, resource: resource, policy: request.validationPolicy, proposedContext: proposedContext)
        proposal = result.proposal; validation = result
      case .identity, .repairUUID:
        var values: [String: JSONValue]
        if request.operation == .identity {
          values = try request.object("identifiers", required: true)
          guard !values.isEmpty, Set(values.keys).isSubset(of: Set(settings.identityFields)) else {
            throw MarkdownMutationError(422, "identity.field", "Identity edits accept only configured identityFields.")
          }
        } else {
          guard let uuidPath = plan.persistentIdentity?.path, let first = uuidPath.first else {
            throw MarkdownMutationError(422, "uuid.disabled", "No persistent UUID is configured.")
          }
          let analyzed = await MarkdownRecordAnalyzer.analyze(original)
          var metadata = analyzed.userFrontmatter ?? [:]
          set(.string(UUID().uuidString.lowercased()), path: uuidPath[...], in: &metadata)
          values = [first: metadata[first] ?? .null]
        }
        explicitlyEditing = Set(values.keys)
        let codec = try MarkdownResourceCodec(configuration: .init(frontmatterFields: values.keys.sorted(), bodyWritable: false))
        let encoded = try codec.plan(.patch(frontmatter: values.mapValues { .set($0) }, body: nil), source: mutationSource)
        let candidate = ResourceMutationProposal(content: encoded.record.content, source: mutationSource,
          proposedContext: encoded.record.content == original.content ? nil : proposedContext)
        proposal = candidate
        validation = try await planner.validator.validate(candidate, destination: planner.requirements(for: resource), policy: request.validationPolicy)
      case .create: throw RecordStoreError.unavailable
      }
    }
    guard !pendingPaths.contains(target.rawValue) else {
      throw MarkdownMutationError(409, "recovery.required", "An unresolved operation owns this path. Inspect operation status before writing.")
    }
    if let validation, !validation.isValid {
      throw MarkdownMutationError(422, "record.invalid", "The complete proposal failed validation.", diagnostics: validation.diagnostics)
    }
    if let proposal {
      guard proposal.record.content.utf8.count <= 8 * 1024 * 1024 else { throw MarkdownMutationError(413, "record.too-large", "Proposed source exceeds 8 MiB.") }
      let after = await MarkdownRecordAnalyzer.analyze(proposal.record)
      let afterProjection = try await project(proposal.record)
      if let source {
        let before = await MarkdownRecordAnalyzer.analyze(source)
        let beforeProjection = try await project(source)
        let names = Set((afterProjection?.memberships ?? []).map(\.resourceName) + (beforeProjection?.memberships ?? []).map(\.resourceName))
        let policy = FileEditPolicy(revision: source.revision, memberships: names, plan: plan, contracts: validation?.changes ?? [])
        try policy.validate(before: before.userFrontmatter ?? [:], after: after.userFrontmatter ?? [:], explicitlyEditing: explicitlyEditing)
      }
      if source != nil { try await validateCollection(proposal.record, projection: afterProjection) }
    }
    try checkConfiguration()
    try Task.checkCancellation()
    var receipt = MarkdownMutationReceipt(resource: name, operation: request.operation, path: target,
      revision: proposal.map { .init(rawValue: IndexFingerprint.hash(Data($0.record.content.utf8))) }, baseline: source?.revision,
      requestHash: fingerprint, keyHash: keyHash,
      lostConformance: validation?.lostConformance.map { "\($0.kind.rawValue).\($0.name)" } ?? [],
      lostMembership: validation?.lostMembership.map { "\($0.kind.rawValue).\($0.name)" } ?? [],
      diagnostics: validation?.diagnostics ?? [],
    )
    receipt.validationPolicy = request.validationPolicy
    receipt.conformanceChanges = validation?.changes.filter { ($0.previouslyPassed && !$0.passes) || ($0.previouslySelected && !$0.selected) } ?? []
    try writeReceipt(receipt)
    do {
      try mutationCheckpoint?(.prepared)
      let store: any RecordStore = CoordinatedNativeRecordStore(repository: self, root: root, lease: lease)
      if let proposal {
        if let revision = source?.revision { _ = try await store.replace(proposal.record, ifRevision: revision) }
        else { _ = try await store.create(proposal.record) }
      } else if let revision = source?.revision {
        try await store.delete(identity: .init(rawValue: target.rawValue), ifRevision: revision)
      } else { throw RecordStoreError.unavailable }
      try mutationCheckpoint?(.persisted)
    } catch let error as MarkdownMutationError where [409, 412, 413, 422].contains(error.status) {
      try FileManager.default.removeItem(at: receiptURL(receipt.id))
      throw error
    } catch {
      receipt.state = .recoveryRequired
      try? writeReceipt(receipt)
      return receipt
    }
    receipt.state = .committed
    receipt.sourceCommitted = true
    do {
      try writeReceipt(receipt)
      try mutationCheckpoint?(.committed)
      try await refresh(lease: lease)
      try mutationCheckpoint?(.published)
      receipt = try await published(receipt)
      try writeReceipt(receipt)
    } catch let error as MarkdownMutationError where error.code == "recovery.source-changed" {
      receipt.state = .recoveryRequired
      try? writeReceipt(receipt)
    } catch {
      receipt.state = .committed
      try? writeReceipt(receipt)
    }
    return receipt
  }

  public func operation(resource: String, id: String) async throws -> MarkdownMutationReceipt {
    guard UUID(uuidString: id)?.uuidString.lowercased() == id else { throw MarkdownMutationError(404, "operation.not-found", "Unknown operation.") }
    let url = receiptURL(id)
    guard FileManager.default.fileExists(atPath: url.path) else { throw MarkdownMutationError(404, "operation.not-found", "Unknown operation.") }
    let result = try readReceipt(url)
    guard result.resource == resource else { throw MarkdownMutationError(404, "operation.not-found", "Unknown operation.") }
    return result
  }

  /// Explicit operator confirmation resolves indeterminate intents without modifying source.
  public func resolveOperation(resource: String, id: String, decision: MarkdownRecoveryDecision) async throws -> MarkdownMutationReceipt {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    try checkConfiguration()
    var receipt = try await operation(resource: resource, id: id)
    guard receipt.state != .completed && receipt.state != .abandoned else { return receipt }
    let data = try NativeMutationFiles.read(NativeMutationFiles.url(root: root, path: receipt.path))
    let expected = decision == .confirmCommitted ? receipt.revision : receipt.baseline
    guard data.map(IndexFingerprint.hash) == expected?.rawValue else {
      throw MarkdownMutationError(409, "recovery.source-changed", "Current source does not match the selected outcome; no files were changed.")
    }
    if decision == .confirmNotCommitted {
      guard receipt.state != .committed else { throw MarkdownMutationError(409, "recovery.committed", "A durable receipt already confirms this write committed.") }
      receipt.state = .abandoned
      receipt.completedAt = Date()
      try writeReceipt(receipt)
    } else {
      receipt.state = .committed
      receipt.sourceCommitted = true
      try writeReceipt(receipt)
      try await refresh(lease: lease)
      receipt = try await published(receipt)
      try writeReceipt(receipt)
    }
    return receipt
  }

  /// Recovery never rewrites authoritative files or guesses who committed an intent.
  public func recoverMutations() async throws {
    let lease = try await CollectionWriterLease.acquire(root: root)
    defer { withExtendedLifetime(lease) {} }
    for url in try journalFiles() {
      var receipt = try readReceipt(url)
      if receipt.state == .prepared { receipt.state = .recoveryRequired; try writeReceipt(receipt) }
      guard receipt.state == .committed else { continue }
      let data = try NativeMutationFiles.read(NativeMutationFiles.url(root: root, path: receipt.path))
      guard data.map(IndexFingerprint.hash) == receipt.revision?.rawValue else {
        receipt.state = .recoveryRequired; try writeReceipt(receipt); continue
      }
      try await refresh(lease: lease)
      receipt = try await published(receipt)
      try writeReceipt(receipt)
    }
  }

  private func published(_ value: MarkdownMutationReceipt) async throws -> MarkdownMutationReceipt {
    var receipt = value
    let source = try NativeMutationFiles.read(NativeMutationFiles.url(root: root, path: receipt.path))
    guard source.map(IndexFingerprint.hash) == receipt.revision?.rawValue else {
      throw MarkdownMutationError(409, "recovery.source-changed", "Source changed after commit; the operation needs recovery.")
    }
    if receipt.operation != .delete {
      guard case .record(let record) = try await lookup(path: receipt.path), record.revision == receipt.revision else {
        throw MarkdownMutationError(503, "publication.pending", "The committed revision is not yet published.")
      }
      receipt.record = record
    }
    receipt.state = .completed
    receipt.completedAt = Date()
    return receipt
  }

  private func prepareCreation(request: MarkdownMutationRequest, resource: PlannedMarkdownResource,
    planner: ResourceMutationPlanner,
  ) async throws -> ResourceMutationValidation {
    for attempt in 0...1000 {
      let candidate = try await createProposal(request: request, resource: resource, planner: planner, slugAttempt: attempt)
      guard candidate.isValid else { return candidate }
      do {
        try await validateCollection(candidate.proposal.record, projection: project(candidate.proposal.record))
        return candidate
      } catch let error as MarkdownMutationError {
        guard let slug = resource.mutations?.creation?.slug, slug.collision == .suffix,
          try request.object("frontmatter")[slug.field] == nil, try request.object("identifiers")[slug.field] == nil,
          error.code == "identity.collision", error.diagnostics.contains(where: { $0.location == "frontmatter." + slug.field }),
          attempt < 1000 else { throw error }
      }
    }
    throw MarkdownMutationError(409, "slug.exhausted", "No slug could be allocated.")
  }

  private func createProposal(request: MarkdownMutationRequest, resource: PlannedMarkdownResource,
    planner: ResourceMutationPlanner, slugAttempt: Int = 0,
  ) async throws -> ResourceMutationValidation {
    guard let allocation = resource.mutations?.creation, let writable = resource.writable, let template = writable.creation else {
      throw MarkdownMutationError(422, "creation.disabled", "Creation has no configured template and allocation.")
    }
    var fields = try request.object("frontmatter")
    var protected = try request.object("identifiers")
    guard Set(protected.keys).isSubset(of: Set(allocation.identifiers)), Set(fields.keys).isDisjoint(with: protected.keys) else {
      throw MarkdownMutationError(422, "creation.identifiers", "Supply configured creation-only identifiers separately from writable frontmatter.")
    }
    let sourceName: String?
    if case .string(let value) = fields[allocation.filenameField] { sourceName = value } else { sourceName = nil }
    guard let filename = try request.string("filename") ?? sourceName.map({ $0 + ".md" }),
      !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0"),
      ["md", "markdown"].contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) else {
      throw MarkdownMutationError(422, "filename.invalid", "Supply an expressive Markdown filename or configured filename source field.")
    }
    let directory = allocation.directory.rawValue == "." ? "" : allocation.directory.rawValue
    var target = try MarkdownRecordPath(directory + filename)
    var suffix = 1
    while FileManager.default.fileExists(atPath: try NativeMutationFiles.url(root: root, path: target).path) {
      guard allocation.collision == .suffix, suffix <= 10_000 else { throw MarkdownMutationError(409, "path.exists", "The creation filename is already allocated.") }
      let nameURL = URL(fileURLWithPath: filename)
      let base = nameURL.deletingPathExtension().lastPathComponent
      let ext = nameURL.pathExtension
      target = try MarkdownRecordPath(directory + "\(base) (\(suffix)).\(ext)"); suffix += 1
    }
    if let slug = allocation.slug {
      let supplied = fields[slug.field] ?? protected[slug.field]
      if supplied != nil, case .string = supplied {} else if supplied != nil {
        throw MarkdownMutationError(422, "slug.invalid", "Supplied slug must be a string.")
      }
      let provided: String? = if case .string(let value) = supplied { value } else { nil }
      let text: String
      if slug.sourceField == "$filename" { text = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent }
      else if case .string(let value) = fields[slug.sourceField] ?? protected[slug.sourceField] { text = value }
      else if provided != nil { text = "" }
      else { throw MarkdownMutationError(422, "slug.source", "The configured slug source must be a string.") }
      var generated = try MarkdownSlugGenerator.resolve(provided: provided, from: text, policy: slug.policy)
      if provided == nil && slugAttempt > 0 { generated += "-\(slugAttempt)" }
      if resource.protectedIdentityFields(persistentIdentity: plan.persistentIdentity).contains(slug.field) {
        fields[slug.field] = nil; protected[slug.field] = .string(generated)
      } else { fields[slug.field] = .string(generated) }
    }
    // A persistentIdentity lookup explicitly opts the resource into UUID creation.
    if let uuid = plan.persistentIdentity,
      resource.lookups.contains(where: { $0.source == .persistentIdentity }) || resource.identityPolicy.source == .frontmatter(path: uuid.path, format: .uuid) {
      set(.string(UUID().uuidString.lowercased()), path: uuid.path[...], in: &protected)
    }
    let allProtected = resource.protectedIdentityFields(persistentIdentity: plan.persistentIdentity).union(writable.codec.protectedFields)
    guard Set(fields.keys).isDisjoint(with: allProtected) else { throw MarkdownMutationError(422, "creation.protected", "Protected identifiers belong in creation-only input.") }
    let codec = try MarkdownResourceCodec(configuration: .init(frontmatterFields: writable.codec.frontmatterFields,
      bodyWritable: writable.codec.bodyWritable, protectedFields: allProtected.sorted()))
    let candidate = try await TemplateResourceCreationCodec(codec: codec, template: template).plan(
      input: .init(frontmatter: fields, data: request.payload["data"] ?? .object([:])),
      identity: .init(rawValue: target.rawValue), context: .init(path: target, modificationDate: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))), protectedFrontmatter: protected)
    return try await planner.validator.validate(candidate, destination: planner.requirements(for: resource))
  }

  private func project(_ record: MarkdownRecord) async throws -> GenericMarkdownRecord? {
    let snapshot = try await MarkdownServerReadSnapshotBuilder(store: SingleRecordStore(record: record),
      plan: plan, ruleRegistry: evaluator.rules ?? MarkdownRuleCompiler().compile([]), typeRegistry: evaluator.types).build()
    return snapshot.resources.lazy.compactMap { $0.records.first }.first
  }

  private func validateCollection(_ proposed: MarkdownRecord, projection: GenericMarkdownRecord?) async throws {
    let analyzed = await MarkdownRecordAnalyzer.analyze(proposed)
    let selected = Set(projection?.memberships.map(\.resourceName) ?? [])
    struct Check { let resource: PlannedMarkdownResource; let policy: MarkdownRecordIdentityPolicy; let value: String; let server: Bool }
    var checks: [Check] = []
    for resource in plan.resources {
      if selected.contains(resource.name) {
        let primary = MarkdownRecordIdentityIndex.assess(analyzed, policy: resource.identityPolicy)
        guard let value = primary.primaryIdentity?.rawValue else { throw MarkdownMutationError(422, "identity.invalid", "The proposed primary identity is missing or invalid.") }
        checks.append(Check(resource: resource, policy: resource.identityPolicy, value: value, server: false))
      }
      for lookup in resource.assessmentLookups(persistentIdentity: plan.persistentIdentity) {
        let constraint = resource.constraint(for: lookup)
        guard selected.contains(resource.name) || constraint.uniqueWithin == .server,
          let policy = lookup.policy(persistentIdentity: plan.persistentIdentity) else { continue }
        let value = MarkdownRecordIdentityIndex.assess(analyzed, policy: policy)
        if (value.status == .invalid && (selected.contains(resource.name) || lookup.source == .persistentIdentity))
          || (value.primaryIdentity == nil && constraint.requireValue && selected.contains(resource.name)) {
          throw MarkdownMutationError(422, "identity.invalid", "The proposed lookup \(lookup.name) violates its format or required-value constraint.")
        }
        if let scope = constraint.uniqueWithin, let key = value.primaryIdentity?.rawValue {
          checks.append(Check(resource: resource, policy: policy, value: key, server: scope == .server))
        }
      }
    }
    var token: RecordStoreContinuationToken?
    repeat {
      let page = try await records(matching: RecordStoreQuery(limit: 1, continuationToken: token))
      for other in page.records where other.identity != proposed.identity {
        let otherAnalyzed = await MarkdownRecordAnalyzer.analyze(other)
        if !checks.isEmpty && otherAnalyzed.parseDiagnostics.contains(where: { $0.severity == .error }) {
          throw MarkdownMutationError(503, "identity.incomplete", "A collection document cannot be assessed; repair its parse diagnostics before enforcing uniqueness.")
        }
        let memberships = try await project(other)?.memberships ?? []
        for check in checks where check.server || memberships.contains(where: { $0.resourceName == check.resource.name }) {
          let assessment = MarkdownRecordIdentityIndex.assess(otherAnalyzed, policy: check.policy)
          if assessment.primaryIdentity?.rawValue == check.value {
            let location: String
            if case .frontmatter(let path, _) = check.policy.source { location = "frontmatter." + path.joined(separator: ".") }
            else { location = "identity" }
            throw MarkdownMutationError(409, "identity.collision", "The proposal violates a configured identity uniqueness scope.",
              diagnostics: [.init(code: "identity.collision", severity: .error, domain: .record,
                location: location, message: "A value already exists in the configured uniqueness scope.")])
          }
        }
      }
      token = page.continuationToken
    } while token != nil
  }

  private func set(_ value: JSONValue, path: ArraySlice<String>, in object: inout [String: JSONValue]) {
    guard let first = path.first else { return }
    if path.count == 1 { object[first] = value; return }
    var nested: [String: JSONValue] = if case .object(let existing) = object[first] { existing } else { [:] }
    set(value, path: path.dropFirst(), in: &nested); object[first] = .object(nested)
  }

  private func journalDirectory() throws -> URL {
    let directory = root.appendingPathComponent(".md-utils/mutations/", isDirectory: true)
    guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else { throw RecordStoreError.unavailable }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    // Persist the journal directory's entry before a source commit can depend on it.
    try NativeMutationFiles.syncDirectory(directory.deletingLastPathComponent())
    try NativeMutationFiles.syncDirectory(root)
    return directory
  }
  private func receiptURL(_ id: String) -> URL { root.appendingPathComponent(".md-utils/mutations/\(id).json") }
  private func journalFiles() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: journalDirectory(), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
  }
  private func readReceipt(_ url: URL) throws -> MarkdownMutationReceipt {
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let data = try handle.read(upToCount: 64 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 64 * 1024 * 1024 else { throw RecordStoreError.unavailable }
    return try JSONDecoder().decode(MarkdownMutationReceipt.self, from: data)
  }
  private func writeReceipt(_ receipt: MarkdownMutationReceipt) throws {
    let directory = try journalDirectory()
    let url = receiptURL(receipt.id)
    try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url); try handle.synchronize(); try handle.close()
    try NativeMutationFiles.syncDirectory(directory)
  }
}
