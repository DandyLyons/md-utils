import Foundation

/// Portable query planning over a bounded host snapshot. All filesystem access,
/// definition loading and certified persistent assessment reuse belong to the host.
public struct MarkdownCollectionQueryEvaluator: Sendable {
  public let types: MarkdownTypeRegistry
  public let rules: MarkdownRuleRegistry?
  public let limits: MarkdownRelationshipLimits
  public init(types: MarkdownTypeRegistry, rules: MarkdownRuleRegistry? = nil,
    limits: MarkdownRelationshipLimits = .init(),
  ) { self.types = types; self.rules = rules; self.limits = limits }

  public func evaluate(_ request: MarkdownCollectionQueryRequest, collection: MarkdownRelationshipCollection,
    evaluation: MarkdownRelationshipEvaluation,
    queryProvider: (any MarkdownRuleQueryCapabilityProvider)? = nil,
  ) async throws -> (result: MarkdownCollectionQueryResult, complete: Bool) {
    var coverage = MarkdownQueryCoverage()
    coverage.sources = collection.sourcesComplete ? "complete" : "incomplete"
    coverage.candidates = collection.resolver.namespaceComplete ? "complete" : "incomplete"
    coverage.limitations = collection.limitations
    var analyzed: [String: AnalyzedMarkdownRecord] = [:]
    var documents: [String: MarkdownDocument] = [:]
    var memberships: [String: [String: Membership]] = [:]
    var bindings: [String: [String: [MarkdownQueryApplicability]]] = [:]
    var hintLimitations: [String: [String]] = [:]
    let assessments = Dictionary(grouping: evaluation.assessments, by: \.source)
    var skipped: Set<String> = []
    var work = 0
    func outcome(_ path: String, _ name: String) -> MarkdownAssessmentOutcome {
      assessments[path]?.first(where: { $0.type == name })?.outcome ?? .unavailable
    }
    func addBinding(_ path: String, _ name: String, _ reason: MarkdownQueryApplicability) {
      guard types.definition(named: name) != nil else { return }
      if !(bindings[path]?[name]?.contains(reason) ?? false) {
        bindings[path, default: [:]][name, default: []].append(reason)
      }
    }
    for path in collection.records.keys.sorted() {
      try Task.checkCancellation()
      guard let record = collection.records[path] else { continue }
      let analysis = await MarkdownRecordAnalyzer.analyze(record)
      analyzed[path] = analysis
      documents[path] = try? MarkdownDocument(content: record.content)
      if let rules {
        var checker = MarkdownRuleChecker(registry: rules)
        for node in assessments[path] ?? [] {
          guard let definition = types.definition(named: node.type) else { continue }
          checker.relationshipAssessments[definition.name] = .init(type: definition.name,
            version: definition.version, diagnostics: node.diagnostics, outcome: node.outcome)
        }
        for rule in rules.definitions.sorted(by: { $0.name < $1.name }) {
          work += 1
          guard work <= limits.policySteps else {
            memberships[path, default: [:]][rule.name] = .unknown
            continue
          }
          let match = try checker.assessApplicability(analysis, rule: rule, outcomeBased: true)
          let member: Membership = match.unavailable ? .unknown : (match.matches ? .yes : .no)
          memberships[path, default: [:]][rule.name] = member
          guard member == .yes else { continue }
          if let expression = rule.typeExpression {
            let required = expression.unconditionalQueryReferences
            for (reference, location) in expression.positiveQueryReferences() {
              guard let name = rule.typeBindings[reference]?.rawValue else { continue }
              addBinding(path, name, .init(kind: required.contains(reference) ? "ruleRequirement" : "ruleAlternative",
                rule: rule.name, expressionLocation: location, verification: outcome(path, name)))
            }
          }
          for check in rule.checks where check.severity == .error {
            if case .typeConformance(let name) = check.predicate {
              addBinding(path, name.rawValue, .init(kind: "ruleRequirement", rule: rule.name,
                expressionLocation: check.id, verification: outcome(path, name.rawValue)))
            }
          }
        }
      }
      for definition in types.definitions where outcome(path, definition.name.rawValue) == .pass {
        addBinding(path, definition.name.rawValue, .init(kind: "conformance", verification: .pass))
      }
      for hint in analysis.allTypeHints {
        if let definition = types.definition(named: hint.name) {
          addBinding(path, hint.name, .init(kind: "typeHint", expressionLocation: "$md-utils.typeHints",
            verification: hint.version == nil || hint.version == definition.version ? outcome(path, hint.name) : .unavailable))
          if let version = hint.version, version != definition.version {
            hintLimitations[path, default: []].append("\(path): hinted type version is unavailable: \(hint.name) \(version)")
          }
        } else if request.types.isEmpty {
          hintLimitations[path, default: []].append("\(path): unknown hinted type \(hint.name)")
        }
      }
      if !request.types.isEmpty {
        bindings[path] = [:]
        for name in request.types {
          addBinding(path, name, .init(kind: "explicit", verification: outcome(path, name)))
        }
      }
    }
    if work > limits.policySteps {
      coverage.interpretations = "incomplete"
      coverage.limitations.append("Rule applicability work budget exhausted.")
    }

    func select(_ selector: MarkdownDocumentSelector, path: String) throws -> Membership {
      work += 1
      guard work <= limits.policySteps else { return .unknown }
      switch selector {
      case .files(let paths): return paths.contains(path) ? .yes : .no
      case .folder(let folder): return folder.isEmpty || path.hasPrefix(folder) ? .yes : .no
      case .type(let name):
        switch outcome(path, name) { case .pass: return .yes; case .fail: return .no; case .unavailable: return .unknown }
      case .rule(let name): return memberships[path]?[name] ?? .unknown
      case .requiredType(let name):
        if bindings[path]?[name]?.contains(where: { $0.kind == "ruleRequirement" }) == true { return .yes }
        // Explicit overrides must not affect selection by rule requirements.
        var possible = false
        for rule in rules?.definitions ?? [] {
          let refs = rule.typeExpression?.unconditionalQueryReferences ?? []
          let requires = refs.contains { rule.typeBindings[$0]?.rawValue == name }
            || rule.checks.contains { check in
              if case .typeConformance(let type) = check.predicate { return check.severity == .error && type.rawValue == name }
              return false
            }
          if requires {
            let membership = memberships[path]?[rule.name] ?? .unknown
            if membership == .yes { return .yes }
            possible = possible || membership == .unknown
          }
        }
        return possible ? .unknown : .no
      case .tag(let tag):
        guard let document = documents[path] else { return .unknown }
        guard document.frontMatterFormat == .yaml,
          case .array(let values) = document.frontMatter["tags"] else { return .no }
        return values.contains(.string(tag)) ? .yes : .no
      case .jmespath(let expression):
        guard let document = documents[path], let analysis = analyzed[path], analysis.parseDiagnostics.isEmpty else { return .unknown }
        if document.frontMatterFormat == .toml { skipped.insert(path); return .no }
        guard let queryProvider else { return .unknown }
        do {
          let value = try queryProvider.evaluateJMESPath(expression, frontmatter: .object([
            "path": .string(path), "frontmatterFormat": .string(document.frontMatterFormat?.rawValue ?? "none"),
            "frontmatter": .object(analysis.relationshipFrontmatter ?? [:]), "body": .string(document.body),
          ]))
          return truthy(value) ? .yes : .no
        } catch is CancellationError { throw CancellationError() }
        catch {
          coverage.limitations.append("\(path): JMESPath evaluation failed: \(error.localizedDescription)")
          return .unknown
        }
      }
    }
    var universe = collection.resolver.paths.filter(Self.isMarkdown)
    for selector in request.selectors {
      if case .files(let paths) = selector { universe.formUnion(paths) }
    }
    var selected: [String] = []
    for path in universe.sorted() {
      try Task.checkCancellation()
      let values = try request.selectors.map { try select($0, path: path) }
      let included = request.mode == .union ? Membership.union(values) : Membership.intersection(values)
      let excluded = Membership.union(try request.exclusions.map { try select($0, path: path) })
      let member = Membership.intersection([included, excluded.negated])
      if member == .yes {
        selected.append(path)
        if collection.records[path] == nil {
          coverage.sources = "incomplete"
          coverage.limitations.append("\(path): selected document is unavailable")
        }
      } else if member == .unknown {
        coverage.selection = "incomplete"
        coverage.limitations.append("\(path): selection membership is unknown")
      }
    }
    if !collection.resolver.namespaceComplete && request.selectors.contains(where: { if case .files = $0 { return false }; return true }) {
      coverage.selection = "incomplete"
    }
    let sourcePaths = selected.isEmpty ? [] : (request.direction == .outgoing ? selected : collection.records.keys.sorted())
    let sourceSet = Set(sourcePaths)
    for path in sourcePaths {
      if request.types.isEmpty {
        if let limitations = hintLimitations[path], !limitations.isEmpty {
          coverage.interpretations = "incomplete"
          coverage.limitations += limitations
        }
        if types.definitions.contains(where: { outcome(path, $0.name.rawValue) == .unavailable })
          || memberships[path]?.values.contains(.unknown) == true {
          coverage.interpretations = "incomplete"
          coverage.limitations.append("\(path): named applicability is incomplete")
        }
      }
      if analyzed[path]?.parseDiagnostics.isEmpty == false {
        coverage.interpretations = "incomplete"
        coverage.sources = "incomplete"
        coverage.limitations.append("\(path): document metadata could not be fully analyzed")
      }
    }
    var occurrences: [MarkdownQueryOccurrence] = []
    for path in sourcePaths {
      guard let record = collection.records[path] else { continue }
      try Task.checkCancellation()
      do {
        let scanned = try await MarkdownQueryLinks.scan(record, collection: collection, maximum: max(0, limits.occurrences - occurrences.count))
        occurrences += scanned.occurrences
        if scanned.truncated {
          coverage.sources = "incomplete"
          coverage.limitations.append("Ordinary link occurrence budget exhausted.")
          break
        }
      } catch is CancellationError { throw CancellationError() }
      catch {
        coverage.sources = "incomplete"
        coverage.limitations.append("\(path): link extraction failed: \(error.localizedDescription)")
      }
    }
    var interpretations: [MarkdownQueryInterpretation] = []
    var interpretedAssertions: [String: MarkdownRelationshipOccurrence] = [:]
    var namedIndices: Set<Int> = []
    var scalarIndices: [String: [[WikilinkPropertyComponent]: [Int]]] = [:]
    for index in occurrences.indices {
      if let path = occurrences[index].location.propertyPath {
        scalarIndices[occurrences[index].source, default: [:]][path, default: []].append(index)
      }
    }
    var selectedNodes: [MarkdownRelationshipNodeAssessment] = []
    func incompleteDiagnostic(_ diagnostic: MarkdownDiagnostic) -> Bool {
      diagnostic.code.contains("limit.exceeded") || diagnostic.code.hasSuffix(".unavailable")
        || diagnostic.code.hasSuffix(".engine-error") || diagnostic.code.hasSuffix(".schema-engine")
        || diagnostic.causes?.contains(where: incompleteDiagnostic) == true
    }
    for path in sourcePaths {
      for node in assessments[path] ?? [] where bindings[path]?[node.type] != nil {
        selectedNodes.append(node)
        if node.selectionComplete.values.contains(false) || node.outcome == .unavailable
          || node.diagnostics.contains(where: incompleteDiagnostic) {
          coverage.interpretations = "incomplete"
        }
      }
    }
    for assertion in evaluation.occurrences where sourceSet.contains(assertion.source) {
      try Task.checkCancellation()
      guard let applicability = bindings[assertion.source]?[assertion.type] else { continue }
      let location = MarkdownQueryLocation(region: "frontmatter", propertyPath: assertion.propertyPath,
        decodedUTF8Range: assertion.decodedUTF8Range, sourceUTF8Range: assertion.sourceUTF8Range)
      let index: Int
      let candidates = scalarIndices[assertion.source]?[assertion.propertyPath] ?? []
      if let existing = candidates.first(where: {
        occurrences[$0].value == assertion.value && occurrences[$0].location.decodedUTF8Range == assertion.decodedUTF8Range
      }) { index = existing }
      else {
        index = occurrences.count
        occurrences.append(.init(id: "", source: assertion.source, sourceIdentity: assertion.sourceIdentity,
          sourceRevision: assertion.sourceRevision, location: location, value: assertion.value,
          syntax: assertion.link == nil ? nil : "wikilink", resolution: assertion.resolution))
        scalarIndices[assertion.source, default: [:]][assertion.propertyPath, default: []].append(index)
      }
      namedIndices.insert(index)
      occurrences[index].link = assertion.link
      occurrences[index].nativeTemporal = assertion.nativeTemporal
      // A malformed whole-value assertion may contain recognized substrings.
      // Suppress their independent unnamed presentation, retaining all raw evidence.
      for candidate in candidates {
        namedIndices.insert(candidate)
      }
      if let relation = request.relation, assertion.relationship != relation { continue }
      let interpretationID = "r\(interpretations.count + 1)"
      interpretedAssertions[interpretationID] = assertion
      interpretations.append(.init(id: interpretationID, occurrence: "o\(index + 1)",
        applicability: applicability, assertion: .init(assertion),
        containedOccurrences: assertion.link == nil ? candidates.filter { $0 != index }.map { "o\($0 + 1)" } : []))
    }
    for index in occurrences.indices { occurrences[index].id = "o\(index + 1)" }
    var files = selected.map { MarkdownQueryFile(path: $0, named: .init(request.direction), unnamed: .init(request.direction)) }
    let fileIndices = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($0.element, $0.offset) })
    func attach(_ id: String, source: String, target: String?, named: Bool) -> Bool {
      var visible = false
      let affected = Set([fileIndices[source], target.flatMap { fileIndices[$0] }].compactMap { $0 })
      for index in affected.sorted() {
        let from = files[index].path == source
        let to = files[index].path == target
        var directions = named ? files[index].named : files[index].unnamed
        if source == target && (from || to) { directions.selfLinks.append(id); visible = true }
        else {
          if from && request.direction != .incoming { directions.outgoing?.append(id); visible = true }
          if to && request.direction != .outgoing { directions.incoming?.append(id); visible = true }
        }
        if named { files[index].named = directions } else { files[index].unnamed = directions }
      }
      return visible
    }
    var triples: [MarkdownQueryTriple] = []
    var links: [MarkdownQueryTriple] = []
    var explanations: [MarkdownQueryExplanation] = []
    var retainedNamed: [MarkdownQueryInterpretation] = []
    var retained: Set<String> = []
    var unresolved = 0
    var failed = 0
    let selectedSet = Set(selected)
    func possibleIncoming(_ resolution: CollectionWikilinkResolution?) -> Bool {
      guard request.direction != .outgoing, !selectedSet.isEmpty else { return false }
      guard let resolution else { return true }
      if resolution.status == .resolved || resolution.status == .unresolved { return false }
      return !selectedSet.isDisjoint(with: resolution.candidates) || resolution.status == .unavailable
    }
    for interpretation in interpretations {
      guard let assertion = interpretedAssertions[interpretation.id] else { continue }
      let visible = attach(interpretation.id, source: assertion.source, target: assertion.resolution?.destination, named: true)
      guard visible || possibleIncoming(assertion.resolution) else { continue }
      retainedNamed.append(interpretation)
      retained.insert(interpretation.occurrence)
      retained.formUnion(interpretation.containedOccurrences)
      let predicate = "\(assertion.type):\(assertion.relationship)"
      if let target = assertion.resolution?.destination {
        triples.append(.init(subject: assertion.source, predicate: predicate, object: target, occurrenceCount: 1))
      } else { unresolved += 1 }
      if assertion.outcome == .fail { failed += 1 }
      if assertion.outcome == .unavailable || assertion.targetOutcome == .unavailable
        || assertion.diagnostics.contains(where: incompleteDiagnostic) { coverage.interpretations = "incomplete" }
      explanations.append(.init(source: assertion.source, predicate: predicate,
        location: .init(region: "frontmatter", propertyPath: assertion.propertyPath,
          decodedUTF8Range: assertion.decodedUTF8Range, sourceUTF8Range: assertion.sourceUTF8Range),
        applicability: interpretation.applicability, outcome: assertion.outcome, diagnostics: assertion.diagnostics))
    }
    for index in occurrences.indices where !namedIndices.contains(index) {
      let occurrence = occurrences[index]
      let visible = attach(occurrence.id, source: occurrence.source, target: occurrence.resolution?.destination, named: false)
      guard visible || possibleIncoming(occurrence.resolution) else { continue }
      retained.insert(occurrence.id)
      if let target = occurrence.resolution?.destination {
        links.append(.init(subject: occurrence.source, predicate: "link", object: target, occurrenceCount: 1))
      } else { unresolved += 1 }
      if occurrence.resolution?.status == .unavailable { coverage.candidates = "incomplete" }
    }
    if selectedNodes.contains(where: { $0.diagnostics.contains(where: { $0.severity == .error }) }) { failed += 1 }
    if evaluation.diagnosticsTruncated {
      coverage.interpretations = "incomplete"
      coverage.limitations.append("Assessment diagnostics were truncated.")
    }
    coverage.limitations = Array(Set(coverage.limitations + evaluation.limitations)).sorted()
    var notices: [MarkdownQueryNotice] = []
    if !coverage.complete { notices.append(.init(code: "query.incomplete", message: "Search incomplete; more relationships may exist.", hint: "Use --detail explain.")) }
    if failed > 0 { notices.append(.init(code: "relationship.validation", message: "Relationship validation found issues.", hint: "Use --detail explain.")) }
    if unresolved > 0 { notices.append(.init(code: "relationship.unresolved", message: "\(unresolved) assertions could not be resolved.", hint: "Use --detail explain.")) }
    if !skipped.isEmpty { notices.append(.init(code: "selection.toml.skipped", message: "JMESPath skipped \(skipped.count) TOML documents.", hint: "Use --detail explain.")) }
    let detailed = request.detail != .summary
    let evidence = request.detail == .evidence
    let result = MarkdownCollectionQueryResult(detail: request.detail, direction: request.direction,
      selected: selected, relationships: grouped(triples), links: grouped(links), notices: notices,
      coverage: detailed ? coverage : nil, explanations: detailed ? explanations : nil,
      skipped: detailed ? skipped.sorted() : nil, files: evidence ? files : nil,
      occurrences: evidence ? occurrences.filter { retained.contains($0.id) } : nil,
      namedRelationships: evidence ? retainedNamed : nil,
      assessments: evidence ? evaluation.assessments : nil,
      diagnostics: detailed ? selectedNodes.flatMap { node in
        node.diagnostics.map { .init(source: node.source, type: node.type, diagnostic: $0) }
      } : nil, collection: evidence ? collection.identity : nil,
      generation: evidence ? collection.generation : nil,
      evaluatorProfile: evidence ? evaluation.evaluatorProfile : nil)
    return (result, coverage.complete)
  }

  private static func isMarkdown(_ path: String) -> Bool { ["md", "markdown"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
  private func truthy(_ value: JSONValue?) -> Bool {
    switch value {
    case nil, .null: return false
    case .boolean(let value): return value
    case .string(let value): return !value.isEmpty
    case .array(let value): return !value.isEmpty
    case .object(let value): return !value.isEmpty
    default: return true
    }
  }
  private func grouped(_ values: [MarkdownQueryTriple]) -> [MarkdownQueryTriple] {
    var result: [MarkdownQueryTriple] = []
    for value in values.sorted(by: { [$0.subject, $0.predicate, $0.object].lexicographicallyPrecedes([$1.subject, $1.predicate, $1.object]) }) {
      if let last = result.last, last.subject == value.subject && last.predicate == value.predicate && last.object == value.object {
        result[result.count - 1].occurrenceCount += 1
      } else { result.append(value) }
    }
    return result
  }
}

private enum Membership {
  case yes, no, unknown
  var negated: Self { self == .yes ? .no : (self == .no ? .yes : .unknown) }
  static func union(_ values: [Self]) -> Self { values.contains(.yes) ? .yes : (values.contains(.unknown) ? .unknown : .no) }
  static func intersection(_ values: [Self]) -> Self { values.contains(.no) ? .no : (values.contains(.unknown) ? .unknown : .yes) }
}
