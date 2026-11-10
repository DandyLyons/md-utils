import Testing
@testable import MarkdownUtilitiesCore

@Suite("Resource mutation validation")
struct ResourceMutationValidatorTests {
  private func relationshipValidator(minimum: Int = 0) throws -> ResourceMutationValidator {
    var relationship = MarkdownRelationshipDefinition(select: [.key("spouse")], target: "person.mdtype.yaml")
    relationship.minimum = minimum
    let person = MarkdownTypeDefinition(
      typeSchemaVersion: "2", name: .init(rawValue: "Person"), version: "1",
      requires: ["document-relationships"], relationships: ["spouse": relationship],
    )
    let types = try MarkdownTypeRegistry(
      definitions: [definition("books", heading: "Book"), person],
      typeResourceBindings: ["person.mdtype.yaml": person.name],
    )
    let rules = try MarkdownRuleCompiler(typeRegistry: types).compile([
      .init(name: "people", applicability: .init(allTypes: [person.name]),
        checks: [.init(id: "person", predicate: .typeConformance(person.name))],
      ),
    ])
    return ResourceMutationValidator(types: types, rules: rules)
  }

  @Test
  func `absent optional relationships allow edits and preserve type selected rules`() async throws {
    let mutation = try proposal(.patch(frontmatter: ["title": .set(.string("New"))], body: nil))
    let result = try await relationshipValidator().validate(mutation, destination: .init(rule: "people"))
    #expect(result.isValid)
    #expect(result.lostConformance.isEmpty)
    let person = try #require(result.changes.first { $0.name == "Person" })
    #expect(person.previouslyPassed && person.passes)
    let rule = try #require(result.changes.first { $0.name == "people" })
    #expect(rule.previouslySelected && rule.selected && rule.passes)
  }

  @Test
  func `required relationship cardinality still rejects the destination`() async throws {
    let mutation = try proposal(.patch(frontmatter: ["title": .set(.string("New"))], body: nil))
    let result = try await relationshipValidator(minimum: 1).validate(
      mutation, destination: .init(type: .init(rawValue: "Person")),
    )
    #expect(!result.isValid)
    #expect(result.diagnostics.contains { $0.code == "relationship.cardinality" })
  }

  @Test
  func `collection policies remain unavailable even with no local relationship values`() async throws {
    let types = try relationshipValidator().types
    let rules = try MarkdownRuleCompiler(typeRegistry: types).compile([
      .init(
        name: "reciprocal", typeBindings: ["person.mdtype.yaml": .init(rawValue: "Person")],
        ruleSchemaVersion: "1", relationshipPolicies: [
          .init(id: "spouse", scope: .selected, kind: .reciprocity(.init(type: "person.mdtype.yaml", name: "spouse"))),
        ],
      ),
    ])
    let validator = ResourceMutationValidator(types: types, rules: rules)
    let mutation = try proposal(.patch(frontmatter: ["title": .set(.string("New"))], body: nil))
    let result = try await validator.validate(mutation, destination: .init(type: .init(rawValue: "books")))
    #expect(!result.isValid)
    #expect(result.diagnostics.contains {
      $0.code == "relationship.context.unavailable" && $0.location == "relationshipPolicies"
    })
  }

  @Test(arguments: [false, true])
  func `relationship targets require evidence before and after an edit`(removing: Bool) async throws {
    let original = MarkdownRecord(
      identity: .init(rawValue: "17"),
      content: "---\ntitle: Original\n" + (removing ? "spouse: '[[Other]]'\n" : "") + "---\n# Book\n",
      context: .init(path: try MarkdownRecordPath("books/17.md")), revision: .init(rawValue: "revision"),
    )
    let source = try ResourceMutationSource(record: original, expectedRevision: .init(rawValue: "revision"))
    let mutation = try MarkdownResourceCodec(configuration: .init(frontmatterFields: ["spouse"], bodyWritable: false))
      .plan(.patch(frontmatter: ["spouse": removing ? .remove : .set(.string("[[Other]]"))], body: nil), source: source)
    for policy in [ResourceMutationValidationPolicy.preserveExistingConformance, .endpointOnly] {
      let result = try await relationshipValidator().validate(
        mutation, destination: .init(type: .init(rawValue: "books")), policy: policy,
      )
      #expect(!result.isValid)
      #expect(result.diagnostics.contains { $0.code == "relationship.context.unavailable" })
    }
  }

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
