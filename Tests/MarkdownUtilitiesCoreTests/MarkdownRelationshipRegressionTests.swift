import Foundation
import Testing
@testable import MarkdownUtilitiesCore

// Regression cases from the #177 review exercise RFC coverage and provenance boundaries.
// They use small in-memory snapshots so failures isolate relationship semantics.
struct MarkdownRelationshipRegressionTests {
  private func definitions(targetHasRelationships: Bool = true) throws -> MarkdownTypeRegistry {
    let relationship = MarkdownRelationshipDefinition(select: [.key("related"), .each], target: "person.mdtype.yaml")
    let person = MarkdownTypeDefinition(typeSchemaVersion: "2", name: .init(rawValue: "Person"), version: "1",
      source: "person.mdtype.yaml",
      requires: ["document-relationships"], relationships: targetHasRelationships ? ["friends": relationship] : [:])
    let article = MarkdownTypeDefinition(typeSchemaVersion: "2", name: .init(rawValue: "Article"), version: "1",
      requires: ["document-relationships"], relationships: ["friends": relationship])
    return try .init(definitions: [person, article], typeResourceBindings: ["person.mdtype.yaml": person.name])
  }

  private func record(_ path: String, content: String, hints: [MarkdownTypeHint] = []) throws -> MarkdownRecord {
    .init(identity: .init(rawValue: path), content: content,
      context: .init(path: try MarkdownRecordPath(path), typeHints: hints), revision: .init(rawValue: content))
  }

  private func collection(_ records: [MarkdownRecord]) -> MarkdownRelationshipCollection {
    let dictionary = Dictionary(uniqueKeysWithValues: records.compactMap { record in record.context.path.map { ($0.rawValue, record) } })
    return .init(identity: "review", generation: "1", records: dictionary, paths: Set(dictionary.keys), sourcesComplete: true, candidatesComplete: true)
  }

  @Test(arguments: [false, true]) func `known ambiguity survives candidate output budget`(exhausted: Bool) async throws {
    let values = exhausted ? "['[[#Self]]', '[[B]]']" : "['[[B]]']"
    let a = try record("A.md", content: "---\nrelated: \(values)\n---\n")
    let b = try record("B.md", content: "")
    let other = try record("sub/B.md", content: "")
    var limits = MarkdownRelationshipLimits()
    limits.candidates = 1
    let result = try await MarkdownRelationshipEvaluator(registry: definitions(), limits: limits)
      .evaluate(roots: [(a, .init(rawValue: "Person"))], collection: collection([a, b, other]))
    #expect(result.occurrences.last?.resolution?.status == .ambiguous)
    #expect(result.occurrences.last?.resolution?.candidates.count == (exhausted ? 0 : 1))
    #expect(result.occurrences.last?.resolution?.namespaceComplete == false)
    #expect(result.assessment(source: "A.md", type: "Person")?.outcome == .fail)
  }

  @Test func `unsupported destination representation is unavailable`() async throws {
    let a = try record("A.md", content: "---\nrelated: ['[[./B.pdf]]']\n---\n")
    let b = try record("B.pdf", content: "%PDF-1.4")
    let result = try await MarkdownRelationshipEvaluator(registry: definitions(targetHasRelationships: false))
      .evaluate(roots: [(a, .init(rawValue: "Article"))], collection: collection([a, b]))
    #expect(result.occurrences.first?.targetOutcome == .unavailable)
    #expect(result.assessment(source: "A.md", type: "Article")?.outcome == .unavailable)
  }

  @Test func `optional absent relationships do not reject type hints`() async throws {
    let a = try record("A.md", content: "", hints: [.init(name: "Person")])
    let checker = try MarkdownTypeChecker(registry: definitions())
    #expect(try await checker.assess(a, as: "Person").outcome == .pass)
    #expect(await checker.verifyTypeHints(in: a).first?.status == .confirmed)
  }

  @Test func `type validation retains the property responsible for target failure`() async throws {
    let a = try record("A.md", content: "---\nrelated: ['[[B]]']\n---\n")
    let b = try record("B.md", content: "---\nrelated: ['not a wikilink']\n---\n")
    let checker = try MarkdownTypeChecker(registry: definitions())
    let result = try await checker.assess(a, as: "Person", collection: collection([a, b]))
    let cause = try #require(result.diagnostics.first { $0.code == "relationship.target.nonconformance" })
    #expect(cause.location == "/related/0")
    #expect(cause.schemaLocation == "#/relationships/friends")
    #expect(cause.definitionSource == "person.mdtype.yaml")
  }

  @Test func `hint verification uses supplied collection evidence`() async throws {
    let a = try record("A.md", content: "---\nrelated: ['[[B]]']\n---\n", hints: [.init(name: "Person")])
    let b = try record("B.md", content: "")
    let checker = try MarkdownTypeChecker(registry: definitions())
    let unavailable = await checker.verifyTypeHints(in: a)
    #expect(unavailable.first?.assessment?.outcome == .unavailable)
    let verified = await checker.verifyTypeHints(in: a, collection: collection([a, b]))
    #expect(verified.first?.status == .confirmed)
    #expect(verified.first?.assessment?.outcome == .pass)
  }

  @Test func `supported text representation remains assessable`() async throws {
    let a = try record("A.md", content: "---\nrelated: ['[[./B.txt]]']\n---\n")
    let b = try record("B.txt", content: "plain text")
    let result = try await MarkdownRelationshipEvaluator(registry: definitions(targetHasRelationships: false))
      .evaluate(roots: [(a, .init(rawValue: "Article"))], collection: collection([a, b]))
    #expect(result.occurrences.first?.targetOutcome == .pass)
  }

  @Test func `cancelled hint verification publishes no assessments`() async throws {
    let a = try record("A.md", content: "", hints: [.init(name: "Person")])
    let checker = try MarkdownTypeChecker(registry: definitions())
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await checker.verifyTypeHints(in: a)
    }
    let result = await task.value
    #expect(result.isEmpty)
  }
}
