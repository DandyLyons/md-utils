import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import MarkdownUtilitiesServer
import MarkdownUtilitiesServerNative
import PathKit
import Testing

@Suite("Indexed native server")
struct IndexedMarkdownRepositoryTests {
  @Test(arguments: [false, true])
  func `named lookups enforce global UUID scope without exposing hidden records`(fts: Bool) async throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + ".md-utils/server/server.yaml").write("""
      serverConfigVersion: "2"
      persistentIdentity:
        path: [uuid]
      resources:
        - name: books
          route: /books
          operations: [list, get]
          selection: {mode: rule, rule: books}
          identityPolicy: {source: frontmatter, path: [slug], format: string}
          lookups:
            - {name: uuid, source: persistentIdentity}
            - {name: slug, source: frontmatter, path: [slug], format: string}
            - {name: filename, source: filename}
            - {name: path, source: logicalPath}
          constraints:
            - {lookup: slug, uniqueWithin: resource}
      """)
    let uuid = "550e8400-e29b-41d4-a716-446655440000"
    try (root + "books/a.md").write("---\nuuid: \(uuid)\nslug: duplicate\n---\n# Book\nAlpha")
    try (root + "hidden/").mkpath()
    try (root + "hidden/a.md").write("---\nuuid: \(uuid)\nslug: unique\n---\nSecret content")
    if fts {
      let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
      try db.prepareCollection(root: root.string)
      try db.setBodyMode(.fts)
    }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    guard case .conflict(let conflict) = try await repository.lookup(resource: "books", lookup: "uuid", value: uuid) else {
      Issue.record("Unexposed UUID holder must participate in global conflict"); return
    }
    #expect(conflict.totalCandidates == 2)
    #expect(conflict.candidates.count == 1)
    #expect(conflict.candidates.first?.body == "# Book\nAlpha")
    #expect(try await repository.lookup(resource: "books", lookup: "path", value: "hidden/a.md") == .notFound)
    guard case .record = try await repository.lookup(resource: "books", lookup: "filename", value: "a.md") else {
      Issue.record("Filename lookup must be scoped to resource"); return
    }
    let evidence = try await repository.lookupEvidence(resource: "books", path: MarkdownRecordPath("books/a.md"))
    #expect(evidence.first(where: { $0.lookup == "uuid" })?.violatesConstraint == true)
    let page = try await repository.page(resource: "books", query: .init())
    #expect(page.records.first?.diagnostics.contains(where: { $0.code == "identity.lookup.duplicate" }) == true)

    // Unchanged projected files must still acquire new collision counts when only
    // an unexposed holder changes; reused alias rows cannot retain stale counts.
    try (root + "hidden/a.md").delete()
    try await repository.refresh()
    guard case .record = try await repository.lookup(resource: "books", lookup: "uuid", value: uuid) else {
      Issue.record("Collision should clear after refresh"); return
    }
    try (root + "books/a.md").move(root + "books/Reading Notes.md")
    try await repository.refresh()
    guard case .record(let moved) = try await repository.lookup(resource: "books", lookup: "uuid", value: uuid) else {
      Issue.record("UUID must resolve after move reconciliation"); return
    }
    #expect(moved.logicalPath?.rawValue == "books/Reading Notes.md")
    #expect(try await repository.lookup(resource: "books", lookup: "filename", value: "a.md") == .notFound)

    let router = Router()
    try MarkdownServerHTTPAdapter.register(plan: repository.plan, repository: repository, on: router)
    try await Application(router: router).test(.router) { client in
      try await client.execute(uri: "/books/by/filename/Reading%20Notes.md", method: .get) { response in
        #expect(response.status == .ok)
      }
      try await client.execute(uri: "/books/by/path?value=books%2FReading%20Notes.md", method: .get) { response in
        #expect(response.status == .ok)
      }
      try await client.execute(uri: "/books/by/path?value=hidden%2Fa.md", method: .get) { response in
        #expect(response.status == .notFound)
      }
      try await client.execute(uri: "/books/by/path?value=a&value=b", method: .get) { response in
        #expect(response.status == .badRequest)
      }
    }
  }

  @Test func `codec proposals use authoritative source identically with metadata and FTS caches`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let metadataRepository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await metadataRepository.refresh()
    let identity = MarkdownRecordIdentity(rawValue: "books/a.md")
    let metadataRecord = try await metadataRepository.record(for: identity)
    let codec = try MarkdownResourceCodec(configuration: .init(frontmatterFields: ["flag"], bodyWritable: true))
    let edit = ResourceEdit.patch(frontmatter: ["flag": .set(.boolean(false))], body: nil)
    let first = try codec.plan(edit, source: ResourceMutationSource(record: metadataRecord,
      expectedRevision: #require(metadataRecord.revision)))
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try database.setBodyMode(.fts)
    let ftsRepository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await ftsRepository.refresh()
    let ftsRecord = try await ftsRepository.record(for: identity)
    let second = try codec.plan(edit, source: ResourceMutationSource(record: ftsRecord,
      expectedRevision: #require(ftsRecord.revision)))
    #expect(first.record.content == second.record.content)
    #expect(first.baselineRevision == second.baselineRevision)
    #expect(try (root + "books/a.md").read(.utf8) == metadataRecord.content)
    try (root + "books/a.md").write("# Concurrent change")
    await #expect(throws: MarkdownServerReadError.self) {
      try await ftsRepository.record(for: identity)
    }
  }
  private func fixture(search: Bool = false) throws -> Path {
    let root = Path("tmp/indexed-server-tests/\(UUID().uuidString)/").absolute()
    try (root + ".md-utils/server/").mkpath()
    try (root + "books/").mkpath()
    try (root + ".md-utils/server/server.yaml").write("""
      serverConfigVersion: "1"
      resources:
        - name: books
          route: /books
          operations: [list, get]
          searchEnabled: \(search)
          selection:
            mode: rule
            rule: books
          identityPolicy:
            source: frontmatter
            path: [slug]
            format: string
            logicalPathFallbackEnabled: true
      """)
    try (root + ".md-utils/md-utils.json").write("""
      {"configVersion":"0.2.0","schemaDirectory":".md-utils/schemas/","rules":[
        {"name":"books","match":{"paths":["books/**"]},"checks":[{"type":"requiredHeading","heading":"Book"}]}]}
      """)
    try (root + "books/a.md").write("---\nslug: duplicate\nflag: true\nnullable: null\n---\n# Book\nAlpha")
    try (root + "books/b.md").write("---\nslug: duplicate\nflag: false\n---\n# Missing\nBeta")
    try (root + "books/c.md").write("---\nslug: unique\nflag: 'true'\n---\n# Book\nGamma")
    return root
  }

  @Test func `pages preserve bodies collisions and invalid records`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let first = try await repository.page(resource: "books", query: .init(limit: 1))
    #expect(first.records.count == 1)
    #expect(first.records.first?.body == "# Book\nAlpha")
    #expect(first.records.first?.memberships.first?.identityStatus == .duplicate)
    let cursor = try #require(first.nextCursor)
    let second = try await repository.page(resource: "books", query: .init(limit: 1, cursor: cursor))
    #expect(second.records.first?.logicalPath?.rawValue == "books/b.md")
    #expect(second.records.first?.valid == false)
    #expect(second.generation == first.generation)
    let result = try await repository.lookup(resource: "books", identity: .init(rawValue: "duplicate"))
    guard case .conflict(let conflict) = result else { Issue.record("Expected collision"); return }
    #expect(conflict.candidates.count == 2)
    let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    #expect(try db.storagePolicy().bodyMode == .metadataOnly)
    #expect(try db.serverRead { try Int.fetchOne($0, sql: "SELECT count(*) FROM documents WHERE body IS NOT NULL") } == 0)
  }

  @Test func `filters preserve types and distinguish missing from null`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let boolean = try await repository.page(resource: "books", query: .init(filter: ["flag": .boolean(true)]))
    #expect(boolean.records.map { $0.logicalPath?.rawValue } == ["books/a.md"])
    let string = try await repository.page(resource: "books", query: .init(filter: ["flag": .string("true")]))
    #expect(string.records.map { $0.logicalPath?.rawValue } == ["books/c.md"])
    let null = try await repository.page(resource: "books", query: .init(filter: ["nullable": .null]))
    #expect(null.records.map { $0.logicalPath?.rawValue } == ["books/a.md"])
  }

  @Test func `changed sources fail and refresh invalidates cursors`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let before = try await repository.page(resource: "books", query: .init(limit: 1))
    let file = root + "books/a.md"
    try file.write(try file.read(.utf8).replacingOccurrences(of: "Alpha", with: "Other"))
    await #expect(throws: MarkdownServerReadError.self) {
      try await repository.lookup(path: MarkdownRecordPath("books/a.md"))
    }
    try await repository.refresh()
    await #expect(throws: MarkdownServerReadError.self) {
      try await repository.page(resource: "books", query: .init(limit: 1, cursor: before.nextCursor))
    }
    let after = try await repository.page(resource: "books", query: .init(limit: 1))
    #expect(after.records.first?.body == "# Book\nOther")
    #expect(after.records.first?.revision != before.records.first?.revision)
    try file.delete()
    await #expect(throws: MarkdownServerReadError.sourceChanged) {
      try await repository.lookup(path: MarkdownRecordPath("books/a.md"))
    }
    try await repository.refresh()
    #expect(try await repository.lookup(path: MarkdownRecordPath("books/a.md")) == .notFound)
  }

  @Test func `external library refresh is adopted without discovery in reads`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    try (root + "books/d.md").write("# Book\nDelta")
    let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    let evaluator = try IndexProjectEvaluator(root: root, configPath: root + ".md-utils/md-utils.json")
    let indexer = try CollectionIndexer(database: db, root: URL(fileURLWithPath: root.string))
    _ = try await indexer.updateMany(fingerprint: evaluator.fingerprint, evaluate: evaluator.evaluate)
    let page = try await repository.page(resource: "books", query: .init())
    #expect(page.records.count == 4)
  }

  @Test func `configuration changes require restart`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let config = root + ".md-utils/server/server.yaml"
    try config.write(try config.read(.utf8).replacingOccurrences(of: "/books", with: "/library"))
    await #expect(throws: MarkdownServerReadError.self) {
      try await repository.page(resource: "books", query: .init())
    }
    #expect(repository.plan.resources.first?.route.rawValue == "/books")
  }

  @Test func `search requires opt in and fts`() async throws {
    let root = try fixture(search: true)
    defer { try? root.delete() }
    #expect(throws: MarkdownServerReadError.self) { try IndexedMarkdownRepository(projectRoot: root.string) }
    let db = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try db.setBodyMode(.fts)
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let page = try await repository.page(resource: "books", query: .init(search: "Alpha"))
    #expect(page.records.map { $0.logicalPath?.rawValue } == ["books/a.md"])
    await #expect(throws: MarkdownServerReadError.invalidQuery("Invalid search expression")) {
      try await repository.page(resource: "books", query: .init(search: "\"unterminated"))
    }
    let contract = try MarkdownServerOpenAPIGenerator.generate(from: repository.plan).serialized(format: .json)
    #expect(String(decoding: contract, as: UTF8.self).contains("FTS5"))
  }

  @Test func `failures keep the last publication and recover`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let before = try await repository.page(resource: "books", query: .init(limit: 1))
    let file = root + "books/c.md"
    let original = try file.read(.utf8)
    try Data([0xff, 0xfe]).write(to: URL(fileURLWithPath: file.string))
    await #expect(throws: IndexProjectError.self) { try await repository.refresh() }
    let retained = try await repository.page(resource: "books", query: .init(limit: 1))
    #expect(retained.generation == before.generation)
    #expect(await repository.isStale())
    await #expect(throws: MarkdownServerReadError.sourceChanged) {
      try await repository.lookup(path: MarkdownRecordPath("books/c.md"))
    }
    try file.write(original)
    try await repository.refresh()
    #expect(await repository.isStale() == false)
  }

  @Test func `overlapping resources match the existing projector`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let config = root + ".md-utils/server/server.yaml"
    try config.write(try config.read(.utf8) + """

        - name: library
          route: /library
          operations: [list, get]
          selection:
            mode: rule
            rule: books
          identityPolicy:
            source: logicalPath
      """)
    let legacy = try await MarkdownServerProjectLoader(projectRoot: root).load()
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let page = try await repository.page(resource: "books", query: .init())
    let expected = try #require(legacy.snapshot.resource(named: "books"))
    #expect(page.records.count == expected.records.count)
    for actual in page.records {
      let previous = try #require(expected.records.first { $0.logicalPath == actual.logicalPath })
      #expect(actual.memberships == previous.memberships)
      #expect(actual.diagnostics == previous.diagnostics)
      #expect(actual.body == previous.body)
      #expect(actual.frontmatter == previous.frontmatter)
      #expect(actual.valid == previous.valid)
    }
  }

  @Test func `readers never mix body and revision while refreshing`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let file = root + "books/a.md"
    let content = try file.read(.utf8).replacingOccurrences(of: "Alpha", with: "Changed")
    try file.write(content)
    let expectedRevision = IndexFingerprint.hash(Data(content.utf8))
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await repository.refresh() }
      for _ in 0..<20 {
        group.addTask {
          do {
            let result = try await repository.lookup(path: MarkdownRecordPath("books/a.md"))
            guard case .record(let record) = result else { Issue.record("Expected record"); return }
            #expect(record.body == "# Book\nChanged")
            #expect(record.revision?.rawValue == expectedRevision)
          } catch MarkdownServerReadError.sourceChanged { }
        }
      }
      try await group.waitForAll()
    }
  }

  @Test func `malformed frontmatter remains visible when the rule selects it`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    try (root + "books/bad.md").write("---\nkey: [unterminated\n---\n# Book")
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let page = try await repository.page(resource: "books", query: .init())
    let bad = try #require(page.records.first { $0.logicalPath?.rawValue == "books/bad.md" })
    #expect(bad.diagnostics.contains { $0.source == .parsing })
  }

  @Test func `httpparameters and error contracts agree`() async throws {
    guard #available(macOS 14.0, *) else { return }
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let router = Router()
    try MarkdownServerHTTPAdapter.register(plan: repository.plan, repository: repository, on: router)
    try await Application(router: router).test(.router) { client in
      for uri in ["/books?limit=0", "/books?valid=maybe", "/books?limit=1&limit=2", "/books?q=Alpha", "/books?filter=%7B%22x%22:%5B%5D%7D"] {
        try await client.execute(uri: uri, method: .get) { response in
          #expect(response.status == .badRequest)
        }
      }
      try await client.execute(uri: "/books?limit=1", method: .get) { response in
        #expect(response.status == .ok)
        let value = try JSONDecoder().decode(MarkdownServerReadPage.self, from: Data(response.body.readableBytesView))
        #expect(value.records.count == 1)
        #expect(value.nextCursor != nil)
      }
      try await client.execute(uri: "/books/duplicate", method: .get) { response in
        #expect(response.status == .conflict)
        let value = try JSONDecoder().decode(MarkdownServerHTTPErrorEnvelope.self, from: Data(response.body.readableBytesView))
        #expect(value.error.totalCandidates == 2)
        #expect(value.error.truncated == false)
      }
    }
  }

  @Test func `body bearing pages stop at the byte budget`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let body = "# Book\n" + String(repeating: "x", count: 5 * 1_024 * 1_024)
    for index in 0..<14 { try (root + "books/large-\(index).md").write(body) }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let first = try await repository.page(resource: "books", query: .init(limit: 1000))
    #expect(first.records.count < 17)
    #expect(first.nextCursor != nil)
    #expect(try JSONEncoder().encode(first).count <= 64 * 1_024 * 1_024)
    let second = try await repository.page(resource: "books", query: .init(limit: 1000, cursor: first.nextCursor))
    #expect(first.records.count + second.records.count == 17)
    #expect(second.nextCursor == nil)
  }

  @Test func `canonical store remains bounded and read only`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let page = try await repository.records(matching: .init(limit: 1))
    #expect(page.records.count == 1)
    let token = try #require(page.continuationToken)
    let next = try await repository.records(matching: .init(limit: 1, continuationToken: token))
    #expect(next.records.first?.context.path != page.records.first?.context.path)
    let record = try #require(page.records.first)
    await #expect(throws: RecordStoreError.unsupportedOperation) { try await repository.create(record) }
    await #expect(throws: RecordStoreError.unsupportedOperation) {
      try await repository.replace(record, ifRevision: .init(rawValue: "old"))
    }
    await #expect(throws: RecordStoreError.unsupportedOperation) {
      try await repository.delete(identity: .init(rawValue: "books/a.md"), ifRevision: .init(rawValue: "old"))
    }
  }

  @Test func `offline contracts use the saved custom project config without refreshing`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let offline = try IndexedMarkdownRepository.loadPlan(projectRoot: root.string)
    #expect(!(root + ".md-utils/index.sqlite").exists)
    let config = root + ".md-utils/md-utils.json"
    let alternate = root + "alternate.json"
    try alternate.write(try config.read(.utf8))
    try config.delete()
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    try database.prepareCollection(root: root.string)
    _ = try database.configurationPath(alternate.string)
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    #expect(repository.plan == offline.plan)
    #expect(try IndexedMarkdownRepository.loadPlan(projectRoot: root.string).plan == repository.plan)
    #expect(try database.scopes().isEmpty)
    try await repository.refresh()
    #expect(try await repository.page(resource: "books", query: .init()).records.count == 3)
  }

  @Test func `collision candidate lists declare their truncation`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let config = root + ".md-utils/server/server.yaml"
    try config.write(try config.read(.utf8)
      .replacingOccurrences(of: "serverConfigVersion: \"1\"", with: "serverConfigVersion: \"2\"")
      .replacingOccurrences(of: "    searchEnabled:", with: "    lookups: [{name: slug, source: frontmatter, path: [slug], format: string}]\n    searchEnabled:"))
    for index in 0..<1_001 {
      try (root + "books/collision-\(index).md").write("---\nslug: crowded\n---\n# Book")
    }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let result = try await repository.lookup(resource: "books", identity: .init(rawValue: "crowded"))
    guard case .conflict(let conflict) = result else { Issue.record("Expected conflict"); return }
    #expect(conflict.totalCandidates == 1_001)
    #expect(conflict.truncated)
    #expect(conflict.candidates.count <= 1_000)
    #expect(try JSONEncoder().encode(conflict).count <= 64 * 1_024 * 1_024)
    guard case .conflict(let named) = try await repository.lookup(resource: "books", lookup: "slug", value: "crowded") else {
      Issue.record("Expected named conflict"); return
    }
    #expect(named.totalCandidates == 1_001)
    #expect(named.truncated)
    #expect(named.candidates.count <= 1_000)
  }

  @Test func `atomic source replacements never return a different body under the indexed revision`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let repository = try IndexedMarkdownRepository(projectRoot: root.string)
    try await repository.refresh()
    let file = root + "books/a.md"
    let fileURL = URL(fileURLWithPath: file.string)
    let original = try file.read(.utf8)
    let changed = original.replacingOccurrences(of: "Alpha", with: "Other")
    let revision = IndexFingerprint.hash(Data(original.utf8))
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        for index in 0..<50 {
          try Data((index.isMultiple(of: 2) ? changed : original).utf8).write(to: fileURL, options: .atomic)
          try await Task.sleep(for: .milliseconds(2))
        }
      }
      for _ in 0..<10 {
        group.addTask {
          for _ in 0..<10 {
            do {
              let result = try await repository.lookup(path: MarkdownRecordPath("books/a.md"))
              guard case .record(let record) = result else { Issue.record("Expected record"); return }
              #expect(record.body == "# Book\nAlpha")
              #expect(record.revision?.rawValue == revision)
            } catch MarkdownServerReadError.sourceChanged { }
          }
        }
      }
      try await group.waitForAll()
    }
  }

  @Test func `concurrent adapters do not delete each others staged projections`() async throws {
    let root = try fixture()
    defer { try? root.delete() }
    let first = try IndexedMarkdownRepository(projectRoot: root.string)
    try await first.refresh()
    let second = try IndexedMarkdownRepository(projectRoot: root.string)
    for index in 0..<20 { try (root + "books/new-\(index).md").write("# Book\nNew") }
    let database = try SQLiteIndexDatabase(path: (root + ".md-utils/index.sqlite").string)
    let evaluator = try IndexProjectEvaluator(root: root, configPath: root + ".md-utils/md-utils.json")
    _ = try await CollectionIndexer(database: database, root: URL(fileURLWithPath: root.string))
      .updateMany(fingerprint: evaluator.fingerprint, evaluate: evaluator.evaluate)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for repository in [first, second] {
        group.addTask {
          do {
            let page = try await repository.page(resource: "books", query: .init())
            #expect([3, 23].contains(page.records.count))
          } catch is DatabaseError {
            // SQLite writer contention may explicitly reject a read; it must never
            // publish or return a partial projection generation.
          }
        }
      }
      try await group.waitForAll()
    }
    #expect(try await first.page(resource: "books", query: .init()).records.count == 23)
    #expect(try await second.page(resource: "books", query: .init()).records.count == 23)
  }
}
