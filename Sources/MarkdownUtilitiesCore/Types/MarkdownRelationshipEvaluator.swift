import Foundation

/// Evaluates user-authored structural assertions over a bounded host snapshot.
/// No filesystem, database, network access or inference of domain truth occurs here.
public struct MarkdownRelationshipEvaluator: Sendable {
  public let registry: MarkdownTypeRegistry
  public var limits: MarkdownRelationshipLimits

  public init(registry: MarkdownTypeRegistry, limits: MarkdownRelationshipLimits = .init()) {
    self.registry = registry
    self.limits = limits
  }

  public func evaluate(
    roots: [(MarkdownRecord, MarkdownTypeName)],
    collection: MarkdownRelationshipCollection? = nil,
  ) async throws -> MarkdownRelationshipEvaluation {
    try Task.checkCancellation()
    guard limits.records > 0, limits.bytes > 0, limits.occurrences > 0, limits.candidates > 0,
      limits.definitions > 0, limits.nodes > 0, limits.edges > 0, limits.diagnostics > 0 else {
      throw MarkdownRelationshipDefinition.invalid("evaluation limits must be positive")
    }
    struct Node {
      var record: MarkdownRecord
      var type: MarkdownTypeName
      var source: String
      var local: MarkdownAssessmentOutcome = .pass
      var outcome: MarkdownAssessmentOutcome = .pass
      var dependencies: Set<String> = []
      var selectionComplete: [String: Bool] = [:]
      var diagnostics: [MarkdownDiagnostic] = []
    }
    func source(_ record: MarkdownRecord) -> String { record.context.path?.rawValue ?? record.identity?.rawValue ?? "<source>" }
    func escape(_ key: String) -> String { key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
    func pointer(_ path: [WikilinkPropertyComponent]) -> String {
      path.reduce("") { result, step in
        switch step { case .key(let key): result + "/" + escape(key); case .index(let index): result + "/\(index)" }
      }
    }
    func key(_ record: MarkdownRecord, _ type: MarkdownTypeName) -> String {
      let identity = record.identity?.rawValue ?? source(record)
      return "\(identity.utf8.count):\(identity)\(type.rawValue.utf8.count):\(type.rawValue)"
    }
    var nodes: [String: Node] = [:]
    var queue: [String] = []
    var rootsSet: Set<String> = []
    var occurrences: [MarkdownRelationshipOccurrence] = []
    var occurrenceOwners: [String] = []
    var analysis: [String: AnalyzedMarkdownRecord] = [:]
    var bytes = 0
    var edges = 0
    var candidateCount = 0
    var diagnosticCount = 0
    var truncated = false
    var limitations = collection?.limitations ?? ["No collection context supplied"]
    var rootsComplete = true
    func diagnostic(_ code: String, _ message: String, _ severity: MarkdownDiagnosticSeverity = .error,
      _ location: String = "relationships") -> MarkdownDiagnostic {
      .init(code: "relationship." + code, severity: severity, domain: .frontmatter,
        location: location, message: message)
    }
    func appendDiagnostic(_ value: MarkdownDiagnostic, to list: inout [MarkdownDiagnostic]) {
      if diagnosticCount < limits.diagnostics { list.append(value); diagnosticCount += 1 }
      else { truncated = true }
    }
    func add(_ record: MarkdownRecord, _ type: MarkdownTypeName) -> String? {
      let id = key(record, type)
      if let existing = nodes[id] {
        guard existing.record == record else { return nil }
        return id
      }
      guard nodes.count < limits.nodes else { return nil }
      nodes[id] = Node(record: record, type: type, source: source(record))
      queue.append(id)
      return id
    }
    for (record, type) in roots {
      guard registry.definition(named: type) != nil else { throw MarkdownTypeCheckerError.unknownType(type.rawValue) }
      guard let id = add(record, type) else {
        rootsComplete = false
        if !limitations.contains("relationship.limit.exceeded: root node budget or inconsistent revisions") {
          limitations.append("relationship.limit.exceeded: root node budget or inconsistent revisions")
        }
        continue
      }
      rootsSet.insert(id)
    }
    var cursor = 0
    while cursor < queue.count {
      try Task.checkCancellation()
      let id = queue[cursor]
      cursor += 1
      guard var node = nodes[id], let definition = registry.definition(named: node.type) else { continue }
      node.selectionComplete = Dictionary(uniqueKeysWithValues: definition.relationships.compactMap { name, relation in
        relation.severity == .error || rootsSet.contains(id) ? (name, false) : nil
      })
      let recordKey = node.record.identity?.rawValue ?? node.source
      let analyzed: AnalyzedMarkdownRecord
      if let prior = analysis[recordKey] {
        guard prior.record == node.record else {
          node.local = .unavailable
          appendDiagnostic(diagnostic("context.unavailable", "Mixed record revisions in snapshot"), to: &node.diagnostics)
          nodes[id] = node
          continue
        }
        analyzed = prior
      } else {
        guard analysis.count < limits.records, node.record.content.utf8.count <= limits.bytes - bytes,
          registry.definitions.count <= limits.definitions else {
          node.local = .unavailable
          appendDiagnostic(diagnostic("limit.exceeded", "Record, byte or definition budget exceeded"), to: &node.diagnostics)
          nodes[id] = node
          continue
        }
        bytes += node.record.content.utf8.count
        analyzed = await MarkdownRecordAnalyzer.analyze(node.record,
          contentKind: node.record.context.path.map { .rulesKind(forFileName: $0.rawValue) } ?? .markdown)
        analysis[recordKey] = analyzed
      }
      let local = try MarkdownTypeChecker(registry: registry).assessLocal(analyzed, as: node.type)
      node.local = local.outcome
      // Representation availability is independent of a type having any constraints.
      if let fileExtension = analyzed.unavailableFrontmatterExtension {
        node.local = .all([node.local, .unavailable])
        appendDiagnostic(diagnostic("context.unavailable", "Unsupported document representation: \(fileExtension)"), to: &node.diagnostics)
      }
      if let collection, collection.records[node.source] != node.record {
        node.local = .all([node.local, .unavailable])
        appendDiagnostic(diagnostic("context.unavailable", "Source is not the supplied snapshot revision"), to: &node.diagnostics)
      }
      for cause in local.diagnostics { appendDiagnostic(cause, to: &node.diagnostics) }
      for name in definition.relationships.keys.sorted() {
        guard let relation = definition.relationships[name],
          let targetType = registry.typeResourceBindings[relation.target] else { continue }
        // Only caller-selected roots expand advisories; their targets expand required checks only.
        if relation.severity == .advisory && !rootsSet.contains(id) { continue }
        var relationOutcomes: [MarkdownAssessmentOutcome] = []
        let location = "#/relationships/" + escape(name)
        func issue(_ code: String, _ message: String, _ outcome: MarkdownAssessmentOutcome, at path: String? = nil) {
          relationOutcomes.append(outcome)
          var cause = diagnostic(code, message, relation.severity, path ?? location)
          cause.schemaLocation = location
          cause.definitionSource = definition.source
          appendDiagnostic(cause, to: &node.diagnostics)
        }
        if analyzed.parseDiagnostics.contains(where: { $0.domain == .frontmatter }) || analyzed.unavailableFrontmatterExtension != nil {
          issue("context.unavailable", "Frontmatter selection is unavailable", .unavailable)
          if relation.severity == .error { node.local = .all([node.local, .unavailable]) }
          continue
        }
        var selected: [(JSONValue, [WikilinkPropertyComponent])] = []
        var selectionGaps: [String] = []
        func walk(_ value: JSONValue, _ offset: Int, _ path: [WikilinkPropertyComponent]) throws {
          try Task.checkCancellation()
          guard selected.count + occurrences.count < limits.occurrences else {
            if selectionGaps.isEmpty { issue("limit.exceeded", "Occurrence budget exceeded", .unavailable) }
            selectionGaps.append("limit")
            return
          }
          if offset == relation.select.count {
            if value == .null && relation.ignoreNulls { return }
            selected.append((value, path))
            return
          }
          switch relation.select[offset] {
          case .key(let key):
            guard case .object(let object) = value else {
              selectionGaps.append("shape")
              issue("selection.shape", "Expected object", .fail, at: pointer(path))
              return
            }
            if let child = object[key] { try walk(child, offset + 1, path + [.key(key)]) }
          case .each:
            guard case .array(let array) = value else {
              selectionGaps.append("shape")
              issue("selection.shape", "Expected array", .fail, at: pointer(path))
              return
            }
            for (index, child) in array.enumerated() {
              try walk(child, offset + 1, path + [.index(index)])
              if selected.count + occurrences.count >= limits.occurrences && index + 1 < array.count {
                selectionGaps.append("limit")
                issue("limit.exceeded", "Occurrence budget exceeded", .unavailable)
                break
              }
            }
          }
        }
        try walk(.object(analyzed.relationshipFrontmatter ?? [:]), 0, [])
        node.selectionComplete[name] = selectionGaps.isEmpty
        if let maximum = relation.maximum, selected.count > maximum {
          issue("cardinality", "Selected \(selected.count) occurrences; maximum is \(maximum)", .fail)
        }
        if selectionGaps.isEmpty && selected.count < relation.minimum {
          issue("cardinality", "Selected \(selected.count) occurrences; minimum is \(relation.minimum)", .fail)
        }
        if !selectionGaps.isEmpty { relationOutcomes.append(.unavailable) }
        var destinations: Set<String> = []
        for (value, path) in selected {
          try Task.checkCancellation()
          var occurrence = MarkdownRelationshipOccurrence(source: node.source,
            sourceIdentity: node.record.identity, sourceRevision: node.record.revision,
            type: definition.name.rawValue, typeVersion: definition.version, definitionSource: definition.source,
            definitionRevision: definition.resourceRevision, declarationLocation: location,
            decodedUTF8Range: value.stringValue.map { 0..<$0.utf8.count },
            relationship: name, propertyPath: path, value: value, targetType: targetType.rawValue, severity: relation.severity)
          var values: [MarkdownAssessmentOutcome] = []
          func failure(_ code: String, _ message: String, _ outcome: MarkdownAssessmentOutcome = .fail,
            reason: String? = nil,
          ) {
            values.append(outcome)
            var cause = diagnostic(code, message, relation.severity, pointer(path))
            cause.schemaLocation = location
            cause.definitionSource = definition.source
            cause.reason = reason
            if code == "value.invalid" { cause.format = "Wikilink/Obsidian" }
            appendDiagnostic(cause, to: &occurrence.diagnostics)
          }
          occurrence.nativeTemporal = analyzed.nativeTemporalPaths.contains(pointer(path))
          if occurrence.nativeTemporal {
            failure("value.invalid", "Expected a Wikilink string, received a native temporal value", reason: "native-kind")
          } else if let string = value.stringValue {
            do { occurrence.link = try Wikilink.parse(string, context: .standard) }
            catch { failure("value.invalid", "Expected one whole Wikilink: \(error)", reason: (error as? MarkdownSemanticScalarError)?.rawValue) }
          } else { failure("value.invalid", "Expected a whole Wikilink string", reason: "native-kind") }
          if let link = occurrence.link {
            if relation.forbidEmbeds && link.isEmbed { failure("embed.forbidden", "Embeds are forbidden") }
            if relation.forbidAnchors && link.anchor != nil { failure("anchor.forbidden", "Anchors are forbidden") }
            if let collection {
              var resolution = collection.resolver.resolve(target: link.target, from: node.source)
              if resolution.candidates.count > limits.candidates - candidateCount {
                resolution.candidates = Array(resolution.candidates.prefix(max(0, limits.candidates - candidateCount)))
                // A bounded candidate listing cannot erase an already witnessed ambiguity.
                if resolution.status != .ambiguous { resolution.status = .unavailable }
                resolution.namespaceComplete = false
                failure("limit.exceeded", "Candidate budget exceeded", .unavailable)
              }
              candidateCount += resolution.candidates.count
              occurrence.resolution = resolution
              switch resolution.status {
              case .unresolved: failure("target.unresolved", "No destination in complete candidate namespace")
              case .ambiguous: failure("target.ambiguous", "Multiple destination candidates")
              case .unavailable: failure("context.unavailable", "Candidate namespace is incomplete", .unavailable)
              case .resolved:
                if let destination = resolution.destination {
                  let target = collection.records[destination]
                  let identity = target?.identity?.rawValue ?? destination
                  occurrence.targetIdentity = .init(rawValue: identity)
                  occurrence.targetRevision = target?.revision
                  if !destinations.insert(identity).inserted && relation.forbidDuplicates {
                    failure("target.duplicate", "Repeated destination identity: \(identity)")
                  }
                  if let target {
                    if edges < limits.edges, let targetID = add(target, targetType) {
                      edges += 1
                      occurrence.dependency = targetID
                      if relation.severity == .error { node.dependencies.insert(targetID) }
                    } else { failure("limit.exceeded", "Dependency budget exceeded or inconsistent revisions", .unavailable) }
                  } else { failure("context.unavailable", "Target record unavailable or unsupported", .unavailable) }
                } else { failure("context.unavailable", "Target record unavailable or unsupported", .unavailable) }
              }
            } else { failure("context.unavailable", "No collection context supplied", .unavailable) }
          }
          occurrence.outcome = .all(values)
          relationOutcomes.append(occurrence.outcome)
          occurrences.append(occurrence)
          occurrenceOwners.append(id)
        }
        if relation.severity == .error { node.local = .all([node.local, .all(relationOutcomes)]) }
      }
      nodes[id] = node
    }
    // Greatest fixed point: only lower assumptions after all bounded obligations are known.
    var reverse: [String: Set<String>] = [:]
    for (id, node) in nodes {
      for dependency in node.dependencies { reverse[dependency, default: []].insert(id) }
    }
    var work = queue
    cursor = 0
    while cursor < work.count {
      try Task.checkCancellation()
      let id = work[cursor]
      cursor += 1
      guard var node = nodes[id] else { continue }
      let outcome = MarkdownAssessmentOutcome.all([node.local] + node.dependencies.map { nodes[$0]?.outcome ?? .unavailable })
      if outcome != node.outcome {
        node.outcome = outcome
        nodes[id] = node
        work.append(contentsOf: (reverse[id] ?? []).sorted())
      }
    }
    for index in occurrences.indices {
      guard let dependency = occurrences[index].dependency, let target = nodes[dependency] else { continue }
      occurrences[index].targetOutcome = target.outcome
      occurrences[index].outcome = .all([occurrences[index].outcome, target.outcome])
      if target.outcome != .pass {
        var cause = diagnostic(target.outcome == .fail ? "target.nonconformance" : "context.unavailable",
          "Destination required assessment: \(dependency)", occurrences[index].severity, pointer(occurrences[index].propertyPath))
        cause.schemaLocation = occurrences[index].declarationLocation
        cause.definitionSource = occurrences[index].definitionSource
        appendDiagnostic(cause, to: &occurrences[index].diagnostics)
      }
    }
    // Attach occurrence causes once to their owning node, retaining dependency IDs for cycles.
    for index in occurrences.indices {
      if var node = nodes[occurrenceOwners[index]] {
        for cause in occurrences[index].diagnostics { appendDiagnostic(cause, to: &node.diagnostics) }
        nodes[occurrenceOwners[index]] = node
      }
    }
    try Task.checkCancellation()
    return .init(collection: collection?.identity, generation: collection?.generation,
      sourcesComplete: (collection?.sourcesComplete ?? false) && rootsComplete,
      candidatesComplete: collection?.resolver.namespaceComplete ?? false,
      limitations: limitations, occurrences: occurrences,
      assessments: nodes.keys.sorted().compactMap { id in
        nodes[id].map { .init(id: id, source: $0.source, type: $0.type.rawValue,
          sourceRevision: $0.record.revision, definitionRevision: registry.definition(named: $0.type)?.resourceRevision,
          outcome: $0.outcome, dependencies: $0.dependencies.sorted(), selectionComplete: $0.selectionComplete,
          diagnostics: $0.diagnostics) }
      }, diagnosticsTruncated: truncated)
  }
}
