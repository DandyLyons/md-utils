import Foundation
import MarkdownUtilitiesCore
import Testing

struct MarkdownRelationshipFixTests {
  @Test func `array return appends without replacing existing assertions`() async throws {
    let (planner, collection) = try environment([
      "Alice.md": "spouse: ['[[Bob]]']", "Bob.md": "spouse: ['[[Carol]]']", "Carol.md": "spouse: ['[[Bob]]']",
    ], array: true)
    let suggestions = try await planner.suggest(collection: collection)
    let add = try #require(suggestions.proposals.first { $0.path.rawValue == "Bob.md" && $0.changes.first?.after != nil })
    #expect(add.changes.first?.after == .array([.string("[[Carol]]"), .string("[[Alice]]")]))
    let preview = try await planner.preview(collection: collection, proposals: [add])
    #expect(preview.blockers.isEmpty)
    #expect(preview.after.outcome == .pass)
  }

  @Test func `array cardinality blocks appending beyond the declaration`() async throws {
    let (planner, collection) = try environment([
      "Alice.md": "spouse: ['[[Bob]]']", "Bob.md": "spouse: ['[[Carol]]']", "Carol.md": "spouse: ['[[Bob]]']",
    ], array: true, maximum: 1)
    let suggestions = try await planner.suggest(collection: collection)
    #expect(suggestions.proposals.contains { $0.path.rawValue == "Bob.md" && $0.changes.first?.after != nil } == false)
    #expect(suggestions.diagnostics.contains { $0.code == "relationship.fix.return-unavailable" })
  }

  @Test func `required minimum blocks removing a relationship`() async throws {
    let (planner, collection) = try environment(["Alice.md": "spouse: '[[Bob]]'", "Bob.md": "name: Bob"], minimum: 1)
    let suggestions = try await planner.suggest(collection: collection)
    let remove = try #require(suggestions.proposals.first { $0.path.rawValue == "Alice.md" })
    #expect(try await planner.preview(collection: collection, proposals: [remove]).blockers.isEmpty == false)
  }

  @Test func `return spelling observes source relative semantics and declared scalar constraints`() async throws {
    let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
      "spouse": .object(["type": .string("string"), "format": .string("Wikilink/Obsidian"),
        "wikilink": .object(["styles": .array([.string("relative-path")]), "markdownExtension": .string("omit")]),
      ]),
    ])])
    let (planner, collection) = try environment([
      "People/Alice.md": "spouse: '[[./Bob]]'", "People/Bob.md": "name: Bob", "Other/Alice.md": "name: Another",
    ], schema: schema)
    let suggestions = try await planner.suggest(collection: collection)
    let add = try #require(suggestions.proposals.first { $0.path.rawValue == "People/Bob.md" })
    #expect(add.changes.first?.after == .string("[[./Alice]]"))
    #expect(try await planner.preview(collection: collection, proposals: [add]).after.outcome == .pass)
  }

  @Test func `inverse uses the declared return key rather than the originating key`() async throws {
    let reference = MarkdownPolicyRelation(type: "person.mdtype.json", name: "spouse")
    let (planner, collection) = try environment(["Alice.md": "spouse: '[[Bob]]'", "Bob.md": "name: Bob"],
      kind: .inverse(from: reference, to: .init(type: "person.mdtype.json", name: "return")),
    )
    let suggestions = try await planner.suggest(collection: collection)
    let add = try #require(suggestions.proposals.first { $0.path.rawValue == "Bob.md" })
    #expect(add.changes.first?.path == [.key("back")])
    #expect(try await planner.preview(collection: collection, proposals: [add]).after.outcome == .pass)
  }

  @Test func `cycles and self links require selected removals`() async throws {
    let reference = MarkdownPolicyRelation(type: "person.mdtype.json", name: "spouse")
    for kind in [MarkdownRelationshipPolicy.Kind.cycles([reference], .forbidden), .selfLinks([reference], forbid: true)] {
      let (planner, collection) = try environment(["Alice.md": "spouse: '[[Alice]]'"], kind: kind)
      let suggestions = try await planner.suggest(collection: collection)
      let fix = try #require(suggestions.proposals.first)
      #expect(fix.fixIt.safety == .requiresInput)
      #expect(fix.changes.first?.after == nil)
      #expect(try await planner.preview(collection: collection, proposals: [fix]).after.outcome == .pass)
    }
  }

  @Test func `advisory repairs require recommendation opt in`() async throws {
    let (planner, collection) = try environment(["Alice.md": "spouse: '[[Bob]]'", "Bob.md": "name: Bob"], severity: .advisory)
    #expect(try await planner.suggest(collection: collection).proposals.isEmpty)
    let suggestions = try await planner.suggest(collection: collection, includeRecommendations: true)
    #expect(suggestions.proposals.isEmpty == false)
    #expect(suggestions.proposals.allSatisfy { $0.diagnostic.severity == .advisory && $0.fixIt.safety == .requiresInput })
  }

  @Test func `typed occurrence edits preserve native TOML values and exact body bytes`() throws {
    let text = "+++\nwhen = 1979-05-27\nlinks = ['[[A]]', '[[B]]', '[[C]]']\ncount = 1\nflag = true\n+++\n# Body\r\n\n"
    let record = MarkdownRecord(content: text)
    let fixes = [MarkdownFixIt(id: "remove", title: "Remove selected links", safety: .requiresInput,
      edits: [.removeFrontmatterOccurrence(path: [.key("links"), .index(0)]),
        .removeFrontmatterOccurrence(path: [.key("links"), .index(2)]),],
    )]
    let result = try MarkdownTypeFixer.apply(fixes, to: record)
    let document = try MarkdownDocument(content: result.content)
    #expect(document.frontMatter["when"] == (try MarkdownDocument(content: text)).frontMatter["when"])
    #expect(document.frontMatter["links"] == .array([.string("[[B]]")]))
    #expect(document.frontMatter["count"] == .integer(1))
    #expect(document.frontMatter["flag"] == .boolean(true))
    #expect(document.body == "# Body\r\n\n")
  }

  @Test func `typed no ops preserve comments formatting and bytes`() throws {
    let source = MarkdownRecord(content: "---\n# retained\n'spouse': \"[[Bob]]\"\n---\nBody\n")
    let fix = MarkdownFixIt(id: "same", title: "Same value", safety: .requiresInput,
      edits: [.setFrontmatterOccurrence(path: [.key("spouse")], value: .string("[[Bob]]")),
        .removeFrontmatterOccurrence(path: [.key("absent")]),],
    )
    #expect(try MarkdownTypeFixer.apply([fix], to: source).content == source.content)
    let nested = MarkdownFixIt(id: "absent-nested", title: "Remove absent descendant", safety: .requiresInput,
      edits: [.removeFrontmatterOccurrence(path: [.key("missing"), .key("nested")])],
    )
    #expect(try MarkdownTypeFixer.apply([nested], to: source).content == source.content)
  }

  @Test func `literal nested keys and array indices retain occurrence identity`() throws {
    let source = MarkdownRecord(content: "---\n'a.b':\n  - spouse: '[[Bob]]'\n  - spouse: '[[Carol]]'\nuntouched: null\n---\nBody\n")
    let fix = MarkdownFixIt(id: "nested", title: "Replace occurrence", safety: .requiresInput,
      edits: [.setFrontmatterOccurrence(path: [.key("a.b"), .index(1), .key("spouse")], value: .string("[[Alice]]"))],
    )
    let output = try MarkdownDocument(content: MarkdownTypeFixer.apply([fix], to: source).content)
    #expect(output.frontMatter["a.b"] == .array([
      .object(FrontMatter(["spouse": .string("[[Bob]]")])),
      .object(FrontMatter(["spouse": .string("[[Alice]]")])),
    ]))
    #expect(output.frontMatter["untouched"] == .null)
    let invalid = MarkdownFixIt(id: "index", title: "Invalid index", safety: .requiresInput,
      edits: [.removeFrontmatterOccurrence(path: [.key("a.b"), .index(9)])],
    )
    #expect(throws: MarkdownTypeFixerError.invalidOccurrence) { try MarkdownTypeFixer.apply([invalid], to: source) }
  }

  private func environment(_ values: [String: String], array: Bool = false, minimum: Int = 0, maximum: Int? = nil,
    schema: JSONValue? = nil, kind: MarkdownRelationshipPolicy.Kind? = nil, severity: MarkdownDiagnosticSeverity = .error,
  ) throws -> (MarkdownRelationshipFixPlanner, MarkdownRelationshipCollection) {
    var relationship = MarkdownRelationshipDefinition(select: [.key("spouse")] + (array ? [.each] : []), target: "person.mdtype.json")
    relationship.minimum = minimum; relationship.maximum = maximum
    let back = MarkdownRelationshipDefinition(select: [.key("back")], target: "person.mdtype.json")
    let person = MarkdownTypeDefinition(typeSchemaVersion: "2", name: .init(rawValue: "Person"), version: "1",
      frontmatter: .init(schemas: schema.map { [.inline($0)] } ?? []),
      requires: ["document-relationships", "wikilink-constraints"], relationships: ["spouse": relationship, "return": back],
    )
    let types = try MarkdownTypeRegistry(definitions: [person], typeResourceBindings: ["person.mdtype.json": person.name])
    let policy = MarkdownRelationshipPolicy(id: "policy", scope: .reachable,
      kind: kind ?? .reciprocity(.init(type: "person.mdtype.json", name: "spouse")), severity: severity,
    )
    let registry = try MarkdownRuleCompiler(typeRegistry: types).compile([
      .init(name: "people", applicability: .init(paths: []), typeExpression: .reference("person.mdtype.json"),
        typeBindings: ["person.mdtype.json": person.name], ruleSchemaVersion: "1", relationshipPolicies: [policy],),
    ])
    let records = values.mapValues { value in MarkdownRecord(content: "---\n\(value)\n---\n", revision: .init(rawValue: value)) }
    var addressed: [String: MarkdownRecord] = [:]
    for (path, value) in records {
      var value = value; value.identity = .init(rawValue: path); value.context.path = try MarkdownRecordPath(path)
      addressed[path] = value
    }
    return (.init(registry: registry), .init(identity: "test", generation: "1", records: addressed, paths: Set(addressed.keys),
      sourcesComplete: true, candidatesComplete: true,
    ))
  }
}
