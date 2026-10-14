import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("Named frontmatter relationship contracts")
struct MarkdownRelationshipTests {
  private func registry(_ relation: MarkdownRelationshipDefinition? = nil, requiredName: Bool = false) throws -> MarkdownTypeRegistry {
    var relation = relation ?? .init(select: [.key("related"), .each], target: "person.mdtype.yaml")
    if requiredName { relation.minimum = 1 }
    let schema: JSONValue = .object(["type": .string("object"), "required": .array([.string("name")])])
    let definition = MarkdownTypeDefinition(typeSchemaVersion: "2", name: .init(rawValue: "Person"), version: "1",
      frontmatter: requiredName ? .init(schemas: [.inline(schema)]) : .init(),
      requires: ["document-relationships"], relationships: ["friends": relation])
    return try .init(definitions: [definition], typeResourceBindings: ["person.mdtype.yaml": definition.name])
  }

  private func record(_ path: String, _ frontmatter: String) throws -> MarkdownRecord {
    .init(identity: .init(rawValue: path), content: "---\n\(frontmatter)\n---\n",
      context: .init(path: try MarkdownRecordPath(path)), revision: .init(rawValue: frontmatter))
  }

  private func collection(_ records: [MarkdownRecord], complete: Bool = true, paths: Set<String>? = nil) -> MarkdownRelationshipCollection {
    let entries = Dictionary(uniqueKeysWithValues: records.compactMap { record in record.context.path.map { ($0.rawValue, record) } })
    return .init(identity: "test", generation: "1", records: entries, paths: paths ?? Set(entries.keys),
      sourcesComplete: complete, candidatesComplete: complete)
  }

  @Test func `cycles converge and propagate structural failures`() async throws {
    let types = try registry(requiredName: true)
    let a = try record("A.md", "name: A\nrelated: ['[[B]]']")
    let b = try record("B.md", "name: B\nrelated: ['[[A]]']")
    let evaluator = MarkdownRelationshipEvaluator(registry: types)
    let pass = try await evaluator.evaluate(roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    #expect(pass.assessments.count == 2)
    #expect(pass.assessments.allSatisfy { $0.outcome == .pass })
    let invalid = try record("B.md", "related: ['[[A]]']")
    let fail = try await evaluator.evaluate(roots: [(a, .init(rawValue: "Person"))], collection: collection([a, invalid]))
    #expect(fail.assessments.allSatisfy { $0.outcome == .fail })
    #expect(fail.occurrences.contains { $0.diagnostics.contains { $0.code == "relationship.target.nonconformance" } })
  }

  @Test func `duplicate destinations fail even when target representation is unavailable`() async throws {
    var relation = MarkdownRelationshipDefinition(select: [.key("related"), .each], target: "person.mdtype.yaml")
    relation.forbidDuplicates = true
    let types = try registry(relation)
    let a = try record("A.md", "related: ['[[file.pdf]]', '[[file.pdf|alias]]']")
    let result = try await MarkdownRelationshipEvaluator(registry: types).evaluate(roots: [(a, .init(rawValue: "Person"))],
      collection: collection([a], paths: ["A.md", "file.pdf"]))
    #expect(result.assessment(source: "A.md", type: "Person")?.outcome == .fail)
    #expect(result.occurrences.last?.diagnostics.contains { $0.code == "relationship.target.duplicate" } == true)
  }

  @Test func `native temporal selected values retain kind evidence`() async throws {
    let a = try record("A.md", "related: [2026-10-13]")
    let result = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(roots: [(a, .init(rawValue: "Person"))], collection: collection([a]))
    #expect(result.occurrences.first?.nativeTemporal == true)
    #expect(result.occurrences.first?.outcome == .fail)
    #expect(result.occurrences.first?.diagnostics.first?.reason == "native-kind")
  }

  @Test func `malformed selected values and every index remain visible`() async throws {
    let a = try record("A.md", "related: ['[[B]]', 'See [[B]]', 42, null]")
    let b = try record("B.md", "name: B")
    let result = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    let values = result.occurrences.filter { $0.source == "A.md" }
    #expect(values.count == 4)
    #expect(values[0].outcome == .pass)
    #expect(values.dropFirst().allSatisfy { $0.outcome == .fail })
    #expect(values[2].propertyPath == [.key("related"), .index(2)])
    #expect(values[2].value == .integer(42))
  }

  @Test func `nested literal paths missing branches and shape failures`() async throws {
    let relation = MarkdownRelationshipDefinition(select: [.key("a.b/c"), .each, .key("person")], target: "person.mdtype.yaml")
    let a = try record("A.md", "'a.b/c': [{person: '[[B]]'}, {}, 42]")
    let b = try record("B.md", "name: B")
    let result = try await MarkdownRelationshipEvaluator(registry: registry(relation)).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    #expect(result.occurrences.count == 1)
    #expect(result.occurrences[0].propertyPath == [.key("a.b/c"), .index(0), .key("person")])
    #expect(result.assessment(source: "A.md", type: "Person")?.outcome == .fail)
    #expect(result.assessment(source: "A.md", type: "Person")?.diagnostics.contains { $0.code == "relationship.selection.shape" } == true)
  }

  @Test(arguments: [0, 1, 2]) func `partial coverage never proves zero or one candidates unique`(_ arguments: Int) async throws {
    let a = try record("A.md", "related: ['[[B]]']")
    var paths: Set<String> = ["A.md"]
    if arguments > 0 { paths.insert("B.md") }
    if arguments > 1 { paths.insert("other/B.md") }
    let result = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a], complete: false, paths: paths))
    #expect(result.occurrences[0].resolution?.status == (arguments > 1 ? .ambiguous : .unavailable))
    #expect(result.assessments[0].outcome == (arguments > 1 ? .fail : .unavailable))
  }

  @Test func `missing context differs from unresolved and optional absence`() async throws {
    let a = try record("A.md", "related: ['[[Missing]]']")
    let checker = MarkdownTypeChecker(registry: try registry())
    let absent = try await checker.assess(a, as: "Person")
    #expect(absent.outcome == .unavailable)
    #expect(absent.conforms == false)
    let unresolved = try await checker.assess(a, as: .init(rawValue: "Person"), collection: collection([a]))
    #expect(unresolved.outcome == .fail)
    let optional = try await checker.assess(record("A.md", "name: A"), as: "Person")
    #expect(optional.outcome == .pass)
  }

  @Test func `null removal precedes counts and duplicate identity ignores aliases`() async throws {
    var relation = MarkdownRelationshipDefinition(select: [.key("related"), .each], target: "person.mdtype.yaml")
    relation.ignoreNulls = true
    relation.forbidDuplicates = true
    relation.maximum = 2
    let a = try record("A.md", "related: [null, '[[B|one]]', '[[B#Heading|two]]']")
    let b = try record("B.md", "name: B")
    let result = try await MarkdownRelationshipEvaluator(registry: registry(relation)).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    #expect(result.occurrences.count == 2)
    #expect(result.occurrences[1].diagnostics.contains { $0.code == "relationship.target.duplicate" })
    #expect(result.assessments.flatMap(\.diagnostics).contains { $0.code == "relationship.cardinality" } == false)
  }

  @Test func `anchors and embeds retain resolved edges while restrictions fail`() async throws {
    var relation = MarkdownRelationshipDefinition(select: [.key("related"), .each], target: "person.mdtype.yaml")
    relation.forbidAnchors = true
    relation.forbidEmbeds = true
    let a = try record("A.md", "related: ['![[#Heading]]']")
    let result = try await MarkdownRelationshipEvaluator(registry: registry(relation)).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a]))
    let query = MarkdownRelationshipQuery(evaluation: result, source: "A.md", direction: .both, type: "Person")
    #expect(query.selfLinks.count == 1)
    #expect(query.incoming.isEmpty && query.outgoing.isEmpty)
    #expect(query.selfLinks[0].outcome == .fail)
    #expect(query.selfLinks[0].resolution?.destination == "A.md")
  }

  @Test func `incoming retains asserting property but excludes ambiguous candidates`() async throws {
    let a = try record("A.md", "related: ['[[B]]', '[[B.md|alias]]']")
    let b = try record("B.md", "name: B")
    let result = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    let query = MarkdownRelationshipQuery(evaluation: result, source: "B.md", direction: .incoming, type: "Person")
    #expect(query.incoming.count == 2)
    #expect(query.incoming[1].propertyPath == [.key("related"), .index(1)])
    let ambiguous = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b], paths: ["A.md", "B.md", "other/B.md"]))
    #expect(MarkdownRelationshipQuery(evaluation: ambiguous, source: "B.md", direction: .incoming, type: "Person").incoming.isEmpty)
  }

  @Test func `advisories never become required recursive obligations`() async throws {
    var relation = MarkdownRelationshipDefinition(select: [.key("related"), .each], target: "person.mdtype.yaml")
    relation.severity = .advisory
    let a = try record("A.md", "related: ['[[B]]']")
    let b = try record("B.md", "related: ['[[Missing]]']")
    let result = try await MarkdownRelationshipEvaluator(registry: registry(relation)).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    #expect(result.assessments.allSatisfy { $0.outcome == .pass })
    #expect(result.occurrences.count == 1)
  }

  @Test func `graph budget leaves an unavailable obligation`() async throws {
    let a = try record("A.md", "related: ['[[B]]']")
    let b = try record("B.md", "related: ['[[A]]']")
    var limits = MarkdownRelationshipLimits()
    limits.nodes = 1
    let result = try await MarkdownRelationshipEvaluator(registry: registry(), limits: limits).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b]))
    #expect(result.assessments[0].outcome == .unavailable)
    #expect(result.occurrences[0].diagnostics.contains { $0.code == "relationship.limit.exceeded" })
  }

  @Test func `declarations reject malformed gates shapes targets and unknown fields`() throws {
    let base = """
    {"md-utils-type-schema":"2","name":"Person","version":"1","frontmatter":{},
    "body":{"requirements":[],"recommendations":[]},"context":{"requirements":[],"recommendations":[]},
    "requires":["document-relationships"],"relationships":{"friends":RELATION}}
    """
    for invalid in ["{}", "{\"select\":[{\"each\":false}],\"target\":{\"type\":\"person.mdtype.yaml\"}}",
      "{\"select\":[\"related\"],\"target\":{\"type\":\"../person.mdtype.yaml\"}}",
      "{\"select\":[\"related\"],\"target\":{\"type\":\"person.mdtype.yaml\"},\"cardinality\":{\"min\":true}}",
    ] {
      #expect(throws: (any Error).self) { try MarkdownTypeDefinitionDecoder.decode(base.replacingOccurrences(of: "RELATION", with: invalid), format: .json) }
    }
    let relation = "{\"select\":[\"related\"],\"target\":{\"type\":\"person.mdtype.yaml\"}}"
    let valid = base.replacingOccurrences(of: "RELATION", with: relation)
    let definition = try MarkdownTypeDefinitionDecoder.decode(valid, format: .json)
    #expect(definition.relationships["friends"]?.select == [.key("related")])
    let duplicate = valid.replacingOccurrences(of: "\"friends\":" + relation, with: "\"friends\":" + relation + ",\"friends\":" + relation)
    #expect(throws: (any Error).self) { try MarkdownTypeDefinitionDecoder.decode(duplicate, format: .json) }
    #expect(throws: (any Error).self) { try MarkdownTypeDefinitionDecoder.decode(valid.replacingOccurrences(of: "\"document-relationships\"", with: "\"wikilink-constraints\""), format: .json) }
  }

  @Test func `exact coverage permits narrow resolution and self anchors need membership`() {
    let resolver = CollectionWikilinkResolver(paths: ["People/B.md"], namespaceComplete: false,
      completeExactPaths: ["People/B.md", "People/B.markdown"])
    #expect(resolver.resolve(target: "People/B", from: "A.md").status == .resolved)
    #expect(resolver.resolve(target: "B", from: "A.md").status == .unavailable)
    #expect(resolver.resolve(target: "", from: "A.md").status == .unavailable)
    #expect(resolver.resolve(target: "Elsewhere/B", from: "A.md").candidates.isEmpty)
  }

  @Test func `unavailable dependencies propagate through cycles and do not erase failures`() async throws {
    let a = try record("A.md", "name: A\nrelated: ['[[B]]']")
    let b = try record("B.md", "name: B\nrelated: ['[[A]]', '[[C]]']")
    let evaluator = MarkdownRelationshipEvaluator(registry: try registry(requiredName: true))
    let result = try await evaluator.evaluate(roots: [(a, .init(rawValue: "Person"))],
      collection: collection([a, b], paths: ["A.md", "B.md", "C.md"]))
    #expect(result.assessments.allSatisfy { $0.outcome == .unavailable })
    let invalid = try record("B.md", "related: ['[[A]]', '[[C]]']")
    let failed = try await evaluator.evaluate(roots: [(a, .init(rawValue: "Person"))],
      collection: collection([a, invalid], paths: ["A.md", "B.md", "C.md"]))
    #expect(failed.assessments.allSatisfy { $0.outcome == .fail })
    #expect(failed.occurrences.contains { $0.diagnostics.contains { $0.code == "relationship.context.unavailable" } })
  }

  @Test func `malformed frontmatter is unavailable instead of vacuous success`() async throws {
    let a = try record("A.md", "related: [")
    let result = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a]))
    #expect(result.assessments[0].outcome == .unavailable)
    #expect(result.assessments[0].diagnostics.contains { $0.code == "record.frontmatter.invalid-yaml" })
  }

  @Test func `occurrence and diagnostic limits cannot produce passing truncation`() async throws {
    let a = try record("A.md", "related: ['[[#A]]', '[[Missing]]']")
    var limits = MarkdownRelationshipLimits()
    limits.occurrences = 1
    limits.diagnostics = 1
    let result = try await MarkdownRelationshipEvaluator(registry: registry(), limits: limits).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a]))
    #expect(result.occurrences.count == 1)
    #expect(result.assessments[0].outcome == .unavailable)
    #expect(result.diagnosticsTruncated)
  }

  @Test func `TOML values use whole scalar parsing and preserve decoded ranges`() async throws {
    let a = MarkdownRecord(identity: .init(rawValue: "A.md"), content: "+++\nrelated = [\"[[#Heading|é]]\"]\n+++\n",
      context: .init(path: try MarkdownRecordPath("A.md")), revision: .init(rawValue: "1"))
    let result = try await MarkdownRelationshipEvaluator(registry: registry()).evaluate(
      roots: [(a, .init(rawValue: "Person"))], collection: collection([a]))
    let occurrence = try #require(result.occurrences.first)
    #expect(occurrence.value == .string("[[#Heading|é]]"))
    #expect(occurrence.decodedUTF8Range == 0..<"[[#Heading|é]]".utf8.count)
    #expect(occurrence.sourceUTF8Range == nil)
    #expect(occurrence.outcome == .pass)
  }

  @Test func `cancellation aborts without returning a completed graph`() async throws {
    let a = try record("A.md", "related: ['[[#A]]']")
    let evaluator = MarkdownRelationshipEvaluator(registry: try registry())
    await #expect(throws: CancellationError.self) {
      try await withThrowingTaskGroup(of: MarkdownRelationshipEvaluation.self) { group in
        group.addTask {
          while !Task.isCancelled { await Task.yield() }
          return try await evaluator.evaluate(roots: [(a, .init(rawValue: "Person"))])
        }
        group.cancelAll()
        _ = try await group.next()
      }
    }
  }

  @Test func `a thousand node cycle converges independently of discovery order`() async throws {
    let records = try (0..<1_000).map { index in
      try record("N\(index).md", "related: ['[[N\((index + 1) % 1_000)]]']")
    }
    let first = try #require(records.first)
    let evaluator = MarkdownRelationshipEvaluator(registry: try registry())
    let result = try await evaluator.evaluate(roots: [(first, .init(rawValue: "Person"))], collection: collection(records))
    #expect(result.assessments.count == 1_000)
    #expect(result.assessments.allSatisfy { $0.outcome == .pass })
    let reverse = try await evaluator.evaluate(roots: [(first, .init(rawValue: "Person"))], collection: collection(records.reversed()))
    #expect(result.occurrences == reverse.occurrences)
    #expect(result.assessments.map(\.id) == reverse.assessments.map(\.id))
  }

  @Test func `rule negation preserves unavailable relationship evidence`() async throws {
    let types = try registry()
    let reference = MarkdownRuleTypeExpression.reference("person.mdtype.yaml")
    for expression in [MarkdownRuleTypeExpression.not(reference), .oneOf([reference, .not(reference)])] {
      let rule = MarkdownRuleDefinition(name: "test", typeExpression: expression,
        typeBindings: ["person.mdtype.yaml": .init(rawValue: "Person")])
      let checker = MarkdownRuleChecker(registry: try MarkdownRuleCompiler(typeRegistry: types).compile([rule]))
      let a = try record("A.md", "related: ['[[B]]']")
      let result = try await checker.assess(a, ruleNamed: "test", collection: collection([a], complete: false))
      #expect(result.status == .failed)
      #expect(result.typeExpressionAssessment?.status == .unavailable)
    }
  }
}
