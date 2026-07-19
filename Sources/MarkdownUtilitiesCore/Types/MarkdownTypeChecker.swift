import Foundation
import JSONSchema

/// Assesses canonical Markdown records against a type registry.
public struct MarkdownTypeChecker: Sendable {
  public var registry: MarkdownTypeRegistry

  public init(registry: MarkdownTypeRegistry) {
    self.registry = registry
  }

  public func assess(
    _ record: MarkdownRecord,
    as type: MarkdownTypeName
  ) async throws -> MarkdownTypeAssessment {
    guard let definition = registry.definition(named: type) else {
      throw MarkdownTypeCheckerError.unknownType(type.rawValue)
    }
    let analyzed = await MarkdownRecordAnalyzer.analyze(record)
    return assess(analyzed, as: definition)
  }

  public func assess(
    _ record: MarkdownRecord,
    as type: String
  ) async throws -> MarkdownTypeAssessment {
    try await assess(record, as: MarkdownTypeName(rawValue: type))
  }

  public func assessAll(_ record: MarkdownRecord) async -> [MarkdownTypeAssessment] {
    let analyzed = await MarkdownRecordAnalyzer.analyze(record)
    return registry.definitions.map { assess(analyzed, as: $0) }
  }

  public func conformingTypes(for record: MarkdownRecord) async -> Set<MarkdownTypeName> {
    Set(await assessAll(record).filter(\.conforms).map(\.type))
  }

  public func verifyTypeHints(in record: MarkdownRecord) async -> [MarkdownTypeHintAssessment] {
    let analyzed = await MarkdownRecordAnalyzer.analyze(record)
    return analyzed.allTypeHints.map { hint in
      let name = MarkdownTypeName(rawValue: hint.name)
      guard let definition = registry.definition(named: name) else {
        return MarkdownTypeHintAssessment(hint: hint, status: .unknownType)
      }
      if let requestedVersion = hint.version, requestedVersion != definition.version {
        return MarkdownTypeHintAssessment(hint: hint, status: .unavailableVersion)
      }
      let assessment = assess(analyzed, as: definition)
      return MarkdownTypeHintAssessment(
        hint: hint,
        status: assessment.conforms ? .confirmed : .rejected,
        assessment: assessment
      )
    }
  }

  private func assess(
    _ record: AnalyzedMarkdownRecord,
    as definition: MarkdownTypeDefinition
  ) -> MarkdownTypeAssessment {
    var diagnostics = record.parseDiagnostics
    diagnostics.append(contentsOf: assessFrontmatter(record, definition: definition))
    diagnostics.append(contentsOf: assess(
      definition.body.requirements,
      severity: .error,
      domain: .body,
      record: record
    ))
    diagnostics.append(contentsOf: assess(
      definition.body.recommendations,
      severity: .advisory,
      domain: .body,
      record: record
    ))
    diagnostics.append(contentsOf: assess(
      definition.context.requirements,
      severity: .error,
      domain: .context,
      record: record
    ))
    diagnostics.append(contentsOf: assess(
      definition.context.recommendations,
      severity: .advisory,
      domain: .context,
      record: record
    ))
    return MarkdownTypeAssessment(
      type: definition.name,
      version: definition.version,
      diagnostics: diagnostics
    )
  }

  private func assessFrontmatter(
    _ record: AnalyzedMarkdownRecord,
    definition: MarkdownTypeDefinition
  ) -> [MarkdownDiagnostic] {
    guard record.parseDiagnostics.contains(where: { $0.domain == .frontmatter }) == false else {
      return []
    }
    if record.hasFrontmatter == false {
      guard definition.frontmatter.effectivePresence == .required else {
        return []
      }
      var diagnostics = [MarkdownDiagnostic(
        code: "frontmatter.presence.required",
        severity: .error,
        domain: .frontmatter,
        location: "frontmatter",
        message: "Frontmatter is required by type \(definition.name.rawValue)",
        fixIts: [MarkdownFixIt(
          id: "frontmatter.presence.create",
          title: "Create a frontmatter block",
          safety: .automatic,
          edits: [.ensureFrontmatter]
        )]
      )]
      diagnostics.append(contentsOf: assessSchemas(
        record.userFrontmatter ?? [:],
        definition: definition
      ))
      return diagnostics
    }

    return assessSchemas(record.userFrontmatter ?? [:], definition: definition)
  }

  private func assessSchemas(
    _ frontmatter: [String: JSONValue],
    definition: MarkdownTypeDefinition
  ) -> [MarkdownDiagnostic] {
    var diagnostics: [MarkdownDiagnostic] = []
    for (index, schemaValue) in registry.resolvedSchemas(for: definition.name).enumerated() {
      guard let schema = schemaValue.foundationValue as? [String: Any] else { continue }
      do {
        let result = try JSONSchema.validate(
          JSONValue.object(frontmatter).foundationValue,
          schema: schema
        )
        guard result.valid == false else { continue }
        for error in result.errors ?? [] {
          let missingKey = missingRequiredKey(from: error.description)
          diagnostics.append(MarkdownDiagnostic(
            code: missingKey == nil ? "frontmatter.schema.invalid" : "frontmatter.schema.required-property",
            severity: .error,
            domain: .frontmatter,
            constraintID: "frontmatter.schema[\(index)]",
            location: displayPath(error.instanceLocation.path),
            message: error.description,
            fixIts: fixItsForMissingKey(
              missingKey,
              instancePointer: error.instanceLocation.path,
              schema: schemaValue,
              schemaIndex: index,
              severity: .error
            )
          ))
        }
      } catch {
        diagnostics.append(MarkdownDiagnostic(
          code: "frontmatter.schema.engine-error",
          severity: .error,
          domain: .frontmatter,
          constraintID: "frontmatter.schema[\(index)]",
          location: "frontmatter",
          message: error.localizedDescription
        ))
      }
    }
    return diagnostics
  }

  private func assess(
    _ constraints: [MarkdownConstraint],
    severity: MarkdownDiagnosticSeverity,
    domain: MarkdownDiagnosticDomain,
    record: AnalyzedMarkdownRecord
  ) -> [MarkdownDiagnostic] {
    constraints.compactMap { constraint in
      diagnostic(for: constraint, severity: severity, domain: domain, record: record)
    }
  }

  private func diagnostic(
    for constraint: MarkdownConstraint,
    severity: MarkdownDiagnosticSeverity,
    domain: MarkdownDiagnosticDomain,
    record: AnalyzedMarkdownRecord
  ) -> MarkdownDiagnostic? {
    switch constraint.predicate {
    case .heading(let predicate):
      guard record.headings.contains(where: { matches($0, predicate) }) == false else { return nil }
      let levelDescription = predicate.level.map { " at level \($0)" } ?? ""
      return MarkdownDiagnostic(
        code: "body.heading.missing",
        severity: severity,
        domain: domain,
        constraintID: constraint.id,
        location: "body.heading",
        message: "Required heading \"\(predicate.text)\"\(levelDescription) was not found",
        fixIts: [headingFixIt(predicate, constraintID: constraint.id, severity: severity)]
      )
    case .headingRelationship(let predicate):
      guard relationshipExists(predicate, headings: record.headings) == false else { return nil }
      return MarkdownDiagnostic(
        code: "body.heading.relationship",
        severity: severity,
        domain: domain,
        constraintID: constraint.id,
        location: "body.heading",
        message: "Heading \"\(predicate.child.text)\" is not a \(predicate.relationship.rawValue) of \"\(predicate.parent.text)\""
      )
    case .section(let predicate):
      let matching = record.headings.filter { matches($0, predicate.heading) }
      let satisfies = matching.contains { heading in
        predicate.content == .any || heading.directContentIsEmpty == false
      }
      guard satisfies == false else { return nil }
      let detail = predicate.content == .nonEmpty ? "nonempty section" : "section"
      return MarkdownDiagnostic(
        code: predicate.content == .nonEmpty ? "body.section.empty-or-missing" : "body.section.missing",
        severity: severity,
        domain: domain,
        constraintID: constraint.id,
        location: "body.section",
        message: "Required \(detail) \"\(predicate.heading.text)\" was not found",
        fixIts: predicate.content == .any
          ? [headingFixIt(predicate.heading, constraintID: constraint.id, severity: severity)]
          : []
      )
    case .path(let predicate):
      guard let path = record.record.context.path else {
        return MarkdownDiagnostic(
          code: "context.path.unavailable",
          severity: severity,
          domain: domain,
          constraintID: constraint.id,
          location: "context.path",
          message: "A logical path is required to evaluate glob \"\(predicate.glob)\""
        )
      }
      guard path.matches(glob: predicate.glob) == false else { return nil }
      return MarkdownDiagnostic(
        code: "context.path.mismatch",
        severity: severity,
        domain: domain,
        constraintID: constraint.id,
        location: "context.path",
        message: "Path \"\(path.rawValue)\" does not match \"\(predicate.glob)\""
      )
    case .maxBodyLines(let maximum):
      let count = record.body.isEmpty ? 0 : record.body.components(separatedBy: "\n").count
      guard count > maximum else { return nil }
      return MarkdownDiagnostic(
        code: "body.lines.maximum",
        severity: severity,
        domain: domain,
        constraintID: constraint.id,
        location: "body.lines",
        message: "Body line count \(count) exceeds maximum \(maximum)"
      )
    case .maxBodyWords(let maximum):
      let count = record.body.split(whereSeparator: \.isWhitespace).count
      guard count > maximum else { return nil }
      return MarkdownDiagnostic(
        code: "body.words.maximum",
        severity: severity,
        domain: domain,
        constraintID: constraint.id,
        location: "body.words",
        message: "Body word count \(count) exceeds maximum \(maximum)"
      )
    }
  }

  private func matches(
    _ heading: AnalyzedMarkdownHeading,
    _ predicate: MarkdownHeadingPredicate
  ) -> Bool {
    heading.text == predicate.text && (predicate.level == nil || heading.level == predicate.level)
  }

  private func relationshipExists(
    _ predicate: MarkdownHeadingRelationshipPredicate,
    headings: [AnalyzedMarkdownHeading]
  ) -> Bool {
    for (childIndex, child) in headings.enumerated() where matches(child, predicate.child) {
      var parentIndex = child.parentIndex
      while let current = parentIndex {
        guard current >= 0, current < headings.count else { break }
        if matches(headings[current], predicate.parent) {
          return true
        }
        if predicate.relationship == .directChild {
          break
        }
        parentIndex = headings[current].parentIndex
      }
      _ = childIndex
    }
    return false
  }

  private func headingFixIt(
    _ predicate: MarkdownHeadingPredicate,
    constraintID: String,
    severity: MarkdownDiagnosticSeverity
  ) -> MarkdownFixIt {
    MarkdownFixIt(
      id: "\(constraintID).append-heading",
      title: "Append heading \"\(predicate.text)\"",
      safety: severity == .advisory ? .advisoryOnly : .automatic,
      edits: [.appendHeading(text: predicate.text, level: predicate.level ?? 2)]
    )
  }

  private func fixItsForMissingKey(
    _ key: String?,
    instancePointer: String,
    schema: JSONValue,
    schemaIndex: Int,
    severity: MarkdownDiagnosticSeverity
  ) -> [MarkdownFixIt] {
    guard let key, case .object(let schemaObject) = schema else { return [] }
    let path = jsonPointerComponents(instancePointer) + [key]
    let propertySchema: JSONValue?
    if path.count == 1, case .object(let properties)? = schemaObject["properties"] {
      propertySchema = properties[key]
    } else {
      propertySchema = nil
    }
    let constantValue: JSONValue?
    let defaultValue: JSONValue?
    if case .object(let propertyObject)? = propertySchema {
      constantValue = propertyObject["const"]
      defaultValue = propertyObject["default"]
    } else {
      constantValue = nil
      defaultValue = nil
    }
    let displayKey = path.joined(separator: ".")
    let id = "frontmatter.schema[\(schemaIndex)].add-\(displayKey)"
    if let constantValue {
      return [MarkdownFixIt(
        id: id,
        title: "Add frontmatter property \"\(displayKey)\"",
        safety: severity == .advisory ? .advisoryOnly : .automatic,
        edits: [.setFrontmatterValue(path: path, value: constantValue)]
      )]
    }
    if let defaultValue {
      return [MarkdownFixIt(
        id: id,
        title: "Add suggested default for frontmatter property \"\(displayKey)\"",
        safety: severity == .advisory ? .advisoryOnly : .requiresInput,
        edits: [.setFrontmatterValue(path: path, value: defaultValue)]
      )]
    }
    return [MarkdownFixIt(
      id: id,
      title: "Add a value for frontmatter property \"\(displayKey)\"",
      safety: .requiresInput,
      edits: [.requestFrontmatterValue(path: path)]
    )]
  }

  private func jsonPointerComponents(_ pointer: String) -> [String] {
    guard pointer.isEmpty == false, pointer != "/" else { return [] }
    let trimmed = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
    return trimmed.split(separator: "/", omittingEmptySubsequences: false).map { component in
      component.replacingOccurrences(of: "~1", with: "/")
        .replacingOccurrences(of: "~0", with: "~")
    }
  }

  private func missingRequiredKey(from description: String) -> String? {
    let prefix = "Required property '"
    let suffix = "' is missing"
    guard description.hasPrefix(prefix), description.hasSuffix(suffix) else { return nil }
    return String(description.dropFirst(prefix.count).dropLast(suffix.count))
  }

  private func displayPath(_ pointer: String) -> String {
    guard pointer.isEmpty == false, pointer != "/" else { return "frontmatter" }
    let trimmed = pointer.hasPrefix("/") ? String(pointer.dropFirst()) : pointer
    return "frontmatter." + trimmed.replacingOccurrences(of: "/", with: ".")
  }
}

/// Errors produced before a type assessment can begin.
public enum MarkdownTypeCheckerError: Error, Equatable, LocalizedError {
  case unknownType(String)

  public var errorDescription: String? {
    switch self {
    case .unknownType(let name):
      return "Markdown type not found: \(name)"
    }
  }
}
