import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex


/// Encodes type definitions for deterministic cache fingerprints.
struct IndexDefinitionPayload: Encodable {
    var definition: MarkdownTypeDefinition
    private enum CodingKeys: String, CodingKey {
        case schema = "md-utils-type-schema"
        case name, version, frontmatter, body, context
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition.typeSchemaVersion, forKey: .schema)
        try container.encode(definition.name.rawValue, forKey: .name)
        try container.encode(definition.version, forKey: .version)
        var frontmatter: [String: JSONValue] = ["schemas": .array(definition.frontmatter.schemas.map {
            switch $0 {
            case .reference(let ref): .object(["ref": .string(ref)])
            case .inline(let value): .object(["inline": value])
            }
        })]
        if let presence = definition.frontmatter.presence { frontmatter["presence"] = .string(presence.rawValue) }
        try container.encode(frontmatter, forKey: .frontmatter)
        try container.encode(Group(definition.body), forKey: .body)
        try container.encode(Group(definition.context), forKey: .context)
    }
    private struct Group: Encodable {
        var requirements: [Constraint]
        var recommendations: [Constraint]
        init(_ group: MarkdownConstraintGroup) {
            requirements = group.requirements.map(Constraint.init)
            recommendations = group.recommendations.map(Constraint.init)
        }
    }
    private struct Constraint: Encodable {
        var constraint: MarkdownConstraint
        init(_ constraint: MarkdownConstraint) { self.constraint = constraint }
        private enum CodingKeys: String, CodingKey {
            case id, heading, headingRelationship, section, path, maxBodyLines, maxBodyWords
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(constraint.id, forKey: .id)
            switch constraint.predicate {
            case .heading(let value): try container.encode(value, forKey: .heading)
            case .headingRelationship(let value): try container.encode(value, forKey: .headingRelationship)
            case .section(let value): try container.encode(value, forKey: .section)
            case .path(let value): try container.encode(value, forKey: .path)
            case .maxBodyLines(let value): try container.encode(value, forKey: .maxBodyLines)
            case .maxBodyWords(let value): try container.encode(value, forKey: .maxBodyWords)
            }
        }
    }
}

/// Stable persisted JSON shapes, independent of terminal renderers and Foundation bridging.
struct IndexTypePayload: Codable {
    struct Identity: Codable {
        var name: String
        var version: String
    }
    var type: Identity
    var conforms: Bool
    var diagnostics: [Diagnostic]
    var path: String?

    init(_ assessment: MarkdownTypeAssessment, path: String? = nil) {
        type = Identity(name: assessment.type.rawValue, version: assessment.version)
        conforms = assessment.conforms
        diagnostics = assessment.diagnostics.map(Diagnostic.init)
        self.path = path
    }

    struct Diagnostic: Codable {
        var code: String
        var severity: MarkdownDiagnosticSeverity
        var domain: MarkdownDiagnosticDomain
        var location: String
        var message: String
        var fixIts: [FixIt]
        var constraintID: String?

        init(_ diagnostic: MarkdownDiagnostic) {
            code = diagnostic.code
            severity = diagnostic.severity
            domain = diagnostic.domain
            location = diagnostic.location
            message = diagnostic.message
            fixIts = diagnostic.fixIts.map(FixIt.init)
            constraintID = diagnostic.constraintID
        }
    }

    struct FixIt: Codable {
        var id: String
        var title: String
        var safety: MarkdownFixItSafety
        var edits: [JSONValue]

        init(_ fix: MarkdownFixIt) {
            id = fix.id
            title = fix.title
            safety = fix.safety
            edits = fix.edits.map { edit in
                switch edit {
                case .ensureFrontmatter:
                    return .object(["kind": .string("ensureFrontmatter")])
                case .setFrontmatterValue(let path, let value):
                    return .object(["kind": .string("setFrontmatterValue"),
                        "path": .array(path.map(JSONValue.string)), "value": value])
                case .requestFrontmatterValue(let path):
                    return .object(["kind": .string("requestFrontmatterValue"),
                        "path": .array(path.map(JSONValue.string))])
                case .appendHeading(let text, let level):
                    return .object(["kind": .string("appendHeading"), "text": .string(text), "level": .integer(level)])
                }
            }
        }
    }
}

struct IndexExpressionPayload: Codable {
    var location: String
    var status: MarkdownRuleEvidenceStatus
    var children: [IndexExpressionPayload]
    var reference: String?
    var assessment: IndexTypePayload?

    init(_ expression: MarkdownRuleTypeExpressionAssessment) {
        location = expression.location
        status = expression.status
        children = expression.children.map(Self.init)
        reference = expression.reference
        assessment = expression.assessment.map { IndexTypePayload($0) }
    }
}

struct IndexRulePayload: Encodable {
    var result: MarkdownRuleAssessment

    private enum CodingKeys: String, CodingKey {
        case status, evidence, typeAssessments, typeExpression
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(result.status, forKey: .status)
        try container.encode(result.evidence, forKey: .evidence)
        try container.encode(result.typeAssessments.mapValues { IndexTypePayload($0) }, forKey: .typeAssessments)
        if let expression = result.typeExpressionAssessment {
            try container.encode(IndexExpressionPayload(expression), forKey: .typeExpression)
        } else {
            // Preserve the established absent-expression representation, rather than null.
            try container.encode([String: JSONValue](), forKey: .typeExpression)
        }
    }
}
