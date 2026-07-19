import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit
import Yams

enum TypesOutputFormat: String, ExpressibleByArgument {
  case text
  case markdown
  case json
  case yaml
}

enum TypesDefinitionFormat: String, ExpressibleByArgument {
  case yaml
  case json
}

struct TypesInitializationResult {
  var directory: Path
  var created: Bool
}

enum TypesProject {
  static let directory = ".md-utils/types/"

  static func typesDirectory(root: Path) -> Path {
    root.absolute() + Path(directory)
  }

  static func initialize(root: Path) throws -> TypesInitializationResult {
    let directory = typesDirectory(root: root)
    if directory.exists {
      guard directory.isDirectory else {
        throw ValidationError("Markdown types path is not a directory: \(directory.string)")
      }
      return TypesInitializationResult(directory: directory, created: false)
    }
    try directory.mkpath()
    return TypesInitializationResult(directory: directory, created: true)
  }

  static func initializationMessage(_ result: TypesInitializationResult) -> String {
    if result.created {
      return "Initialized Markdown types directory: \(directoryDisplayPath(result.directory))"
    }
    return ".md-utils/types/ has already been initialized."
  }

  static func createDefinition(
    name: String,
    version: String,
    format: TypesDefinitionFormat,
    root: Path,
    output: Path?
  ) throws -> Path {
    guard name.isEmpty == false else {
      throw ValidationError("Type name cannot be empty")
    }
    guard version.isEmpty == false else {
      throw ValidationError("Type version cannot be empty")
    }
    let directory = try initialize(root: root).directory
    let filename = slug(name) + ".mdtype." + format.rawValue
    let destination = output ?? (directory + filename)
    let destinationName = destination.lastComponent.lowercased()
    let allowedSuffixes = switch format {
    case .yaml:
      [".mdtype.yaml", ".mdtype.yml"]
    case .json:
      [".mdtype.json"]
    }
    guard allowedSuffixes.contains(where: destinationName.hasSuffix) else {
      let expectedSuffixes = allowedSuffixes.joined(separator: " or ")
      throw ValidationError(
        "Markdown type definition filename must end in \(expectedSuffixes)"
      )
    }
    guard destination.exists == false else {
      throw ValidationError("Refusing to overwrite existing type definition: \(destination.string)")
    }
    try destination.parent().mkpath()
    try destination.write(scaffold(name: name, version: version, format: format))
    return destination
  }

  static func load(root: Path) throws -> MarkdownTypeRegistry {
    try MarkdownTypeFileRegistryLoader.load(projectRoot: root)
  }

  static func schemaContent() throws -> String {
    guard let url = Bundle.module.url(forResource: "1_md-utils-type.schema", withExtension: "json") else {
      throw ValidationError("Bundled md-utils type-definition schema is missing")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  static func scaffold(
    name: String,
    version: String,
    format: TypesDefinitionFormat
  ) throws -> String {
    switch format {
    case .yaml:
      return """
      md-utils-type-schema: "1"
      name: \(try yamlQuoted(name))
      version: \(try yamlQuoted(version))

      frontmatter:
        schemas: []

      body:
        requirements: []
        recommendations: []

      context:
        requirements: []
        recommendations: []
      """ + "\n"
    case .json:
      let object: [String: Any] = [
        "md-utils-type-schema": "1",
        "name": name,
        "version": version,
        "frontmatter": ["schemas": []],
        "body": ["requirements": [], "recommendations": []],
        "context": ["requirements": [], "recommendations": []],
      ]
      let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
      guard let string = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode type definition")
      }
      return string + "\n"
    }
  }

  private static func slug(_ name: String) -> String {
    let lowered = name.lowercased()
    let mapped = lowered.map { character in
      character.isLetter || character.isNumber ? character : "-"
    }
    var result = String(mapped)
    while result.contains("--") {
      result = result.replacingOccurrences(of: "--", with: "-")
    }
    let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "type" : trimmed
  }

  private static func yamlQuoted(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
      throw ValidationError("Failed to encode YAML string")
    }
    return string
  }
}

struct TypeFileAssessment {
  var file: Path
  var assessment: MarkdownTypeAssessment
}

enum TypesRunner {
  static func assess(
    typeName: String,
    files: [Path],
    root: Path,
    registry: MarkdownTypeRegistry? = nil
  ) async throws -> [TypeFileAssessment] {
    let registry = try registry ?? TypesProject.load(root: root)
    let checker = MarkdownTypeChecker(registry: registry)
    return try await files.asyncMap { file in
      let record = try MarkdownRecordFileAdapter.read(file, projectRoot: root)
      let assessment = try await checker.assess(record, as: typeName)
      return TypeFileAssessment(file: file, assessment: assessment)
    }
  }

  static func identifiedTypes(
    files: [Path],
    root: Path,
    registry: MarkdownTypeRegistry? = nil
  ) async throws -> [(Path, [MarkdownTypeAssessment])] {
    let registry = try registry ?? TypesProject.load(root: root)
    let checker = MarkdownTypeChecker(registry: registry)
    return try await files.asyncMap { file in
      let record = try MarkdownRecordFileAdapter.read(file, projectRoot: root)
      return (file, await checker.assessAll(record))
    }
  }

  static func verifiedHints(
    files: [Path],
    root: Path,
    registry: MarkdownTypeRegistry? = nil
  ) async throws -> [(Path, [MarkdownTypeHintAssessment])] {
    let registry = try registry ?? TypesProject.load(root: root)
    let checker = MarkdownTypeChecker(registry: registry)
    return try await files.asyncMap { file in
      let record = try MarkdownRecordFileAdapter.read(file, projectRoot: root)
      return (file, await checker.verifyTypeHints(in: record))
    }
  }
}

enum TypesRenderer {
  static func renderDefinitions(
    _ definitions: [MarkdownTypeDefinition],
    format: TypesOutputFormat,
    root: Path
  ) throws -> String {
    switch format {
    case .text:
      guard definitions.isEmpty == false else { return "No Markdown types found." }
      return definitions.map { definition in
        let source = definition.source.map { relativePath(from: root, to: Path($0)) } ?? "in-memory"
        return "\(definition.name.rawValue)\t\(definition.version)\t\(source)"
      }.joined(separator: "\n")
    case .markdown:
      guard definitions.isEmpty == false else { return "No Markdown types found." }
      return definitions.map { "- `\($0.name.rawValue)` \($0.version)" }.joined(separator: "\n")
    case .json, .yaml:
      return try serialize(definitions.map(definitionObject), format: format)
    }
  }

  static func renderDefinition(
    _ definition: MarkdownTypeDefinition,
    format: TypesOutputFormat
  ) throws -> String {
    switch format {
    case .text:
      var lines = [
        "Type: \(definition.name.rawValue)",
        "Version: \(definition.version)",
        "Definition: \(definition.source ?? "in-memory")",
        "",
        "Frontmatter",
        "  Presence: \(definition.frontmatter.effectivePresence?.rawValue ?? "not constrained")",
        "  Schemas: \(definition.frontmatter.schemas.count)",
        "",
        "Body requirements: \(definition.body.requirements.count)",
      ]
      lines.append(contentsOf: definition.body.requirements.map { "  \($0.id): \(predicateDescription($0.predicate))" })
      lines.append("Body recommendations: \(definition.body.recommendations.count)")
      lines.append(contentsOf: definition.body.recommendations.map { "  \($0.id): \(predicateDescription($0.predicate))" })
      lines.append("Context requirements: \(definition.context.requirements.count)")
      lines.append(contentsOf: definition.context.requirements.map { "  \($0.id): \(predicateDescription($0.predicate))" })
      lines.append("Context recommendations: \(definition.context.recommendations.count)")
      lines.append(contentsOf: definition.context.recommendations.map { "  \($0.id): \(predicateDescription($0.predicate))" })
      return lines.joined(separator: "\n")
    case .markdown:
      return """
      # \(definition.name.rawValue)

      - Version: \(definition.version)
      - Frontmatter presence: \(definition.frontmatter.effectivePresence?.rawValue ?? "not constrained")
      - Frontmatter schemas: \(definition.frontmatter.schemas.count)
      - Body requirements: \(definition.body.requirements.count)
      - Body recommendations: \(definition.body.recommendations.count)
      - Context requirements: \(definition.context.requirements.count)
      - Context recommendations: \(definition.context.recommendations.count)
      """
    case .json, .yaml:
      return try serialize(definitionObject(definition), format: format)
    }
  }

  static func renderAssessments(
    _ results: [TypeFileAssessment],
    format: TypesOutputFormat,
    root: Path,
    includeOK: Bool,
    includeAdvisories: Bool = true
  ) throws -> String {
    if format == .json || format == .yaml {
      let objects = results.map { result in
        assessmentObject(result.assessment, path: relativePath(from: root, to: result.file))
      }
      return try serialize(objects, format: format)
    }
    var lines: [String] = []
    for result in results where includeOK || result.assessment.conforms == false || result.assessment.advisories.isEmpty == false {
      let path = relativePath(from: root, to: result.file)
      lines.append("\(result.assessment.type.rawValue): \(path)")
      lines.append(result.assessment.conforms ? "  CONFORMS" : "  DOES NOT CONFORM")
      for diagnostic in result.assessment.diagnostics where includeAdvisories || diagnostic.severity == .error {
        lines.append("  \(diagnostic.severity.rawValue.uppercased()) \(diagnostic.constraintID ?? diagnostic.code)")
        lines.append("    \(diagnostic.location): \(diagnostic.message)")
        for fixIt in diagnostic.fixIts {
          lines.append("    FIX [\(fixIt.safety.rawValue)] \(fixIt.title)")
        }
      }
    }
    return lines.isEmpty ? "All assessed records conform." : lines.joined(separator: "\n")
  }

  static func renderIdentified(
    _ results: [(Path, [MarkdownTypeAssessment])],
    format: TypesOutputFormat,
    root: Path,
    includeAll: Bool
  ) throws -> String {
    if format == .json || format == .yaml {
      let objects: [[String: Any]] = results.map { file, assessments in
        [
          "path": relativePath(from: root, to: file),
          "assessments": assessments.filter { includeAll || $0.conforms }.map { assessmentObject($0, path: nil) },
        ]
      }
      return try serialize(objects, format: format)
    }
    return results.map { file, assessments in
      let visible = assessments.filter { includeAll || $0.conforms }
      let names = visible.map { assessment in
        includeAll ? "\(assessment.type.rawValue): \(assessment.conforms ? "CONFORMS" : "NO")" : assessment.type.rawValue
      }
      return ([relativePath(from: root, to: file)] + names.map { "  \($0)" }).joined(separator: "\n")
    }.joined(separator: "\n")
  }

  static func renderHints(
    _ results: [(Path, [MarkdownTypeHintAssessment])],
    format: TypesOutputFormat,
    root: Path,
    includeConfirmed: Bool
  ) throws -> String {
    let objects: [[String: Any]] = results.map { file, hints in
      [
        "path": relativePath(from: root, to: file),
        "hints": hints.filter { includeConfirmed || $0.status != .confirmed }.map(hintObject),
      ]
    }
    if format == .json || format == .yaml {
      return try serialize(objects, format: format)
    }
    return results.map { file, hints in
      let visible = hints.filter { includeConfirmed || $0.status != .confirmed }
      var lines = [relativePath(from: root, to: file)]
      if hints.isEmpty {
        lines.append("  NO HINTS")
      } else {
        lines.append(contentsOf: visible.map { "  \($0.status.rawValue.uppercased()) \($0.hint.name)" })
      }
      return lines.joined(separator: "\n")
    }.joined(separator: "\n")
  }

  static func definitionObject(_ definition: MarkdownTypeDefinition) -> [String: Any] {
    var frontmatter: [String: Any] = [
      "schemas": definition.frontmatter.schemas.map { schema -> [String: Any] in
        switch schema {
        case .reference(let reference): return ["ref": reference]
        case .inline(let value): return ["inline": value.foundationValue]
        }
      }
    ]
    if let presence = definition.frontmatter.presence {
      frontmatter["presence"] = presence.rawValue
    }
    return [
      "md-utils-type-schema": definition.typeSchemaVersion,
      "name": definition.name.rawValue,
      "version": definition.version,
      "frontmatter": frontmatter,
      "body": groupObject(definition.body),
      "context": groupObject(definition.context),
    ]
  }

  static func assessmentObject(_ assessment: MarkdownTypeAssessment, path: String?) -> [String: Any] {
    var object: [String: Any] = [
      "type": ["name": assessment.type.rawValue, "version": assessment.version],
      "conforms": assessment.conforms,
      "diagnostics": assessment.diagnostics.map(diagnosticObject),
    ]
    if let path { object["path"] = path }
    return object
  }

  private static func groupObject(_ group: MarkdownConstraintGroup) -> [String: Any] {
    [
      "requirements": group.requirements.map(constraintObject),
      "recommendations": group.recommendations.map(constraintObject),
    ]
  }

  private static func constraintObject(_ constraint: MarkdownConstraint) -> [String: Any] {
    var result: [String: Any] = ["id": constraint.id]
    let pair = predicateObject(constraint.predicate)
    result[pair.0] = pair.1
    return result
  }

  private static func predicateObject(_ predicate: MarkdownPredicate) -> (String, Any) {
    switch predicate {
    case .heading(let heading):
      return ("heading", headingObject(heading))
    case .headingRelationship(let relationship):
      return ("headingRelationship", [
        "parent": headingObject(relationship.parent),
        "child": headingObject(relationship.child),
        "relationship": relationship.relationship.rawValue,
      ])
    case .section(let section):
      return ("section", ["heading": headingObject(section.heading), "content": section.content.rawValue])
    case .path(let path):
      return ("path", ["glob": path.glob])
    case .maxBodyLines(let maximum):
      return ("maxBodyLines", maximum)
    case .maxBodyWords(let maximum):
      return ("maxBodyWords", maximum)
    }
  }

  private static func headingObject(_ heading: MarkdownHeadingPredicate) -> [String: Any] {
    var object: [String: Any] = ["text": heading.text]
    if let level = heading.level { object["level"] = level }
    return object
  }

  private static func predicateDescription(_ predicate: MarkdownPredicate) -> String {
    switch predicate {
    case .heading(let heading): return "heading \"\(heading.text)\""
    case .headingRelationship(let value): return "\(value.child.text) \(value.relationship.rawValue) of \(value.parent.text)"
    case .section(let section): return "section \"\(section.heading.text)\" (\(section.content.rawValue))"
    case .path(let path): return "path matches \(path.glob)"
    case .maxBodyLines(let maximum): return "at most \(maximum) body lines"
    case .maxBodyWords(let maximum): return "at most \(maximum) body words"
    }
  }

  private static func diagnosticObject(_ diagnostic: MarkdownDiagnostic) -> [String: Any] {
    var object: [String: Any] = [
      "code": diagnostic.code,
      "severity": diagnostic.severity.rawValue,
      "domain": diagnostic.domain.rawValue,
      "location": diagnostic.location,
      "message": diagnostic.message,
      "fixIts": diagnostic.fixIts.map(fixItObject),
    ]
    if let id = diagnostic.constraintID { object["constraintID"] = id }
    return object
  }

  private static func fixItObject(_ fixIt: MarkdownFixIt) -> [String: Any] {
    [
      "id": fixIt.id,
      "title": fixIt.title,
      "safety": fixIt.safety.rawValue,
      "edits": fixIt.edits.map(editObject),
    ]
  }

  private static func editObject(_ edit: MarkdownRecordEdit) -> [String: Any] {
    switch edit {
    case .ensureFrontmatter:
      return ["kind": "ensureFrontmatter"]
    case .setFrontmatterValue(let path, let value):
      return ["kind": "setFrontmatterValue", "path": path, "value": value.foundationValue]
    case .requestFrontmatterValue(let path):
      return ["kind": "requestFrontmatterValue", "path": path]
    case .appendHeading(let text, let level):
      return ["kind": "appendHeading", "text": text, "level": level]
    }
  }

  private static func hintObject(_ hint: MarkdownTypeHintAssessment) -> [String: Any] {
    var object: [String: Any] = [
      "name": hint.hint.name,
      "status": hint.status.rawValue,
    ]
    if let version = hint.hint.version { object["version"] = version }
    if let assessment = hint.assessment { object["assessment"] = assessmentObject(assessment, path: nil) }
    return object
  }

  private static func serialize(_ object: Any, format: TypesOutputFormat) throws -> String {
    switch format {
    case .json:
      let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
      guard let string = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode JSON output")
      }
      return string
    case .yaml:
      return try Yams.dump(object: object, sortKeys: true)
    case .text, .markdown:
      throw ValidationError("Structured serialization requires json or yaml output")
    }
  }
}

extension Array {
  fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var values: [T] = []
    values.reserveCapacity(count)
    for element in self {
      values.append(try await transform(element))
    }
    return values
  }
}
