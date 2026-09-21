import Testing
@testable import MarkdownUtilitiesCore

@Suite("Resource mutation validation")
struct ResourceMutationValidatorTests {
  private func definition(_ name: String, heading: String) -> MarkdownTypeDefinition {
    MarkdownTypeDefinition(name: .init(rawValue: name), version: "1",
      frontmatter: .init(presence: .required, schemas: [.inline(.object([
        "type": .string("object"), "required": .array([.string("title")])
      ]))]), body: .init(requirements: [.init(id: "heading", predicate: .heading(.init(text: heading)))]))
  }

  private func validator() throws -> ResourceMutationValidator {
    let types = try MarkdownTypeRegistry(definitions: [definition("books", heading: "Book"),
      definition("stories", heading: "Story"), definition("publishable", heading: "Story"),
      definition("already-invalid", heading: "Missing")])
    let rules = try MarkdownRuleCompiler(typeRegistry: types).compile([
      .init(name: "stories-rule", checks: [.init(id: "story", predicate: .typeConformance(.init(rawValue: "stories")))]),
      .init(name: "stories-selection", applicability: .init(allTypes: [.init(rawValue: "stories")])),
      .init(name: "already-invalid-rule", checks: [.init(id: "missing", predicate: .typeConformance(.init(rawValue: "already-invalid")))])
    ])
    return ResourceMutationValidator(types: types, rules: rules)
  }

  private func proposal(_ edit: ResourceEdit) throws -> ResourceMutationProposal {
    let record = MarkdownRecord(identity: .init(rawValue: "17"),
      content: "---\ntitle: Original\n---\n# Book\n# Story\n",
      context: .init(path: try MarkdownRecordPath("books/17.md")), revision: .init(rawValue: "revision"))
    let source = try ResourceMutationSource(record: record, expectedRevision: .init(rawValue: "revision"))
    return try MarkdownResourceCodec(configuration: .init(frontmatterFields: ["title"], bodyWritable: true))
      .plan(edit, source: source)
  }

  @Test
  func `default preserves exposed unexposed types and rules while override reports losses`() async throws {
    let mutation = try proposal(.patch(frontmatter: [:], body: "# Book\n"))
    let destination = ResourceMutationRequirements(type: .init(rawValue: "books"))
    let strict = try await validator().validate(mutation, destination: destination)
    #expect(!strict.isValid)
    #expect(Set(strict.lostConformance.map(\.name)) == ["stories", "publishable", "stories-rule", "stories-selection"])
    #expect(Set(strict.lostMembership.map(\.name)) == ["stories", "publishable", "stories-selection"])
    let override = try await validator().validate(mutation, destination: destination, policy: .endpointOnly)
    #expect(override.isValid)
    #expect(override.lostConformance == strict.lostConformance)
    #expect(override.proposal.record.revision == nil)
    #expect(override.proposal.baselineRevision?.rawValue == "revision")
  }

  @Test
  func `preexisting failures do not block valid changes`() async throws {
    let mutation = try proposal(.patch(frontmatter: ["title": .set(.string("New"))], body: nil))
    let result = try await validator().validate(mutation, destination: .init(type: .init(rawValue: "books")))
    #expect(result.isValid)
    #expect(result.lostConformance.isEmpty)
  }

  @Test
  func `replace omission and explicit removal of required field fail but patch omission succeeds`() async throws {
    for edit in [ResourceEdit.replace(frontmatter: [:], body: "# Book\n# Story\n"),
                 .patch(frontmatter: ["title": .remove], body: nil)] {
      let result = try await validator().validate(proposal(edit), destination: .init(type: .init(rawValue: "books")))
      #expect(!result.isValid)
      #expect(result.diagnostics.contains { $0.domain == .frontmatter })
    }
    let result = try await validator().validate(proposal(.patch(frontmatter: [:], body: nil)),
      destination: .init(type: .init(rawValue: "books")))
    #expect(result.isValid)
  }

  @Test
  func `endpoint only still enforces destination rule type and search root`() async throws {
    let mutation = try proposal(.patch(frontmatter: [:], body: "# Book\n"))
    for destination in [ResourceMutationRequirements(rule: "stories-rule"),
                        .init(type: .init(rawValue: "stories")),
                        .init(type: .init(rawValue: "books"), searchRoot: "other/")] {
      let result = try await validator().validate(mutation, destination: destination, policy: .endpointOnly)
      #expect(!result.isValid)
    }
  }

  @Test
  func `creation validates destination without demanding unrelated types`() async throws {
    let created = try ResourceMutationProposal(created: MarkdownRecord(identity: .init(rawValue: "new"),
      content: "---\ntitle: New\n---\n# Book\n"))
    let result = try await validator().validate(created, destination: .init(type: .init(rawValue: "books")))
    #expect(result.isValid)
    #expect(result.lostConformance.isEmpty)
  }

  @Test
  func `missing evaluation context is a failure rather than a weakened baseline`() async throws {
    let type = MarkdownTypeDefinition(name: .init(rawValue: "path-type"), version: "1",
      context: .init(requirements: [.init(id: "path", predicate: .path(.init(glob: "books/**")))]))
    let types = try MarkdownTypeRegistry(definitions: [type])
    let validator = ResourceMutationValidator(types: types, rules: try MarkdownRuleCompiler(typeRegistry: types).compile([]))
    let created = try ResourceMutationProposal(created: MarkdownRecord(identity: .init(rawValue: "new"), content: "Body"))
    let result = try await validator.validate(created, destination: .init(type: type.name))
    #expect(!result.isValid)
    #expect(result.diagnostics.contains { $0.code == "context.path.unavailable" })
  }

  @Test
  func `repair proposals retain safety classifications and are never applied`() async throws {
    let mutation = try proposal(.patch(frontmatter: [:], body: "No required headings."))
    let result = try await validator().validate(mutation,
      destination: .init(type: .init(rawValue: "books")), policy: .endpointOnly)
    #expect(!result.isValid)
    #expect(result.diagnostics.flatMap(\.fixIts).contains { $0.safety == .automatic })
    #expect(try MarkdownDocument(content: result.proposal.record.content).body == "No required headings.")
  }

  @Test
  func `mismatched rule and type registries cannot weaken validation`() async throws {
    let original = try validator()
    let different = try MarkdownTypeRegistry(definitions: [])
    let mixed = ResourceMutationValidator(types: original.types,
      rules: try MarkdownRuleCompiler(typeRegistry: different).compile([]))
    let mutation = try proposal(.patch(frontmatter: [:], body: nil))
    await #expect(throws: ResourceCodecError.self) {
      try await mixed.validate(mutation, destination: .init(type: .init(rawValue: "books")))
    }
  }
}
