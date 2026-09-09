import ArgumentParser
import MarkdownUtilitiesCore
import PathKit

extension InteractiveAuthoring {
  /// Used by both commands. New types remain in the caller's draft until final confirmation.
  func authorType(original: MarkdownTypeDefinition?, session: inout InteractiveDraftSession) throws -> String {
    var definition = original ?? MarkdownTypeDefinition(name: .init(rawValue: ""), version: "1.0.0")
    definition.name = .init(rawValue: try prompts.required("Type name", default: original?.name.rawValue))
    definition.version = try prompts.required("Contract version", default: definition.version)
    let path: Path
    if let source = original?.source { path = Path(source) }
    else {
      path = try session.resourcePath(prompts.required("Type filename relative to types/ (include .mdtype.json, .yaml, .yml, or .toml)"), types: true)
    }
    definition.source = path.string
    while true {
      let action = try prompts.choose("Type contract", ["Done", "Name and version", "Frontmatter presence", "Schema references", "Body constraints", "Context constraints"])
      switch action {
      case "Done":
        var proposed = session
        try proposed.stage(path: path, content: InteractiveDraftSession.encode(definition, path: path), creating: original == nil)
        do {
          try proposed.validate()
          session = proposed
          return String(path.string.dropFirst((session.root.string + "/.md-utils/types/").count))
        } catch { prompts.output(CLIStyle.error(error.localizedDescription)) }
      case "Name and version":
        definition.name = .init(rawValue: try prompts.required("Type name", default: definition.name.rawValue))
        definition.version = try prompts.required("Contract version", default: definition.version)
      case "Frontmatter presence":
        let value = try prompts.choose("Frontmatter presence", ["Inferred", "required", "optional"])
        definition.frontmatter.presence = MarkdownFrontmatterPresence(rawValue: value)
      case "Schema references":
        try schemas(&definition.frontmatter.schemas)
      case "Body constraints":
        try constraints(&definition.body, context: false)
      default:
        try constraints(&definition.context, context: true)
      }
    }
  }

  private func schemas(_ schemas: inout [MarkdownJSONSchemaSource]) throws {
    while true {
      let action = try prompts.choose("Existing JSON Schemas (references are relative to this type file)", ["Done", "Add reference", "Remove schema"])
      if action == "Done" { return }
      if action == "Add reference" {
        schemas.append(.reference(try prompts.required("Existing JSON Schema reference")))
      } else if schemas.isEmpty == false {
        let labels = schemas.enumerated().map { index, schema in
          switch schema {
          case .reference(let ref): return "\(index + 1): \(ref)"
          case .inline: return "\(index + 1): existing inline schema"
          }
        }
        let selected = try prompts.choose("Remove schema association", labels)
        if let index = labels.firstIndex(of: selected) { schemas.remove(at: index) }
      }
    }
  }

  private func constraints(_ group: inout MarkdownConstraintGroup, context: Bool) throws {
    while true {
      let action = try prompts.choose("Constraints", ["Done", "Add requirement", "Add recommendation", "Edit constraint", "Remove constraint"])
      if action == "Done" { return }
      if action == "Add requirement" || action == "Add recommendation" {
        let constraint = try constraint(context: context)
        if action == "Add requirement" { group.requirements.append(constraint) }
        else { group.recommendations.append(constraint) }
      } else {
        let all = group.requirements + group.recommendations
        guard all.isEmpty == false else { continue }
        let labels = all.enumerated().map { "\($0.offset + 1): \($0.element.id)" }
        let selected = try prompts.choose("Select constraint", labels)
        guard let index = labels.firstIndex(of: selected) else { continue }
        let replacement = action == "Edit constraint" ? try constraint(context: context, original: all[index]) : nil
        if index < group.requirements.count {
          if let replacement { group.requirements[index] = replacement }
          else { group.requirements.remove(at: index) }
        } else {
          let offset = index - group.requirements.count
          if let replacement { group.recommendations[offset] = replacement }
          else { group.recommendations.remove(at: offset) }
        }
      }
    }
  }

  private func constraint(context: Bool, original: MarkdownConstraint? = nil) throws -> MarkdownConstraint {
    let id = try prompts.required("Constraint ID (unique across this type)", default: original?.id)
    let kinds = context ? ["path"] : ["heading", "headingRelationship", "section", "maxBodyLines", "maxBodyWords"]
    let kind = try prompts.choose("Predicate", (original == nil ? [] : ["Keep predicate"]) + kinds)
    let predicate: MarkdownPredicate
    switch kind {
    case "Keep predicate":
      guard let original else { throw ValidationError("No existing predicate") }
      predicate = original.predicate
    case "path": predicate = .path(.init(glob: try prompts.required("Project-relative path glob")))
    case "heading": predicate = .heading(try heading())
    case "headingRelationship":
      let parent = try heading(label: "Parent heading")
      let child = try heading(label: "Child heading")
      let relationship = try prompts.choose("Relationship", ["directChild", "descendant"])
      predicate = .headingRelationship(.init(parent: parent, child: child,
        relationship: relationship == "directChild" ? .directChild : .descendant))
    case "section":
      let heading = try heading()
      let content = try prompts.choose("Section content", ["any", "nonEmpty"])
      predicate = .section(.init(heading: heading, content: content == "any" ? .any : .nonEmpty))
    case "maxBodyLines": predicate = .maxBodyLines(try prompts.number("Maximum body lines"))
    default: predicate = .maxBodyWords(try prompts.number("Maximum body words"))
    }
    return MarkdownConstraint(id: id, predicate: predicate)
  }

  private func heading(label: String = "Heading") throws -> MarkdownHeadingPredicate {
    let text = try prompts.required(label + " text")
    let level = try prompts.choose(label + " level", ["Any", "1", "2", "3", "4", "5", "6"])
    return .init(text: text, level: ["1", "2", "3", "4", "5", "6"].firstIndex(of: level).map { $0 + 1 })
  }
}
