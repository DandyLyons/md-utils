import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import Testing
@testable import md_utils

@Suite("Index JSON compatibility")
struct IndexPayloadTests {
    private func value<T: Encodable>(_ payload: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(payload))
    }

    @Test func `type payload preserves diagnostics fixes and optional field omission`() throws {
        let nested: JSONValue = .object(["null": .null, "flag": .boolean(false),
            "integer": .integer(Int.max), "decimal": .number(1.25),
            "array": .array([.string("雪/\"\n"), .integer(1)])])
        let assessment = MarkdownTypeAssessment(type: MarkdownTypeName(rawValue: "Book"), version: "1",
            diagnostics: [MarkdownDiagnostic(code: "missing", severity: .error, domain: .frontmatter,
                constraintID: "title", location: "title", message: "Needs a title",
                fixIts: [MarkdownFixIt(id: "fix", title: "Repair", safety: .requiresInput, edits: [
                    .ensureFrontmatter, .setFrontmatterValue(path: ["nested"], value: nested),
                    .requestFrontmatterValue(path: ["title"]), .appendHeading(text: "雪", level: 2)
                ])])])
        for path: String? in [nil, "notes/book.md"] {
            let payload = IndexTypePayload(assessment, path: path)
            // The old renderer is a compatibility oracle only; production index code
            // must not round-trip through these Foundation representations.
            let legacy = try JSONSerialization.data(withJSONObject: TypesRenderer.assessmentObject(assessment, path: path))
            #expect(try value(payload) == JSONDecoder().decode(JSONValue.self, from: legacy))
            let decoded = try JSONDecoder().decode(IndexTypePayload.self, from: JSONEncoder().encode(payload))
            #expect(decoded.path == path)
            #expect(decoded.diagnostics.first?.fixIts.first?.edits.count == 4)
        }
        let clean = MarkdownTypeAssessment(type: MarkdownTypeName(rawValue: "Clean"), version: "2", diagnostics: [])
        let object = try #require(value(IndexTypePayload(clean)).objectValue)
        #expect(object["path"] == nil)
        #expect(object["conforms"] == .boolean(true))
        #expect(object["diagnostics"] == .array([]))
    }

    @Test func `definition encoding preserves all predicate shapes and inline schemas`() throws {
        let heading = MarkdownHeadingPredicate(text: "Title", level: 1)
        let predicates: [MarkdownPredicate] = [.heading(heading),
            .headingRelationship(MarkdownHeadingRelationshipPredicate(parent: heading,
                child: MarkdownHeadingPredicate(text: "Child"), relationship: .descendant)),
            .section(MarkdownSectionPredicate(heading: heading, content: .nonEmpty)),
            .path(MarkdownPathPredicate(glob: "notes/**")), .maxBodyLines(10), .maxBodyWords(30)]
        let constraints = predicates.enumerated().map { MarkdownConstraint(id: String($0.offset), predicate: $0.element) }
        let definition = MarkdownTypeDefinition(name: MarkdownTypeName(rawValue: "Book"), version: "1",
            frontmatter: MarkdownFrontmatterDefinition(presence: .optional,
                schemas: [.reference("schemas/book.json"), .inline(.object(["type": .string("object")]))]),
            body: MarkdownConstraintGroup(requirements: constraints),
            context: MarkdownConstraintGroup(recommendations: constraints))
        let legacy = try JSONSerialization.data(withJSONObject: TypesRenderer.definitionObject(definition))
        #expect(try value(IndexDefinitionPayload(definition: definition)) == JSONDecoder().decode(JSONValue.self, from: legacy))
    }

    @Test func `absent rule expression remains an empty object and evidence stays typed`() throws {
        let result = MarkdownRuleAssessment(ruleName: "books", status: .notApplicable,
            evidence: [MarkdownRulePredicateEvidence(id: "path", status: .notMatched, message: "Outside notes/")])
        let object = try #require(value(IndexRulePayload(result: result)).objectValue)
        #expect(object["typeExpression"] == .object([:]))
        #expect(object["typeAssessments"] == .object([:]))
        #expect(object["evidence"] == .array([.object(["id": .string("path"),
            "status": .string("notMatched"), "message": .string("Outside notes/")])]))
    }

    @Test func `query encoding preserves integer boundaries nulls blobs and escaped text`() throws {
        let values: [IndexQueryValue] = [.integer(Int64.min), .integer(Int64.max), .null,
            .real(1.25), .text("雪/\"\n"), .blob(Data([0, 255]))]
        #expect(try value(values.map { IndexQueryJSONValue(value: $0) }) == .array([
            .integer(Int.min), .integer(Int.max), .null, .number(1.25), .string("雪/\"\n"),
            .object(["base64": .string("AP8=")])]))
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(IndexQueryJSONValue(value: .real(.infinity)))
        }
    }
}
