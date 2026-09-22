import Foundation
import Hummingbird
import HummingbirdTesting
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer
@testable import MarkdownUtilitiesServerNative
import PathKit
import Testing

@Suite("Native resource mutations")
struct MarkdownMutationTests {
  private func fixture() throws -> Path {
    let root = Path("tmp/mutations/\(UUID().uuidString)/").absolute()
    try (root + ".md-utils/server/").mkpath()
    try (root + "books/").mkpath()
    try (root + ".md-utils/md-utils.json").write("""
      {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
      {"name":"books","match":{"paths":["books/**"]},"checks":[{"type":"requiredHeading","heading":"Book"}]}]}
      """)
    try (root + ".md-utils/server/server.yaml").write("""
      serverConfigVersion: "3"
      persistentIdentity: {path: [uuid]}
      resources:
        - name: books
          route: /books
          operations: [list, get]
          selection: {mode: rule, rule: books}
          identityPolicy: {source: frontmatter, path: [slug], format: string}
          lookups:
            - {name: uuid, source: persistentIdentity}
          writable:
            codec: {frontmatterFields: [title, subtitle], bodyWritable: true}
            creation: {template: "# Book\\n{{ data.text }}"}
          mutations:
            operations: [create, replace, patch, delete, identity, repairUUID]
            identityFields: [slug]
            creation:
              directory: books/
              identifiers: [slug]
              slug: {field: slug, sourceField: title, policy: unicode}
      """)
    return root
  }
  private func request(_ operation: MarkdownMutationOperation, _ json: String = "{}") throws -> MarkdownMutationRequest {
    try MarkdownMutationRequest(operation: operation, data: Data(json.utf8))
  }
  private func create(_ repository: IndexedMarkdownRepository, title: String = "Dune", key: String = "one") async throws -> MarkdownMutationReceipt {
    let payload: [String: JSONValue] = ["frontmatter": .object(["title": .string(title)]), "data": .object(["text": .string("Story")])]
    return try await repository.mutate(resource: "books", identity: nil, path: nil,
      request: MarkdownMutationRequest(operation: .create, data: JSONEncoder().encode(payload)), revision: nil, idempotencyKey: key)
  }

  @Test(arguments: [false, true])
  func crud(fts: Bool) async throws {
    let root = try fixture(); defer { try? root.delete() }
    if fts {
      let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
      try db.prepareCollection(root: root.string); try db.setBodyMode(.fts)
    }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    let created = try await create(repository, title: "Dune — Notes")
    #expect(created.state == .completed)
    #expect(created.path.rawValue == "books/Dune — Notes.md")
    #expect(created.record?.frontmatter?["slug"] == .string("dune-notes"))
    let uuid = try #require(created.record?.frontmatter?["uuid"])
    let replay = try await create(repository, title: "Dune — Notes")
    #expect(replay.id == created.id)
    #expect(replay.revision == created.revision)
    await #expect(throws: MarkdownMutationError.self) { try await create(repository, title: "Other") }
    let changed = try await repository.mutate(resource: "books", identity: "dune-notes", path: nil,
      request: request(.patch, #"{"frontmatter":{"set":{"title":"Changed"}}}"#),
      revision: created.revision, idempotencyKey: nil)
    #expect(changed.state == .completed)
    #expect(changed.record?.frontmatter?["uuid"] == uuid)
    #expect(changed.path == created.path)
    #expect(changed.record?.frontmatter?["slug"] == .string("dune-notes"))
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: "dune-notes", path: nil,
        request: request(.delete), revision: created.revision, idempotencyKey: nil)
    }
    let renamed = try await repository.mutate(resource: "books", identity: "dune-notes", path: nil,
      request: request(.identity, #"{"identifiers":{"slug":"new-slug"}}"#), revision: changed.revision, idempotencyKey: nil)
    #expect(renamed.state == .completed)
    #expect(try await repository.lookup(resource: "books", identity: .init(rawValue: "dune-notes")) == .notFound)
    let removed = try await repository.mutate(resource: "books", identity: "new-slug", path: nil,
      request: request(.delete), revision: renamed.revision, idempotencyKey: nil)
    #expect(removed.state == .completed)
    #expect(!(root + created.path.rawValue).exists)
    // Replaying creation returns the original receipt even after later deletion.
    #expect(try await create(repository, title: "Dune — Notes").id == created.id)
  }

  @Test func rejectionPreservesSource() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    let created = try await create(repository)
    let file = root + created.path.rawValue
    let original = try file.read(.utf8)
    for payload in [##"{"body":"# Wrong"}"##, #"{"frontmatter":{"set":{"slug":"stolen"}}}"#] {
      await #expect(throws: (any Error).self) {
        try await repository.mutate(resource: "books", identity: "dune", path: nil,
          request: request(.patch, payload), revision: created.revision, idempotencyKey: nil)
      }
      #expect(try file.read(.utf8) == original)
    }
    try file.write(original + "\nExternal")
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: "dune", path: nil,
        request: request(.delete), revision: created.revision, idempotencyKey: nil)
    }
    #expect(try file.read(.utf8).hasSuffix("External"))
  }

  @Test func collisionAndExplicitRepair() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    let created = try await create(repository)
    try (root + "hidden/").mkpath()
    try (root + "hidden/copy.md").write((root + created.path.rawValue).read(.utf8))
    let repaired = try await repository.mutate(resource: "books", identity: "dune", path: nil,
      request: request(.repairUUID), revision: created.revision, idempotencyKey: nil)
    #expect(repaired.state == .completed)
    #expect(repaired.record?.frontmatter?["uuid"] != created.record?.frontmatter?["uuid"])
    let another = try await create(repository, title: "Other", key: "two")
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: "other", path: nil,
        request: request(.identity, #"{"identifiers":{"slug":"dune"}}"#), revision: another.revision, idempotencyKey: nil)
    }
  }

  @Test func httpContracts() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    let created = try await create(repository)
    let router = Router()
    try MarkdownServerHTTPAdapter.register(plan: repository.plan, repository: repository, mutations: repository, on: router)
    try await Application(router: router).test(.router) { client in
      try await client.execute(uri: "/books/dune", method: .get) { response in
        #expect(response.status == .ok)
      }
      try await client.execute(uri: "/books/dune", method: .delete) { response in
        #expect(response.status.code == 428)
      }
      try await client.execute(uri: "/books/_operations/\(created.id)", method: .get) { response in
        #expect(response.status == .ok)
      }
      try await client.execute(uri: "/books/dune", method: .post) { response in
        #expect(response.status.code == 404 || response.status.code == 405)
      }
    }
  }

  @Test func strictEnvelopesAndOpaqueRevisions() throws {
    for (operation, json) in [
      (MarkdownMutationOperation.patch, #"{"frontmatter":{"set":{"a":1},"remove":["a"]}}"#),
      (.patch, #"{"frontmatter":{"remove":["a","a"]}}"#),
      (.patch, #"{"body":null}"#), (.replace, "{}"), (.delete, #"{"validationPolicy":"endpointOnly"}"#),
      (.create, #"{"path":"escape.md"}"#),
    ] { #expect(throws: MarkdownMutationError.self) { try request(operation, json) } }
    let opaque = MarkdownRecordRevision(rawValue: "opaque/日本語\nrevision")
    #expect(try MarkdownRevisionHeader.decode(MarkdownRevisionHeader.encode(opaque)) == opaque)
    for invalid in ["*", "W/\"abc\"", "abc", "r1.", "r1.YQ"] {
      #expect(throws: MarkdownMutationError.self) { try MarkdownRevisionHeader.decode(invalid) }
    }
  }

  @Test func committedPublicationFailureAndRestart() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    await repository.setMutationCheckpoint { if $0 == .committed { throw CancellationError() } }
    let pending = try await create(repository)
    #expect(pending.state == .committed)
    #expect((root + pending.path.rawValue).exists)
    #expect(try await create(repository).id == pending.id)
    let restarted = try IndexedMarkdownRepository(projectRoot: root.string)
    try await restarted.recoverMutations()
    let recovered = try await restarted.operation(resource: "books", id: pending.id)
    #expect(recovered.state == .completed)
    #expect(recovered.revision == pending.revision)
    #expect(try await create(restarted).id == pending.id)
  }

  @Test(arguments: [MutationBoundary.prepared, .persisted])
  func uncertainIntentNeverOverwrites(boundary: MutationBoundary) async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    await repository.setMutationCheckpoint { if $0 == boundary { throw CancellationError() } }
    let receipt = try await create(repository)
    #expect(receipt.state == .recoveryRequired)
    let file = root + receipt.path.rawValue
    try file.write("# External document\n")
    let restarted = try IndexedMarkdownRepository(projectRoot: root.string)
    try await restarted.recoverMutations()
    #expect(try file.read(.utf8) == "# External document\n")
    #expect(try await restarted.operation(resource: "books", id: receipt.id).state == .recoveryRequired)
  }

  @Test func simultaneousCreationReplaysOneAllocation() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let first = try IndexedMarkdownRepository(projectRoot: root.string)
    let second = try IndexedMarkdownRepository(projectRoot: root.string)
    async let a = create(first)
    async let b = create(second)
    let results = try await [a, b]
    #expect(results[0].id == results[1].id)
    #expect(try (root + "books/").children().count == 1)
  }

  @Test func crossResourceProtectionAndUnexposedConformance() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let config = root + ".md-utils/server/server.yaml"
    try config.write(config.read(.utf8) + """

        - name: aliases
          route: /aliases
          operations: [get]
          selection: {mode: rule, rule: books}
          identityPolicy: {source: logicalPath}
          writable:
            codec: {frontmatterFields: [title, slug], bodyWritable: true}
          mutations: {operations: [patch]}

      """)
    try (root + ".md-utils/md-utils.json").write("""
      {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
      {"name":"books","match":{"paths":["books/**"]},"checks":[{"type":"requiredHeading","heading":"Book"}]},
      {"name":"hidden","match":{"paths":["books/**"]},"checks":[{"type":"requiredHeading","heading":"Story"}]}]}
      """)
    try (root + "books/a.md").write("---\nslug: a\ntitle: A\n---\n# Book\n# Story\n")
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let original = try await repository.record(for: .init(rawValue: "books/a.md"))
    let path = try MarkdownRecordPath("books/a.md")
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "aliases", identity: nil, path: path,
        request: request(.patch, #"{"frontmatter":{"set":{"slug":"escape"}},"validationPolicy":"endpointOnly"}"#),
        revision: original.revision, idempotencyKey: nil)
    }
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: "a", path: nil,
        request: request(.patch, ##"{"body":"# Book\n"}"##), revision: original.revision, idempotencyKey: nil)
    }
    let override = try await repository.mutate(resource: "books", identity: "a", path: nil,
      request: request(.patch, ##"{"body":"# Book\n","validationPolicy":"endpointOnly"}"##), revision: original.revision, idempotencyKey: nil)
    #expect(override.state == .completed)
    #expect(override.lostConformance.contains("rule.hidden"))
  }

  @Test func explicitRecoveryDecisions() async throws {
    for boundary in [MutationBoundary.prepared, .persisted] {
      let root = try fixture(); defer { try? root.delete() }
      let repository = try IndexedMarkdownRepository(projectRoot: root.string)
      await repository.setMutationCheckpoint { if $0 == boundary { throw CancellationError() } }
      let receipt = try await create(repository)
      await repository.setMutationCheckpoint(nil)
      let resolved = try await repository.resolveOperation(resource: "books", id: receipt.id,
        decision: boundary == .prepared ? .confirmNotCommitted : .confirmCommitted)
      #expect(resolved.state == (boundary == .prepared ? .abandoned : .completed))
      #expect(try await create(repository).id == receipt.id)
    }
  }

  @Test func httpWriteAndNamedLookup() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let router = Router()
    try MarkdownServerHTTPAdapter.register(plan: repository.plan, repository: repository, mutations: repository, on: router)
    let revisionName = try #require(HTTPFields.Element.Name("MD-Utils-If-Revision"))
    let idempotencyName = try #require(HTTPFields.Element.Name("Idempotency-Key"))
    try await Application(router: router).test(.router) { client in
      let body = ByteBuffer(string: #"{"frontmatter":{"title":"Dune"},"data":{"text":"story"}}"#)
      try await client.execute(uri: "/books", method: .post, headers: [.contentType: "text/plain"], body: body) { response in
        #expect(response.status.code == 415)
      }
      let created = try await client.execute(uri: "/books", method: .post,
        headers: [.contentType: "application/json", idempotencyName: "http-one"], body: body) { response in
        #expect(response.status.code == 201)
        return try JSONDecoder().decode(MarkdownMutationReceipt.self, from: Data(response.body.readableBytesView))
      }
      let revision = try #require(created.revision)
      let uuidValue = try #require(created.record?.frontmatter?["uuid"])
      guard case .string(let uuid) = uuidValue else { Issue.record("Expected UUID"); return }
      let updated = try await client.execute(uri: "/books/by/uuid/\(uuid)", method: .put,
        headers: [.contentType: "application/json", revisionName: MarkdownRevisionHeader.encode(revision)],
        body: ByteBuffer(string: ##"{"frontmatter":{"title":"Replaced"},"body":"# Book\nNew body"}"##)) { response in
        #expect(response.status.code == 200)
        return try JSONDecoder().decode(MarkdownMutationReceipt.self, from: Data(response.body.readableBytesView))
      }
      #expect(updated.record?.frontmatter?["title"] == .string("Replaced"))
      #expect(updated.path == created.path)
      let current = try #require(updated.revision)
      try await client.execute(uri: "/books/_mutations/delete/by-path?path=books%2FDune.md", method: .delete,
        headers: [revisionName: MarkdownRevisionHeader.encode(current)]) { response in
        #expect(response.status.code == 200)
      }
      try await client.execute(uri: "/books/dune", method: .get) { response in #expect(response.status.code == 404) }
    }
  }

  @Test func suppliedSlugsFilenameCollisionsAndPathSafety() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    let supplied = try request(.create, #"{"filename":"Expressive (2026)!.md","frontmatter":{"title":"Different"},"identifiers":{"slug":"authored_slug"}}"#)
    let first = try await repository.mutate(resource: "books", identity: nil, path: nil,
      request: supplied, revision: nil, idempotencyKey: "supplied")
    #expect(first.record?.frontmatter?["slug"] == .string("authored_slug"))
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: nil, path: nil,
        request: supplied, revision: nil, idempotencyKey: "collision")
    }
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: nil, path: nil,
        request: request(.create, #"{"filename":"../escape.md","frontmatter":{"title":"x"}}"#), revision: nil, idempotencyKey: "unsafe")
    }
    let outsider = root + "outside.md"
    try outsider.write("# Outside")
    await #expect(throws: MarkdownMutationError.self) {
      try await repository.mutate(resource: "books", identity: nil, path: MarkdownRecordPath("outside.md"),
        request: request(.delete), revision: .init(rawValue: IndexFingerprint.hash(Data("# Outside".utf8))), idempotencyKey: nil)
    }
    #expect(outsider.exists)
  }

  @Test func configuredSuffixAllocation() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let config = root + ".md-utils/server/server.yaml"
    try config.write(config.read(.utf8)
      .replacingOccurrences(of: "directory: books/", with: "directory: books/\n        collision: suffix")
      .replacingOccurrences(of: "policy: unicode}", with: "policy: unicode, collision: suffix}"))
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    _ = try await create(repository)
    let second = try await create(repository, key: "two")
    #expect(second.state == .completed)
    #expect(second.path.rawValue == "books/Dune (1).md")
    #expect(second.record?.frontmatter?["slug"] == .string("dune-1"))
  }

  @Test func versionsStrictConfigurationAndPlanRoundTrip() throws {
    let root = try fixture(); defer { try? root.delete() }
    let config = root + ".md-utils/server/server.yaml"
    let original = try config.read(.utf8)
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    #expect(try JSONDecoder().decode(EndpointPlan.self, from: JSONEncoder().encode(repository.plan)) == repository.plan)
    #expect(try MarkdownServerConfigurationSchema.content(version: "3").contains("mutations"))
    try config.write(original.replacingOccurrences(of: "serverConfigVersion: \"3\"", with: "serverConfigVersion: \"2\""))
    #expect(throws: EndpointPlanCompilationError.self) { try IndexedMarkdownRepository(projectRoot: root.string) }
    try config.write(original.replacingOccurrences(of: "identityFields: [slug]", with: "identityFields: [uuid]"))
    #expect(throws: EndpointPlanCompilationError.self) { try IndexedMarkdownRepository(projectRoot: root.string) }
    try config.write(original.replacingOccurrences(of: "identityFields: [slug]", with: "identityField: [slug]"))
    #expect(throws: (any Error).self) { try IndexedMarkdownRepository(projectRoot: root.string) }
  }

  @Test func finalRevisionCheckAndPostCommitExternalEdit() async throws {
    for boundary in [MutationBoundary.prepared, .published] {
      let root = try fixture(); defer { try? root.delete() }
      let repository = try IndexedMarkdownRepository(projectRoot: root.string)
      let created = try await create(repository)
      let file = (root + created.path.rawValue).string
      await repository.setMutationCheckpoint { point in
        if point == boundary { try "# Book\nExternal change".write(toFile: file, atomically: true, encoding: .utf8) }
      }
      do {
        let result = try await repository.mutate(resource: "books", identity: "dune", path: nil,
          request: request(.patch, #"{"frontmatter":{"set":{"title":"Changed"}}}"#),
          revision: created.revision, idempotencyKey: nil)
        #expect(boundary == .published)
        #expect(result.state == .recoveryRequired)
        #expect(result.committed)
      } catch let error as MarkdownMutationError {
        #expect(boundary == .prepared)
        #expect(error.status == 412)
      }
      #expect(try String(contentsOfFile: file, encoding: .utf8) == "# Book\nExternal change")
    }
  }

  @Test func cancelledLeaseWaitDoesNotStealOwnership() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let url = URL(fileURLWithPath: root.string)
    let lease = try await CollectionWriterLease.acquire(root: url)
    defer { withExtendedLifetime(lease) {} }
    let waiting = Task { try await CollectionWriterLease.acquire(root: url) }
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
  }

  @Test func completedRetentionExpiresButPendingIntentDoesNot() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    var completed = try await create(repository)
    completed.completedAt = Date(timeIntervalSince1970: 0)
    let url = URL(fileURLWithPath: (root + ".md-utils/mutations/\(completed.id).json").string)
    try JSONEncoder().encode(completed).write(to: url)
    let next = try await create(repository, title: "Another")
    #expect(next.id != completed.id)
    await repository.setMutationCheckpoint { if $0 == .committed { throw CancellationError() } }
    var pending = try await create(repository, title: "Pending", key: "pending")
    pending.completedAt = Date(timeIntervalSince1970: 0)
    try JSONEncoder().encode(pending).write(to: URL(fileURLWithPath: (root + ".md-utils/mutations/\(pending.id).json").string))
    #expect(try await create(repository, title: "Pending", key: "pending").id == pending.id)
  }

  @Test func serverUniquenessDoesNotRequireOtherResourceFields() async throws {
    let root = try fixture(); defer { try? root.delete() }
    let rules = root + ".md-utils/md-utils.json"
    try rules.write(rules.read(.utf8).replacingOccurrences(of: "\"rules\":[", with:
      "\"rules\":[{\"name\":\"catalog\",\"match\":{\"paths\":[\"catalog/**\"]},\"checks\":[{\"type\":\"requiredHeading\",\"heading\":\"Catalog\"}]},"))
    let config = root + ".md-utils/server/server.yaml"
    try config.write(config.read(.utf8) + """

        - name: catalog
          route: /catalog
          operations: [get]
          selection: {mode: rule, rule: catalog}
          identityPolicy: {source: logicalPath}
          lookups:
            - {name: isbn, source: frontmatter, path: [isbn], format: string}
          constraints:
            - {lookup: isbn, uniqueWithin: server, requireValue: true}

      """)
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    #expect(try await create(repository).state == .completed)
    try (root + "hidden/").mkpath()
    try (root + "hidden/broken.md").write("---\nuuid: [broken\n---\n")
    await #expect(throws: (any Error).self) { try await create(repository, title: "Another", key: "another") }
    #expect(!(root + "books/Another.md").exists)
  }
}
