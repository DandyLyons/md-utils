import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import PathKit

enum SurveyContracts {
  static func populate(
    root: Path, records: [MarkdownRecord], requested: Set<String>, options: SurveyOptions,
    report: inout SurveyReport, progress: SurveyProgress? = nil,
    analyze: @Sendable (MarkdownRecord, MarkdownRecordAnalysisRequirements, MarkdownRecordContentKind) async -> AnalyzedMarkdownRecord = {
      await MarkdownRecordAnalyzer.analyze($0, requirements: $1, contentKind: $2)
    },
  ) async throws {
    do {
      if let config = options.config, !Path(config).exists { throw IndexProjectError("Explicit configuration does not exist: \(config)") }
      let project = try IndexProjectEvaluator(root: root, configPath: options.config.map { Path($0) } ?? root + ".md-utils/md-utils.json")
      var definitions = project.types.definitions
      // Definition inventory uses the same bounded, confined input discovery as documents.
      for record in records {
        guard let path = record.context.path?.rawValue,
          MarkdownTypeFileRegistryLoader.definitionFileSuffixes.contains(where: path.hasSuffix) else { continue }
        let suffix = URL(fileURLWithPath: path).pathExtension
        let format: MarkdownTypeDefinitionFormat = suffix == "json" ? .json : (suffix == "toml" ? .toml : .yaml)
        let definition = try MarkdownTypeDefinitionDecoder.decode(record.content, format: format, source: (root + path).string)
        if !definitions.contains(where: { $0.source == definition.source }) { definitions.append(definition) }
      }
      let ruleDefinitions = project.rules?.definitions ?? []
      if !requested.intersection(["rules", "uncovered", "overlaps", "types"]).isEmpty {
        await progress?.update("Checking \(ruleDefinitions.count) rules against \(records.count.formatted(.number.grouping(.automatic))) text files…")
      }
      var ruleRows: [JSONValue] = []
      var memberships: [String: [String]] = [:]
      var unknown: Set<String> = []
      var uncertainties: [JSONValue] = []
      var reportedUnknown: Set<String> = []
      var reportedSelected: Set<String> = []
      var referenced: Set<MarkdownTypeName> = []
      if !requested.intersection(["rules", "uncovered", "overlaps", "types"]).isEmpty, let registry = project.rules {
        let checker = MarkdownRuleChecker(registry: registry)
        let ordered = ruleDefinitions.sorted(by: { $0.name < $1.name })
        let requirements = ordered.reduce(into: MarkdownRecordAnalysisRequirements()) { combined, definition in
          if let compiled = registry.rule(named: definition.name) {
            combined.formUnion(checker.analysisRequirements(for: compiled))
          }
        }
        var selectedCounts: [String: Int] = [:]
        var uncertainCounts: [String: Int] = [:]
        var uncertaintyRows: [String: [JSONValue]] = [:]
        // Analysis is pure for a record and its requested features. Unioning those
        // features lets all rules share one parse without retaining a collection of ASTs.
        if !ordered.isEmpty {
          for record in records {
            try Task.checkCancellation()
            guard let path = record.context.path?.rawValue else { continue }
            let analyzed = await analyze(record, requirements, .rulesKind(forFileName: path))
            try Task.checkCancellation()
            for definition in ordered {
              try Task.checkCancellation()
              let result = try checker.assessApplicability(analyzed, rule: definition)
              if result.unavailable {
                uncertainCounts[definition.name, default: 0] += 1
                unknown.insert(path)
                if options.rule.isEmpty || options.rule.contains(definition.name) {
                  reportedUnknown.insert(path)
                  let reasons = result.diagnostics.map { diagnostic in
                    JSONValue.object(["code": .string(diagnostic.code), "message": .string(diagnostic.message)])
                  }
                  uncertaintyRows[definition.name, default: []].append(.object([
                    "path": .string(path), "rule": .string(definition.name),
                    "reasons": .array(reasons.isEmpty ? [.object(["code": .string("rule.applicability.unavailable"), "message": .string("Rule selection could not be assessed")])] : reasons),
                  ]))
                }
              } else if result.matches {
                selectedCounts[definition.name, default: 0] += 1
                memberships[path, default: []].append(definition.name)
                if options.rule.isEmpty || options.rule.contains(definition.name) { reportedSelected.insert(path) }
              }
            }
          }
        }
        // Preserve the original rule-first diagnostic order and selection summaries.
        for definition in ordered {
          let selected = selectedCounts[definition.name, default: 0]
          let uncertain = uncertainCounts[definition.name, default: 0]
          uncertainties.append(contentsOf: uncertaintyRows[definition.name] ?? [])
          if selected > 0 || uncertain > 0 { referenced.formUnion(definition.referencedTypes) }
          if options.rule.isEmpty || options.rule.contains(definition.name) {
            ruleRows.append(.object([
              "name": .string(definition.name), "selected": .integer(selected), "unknown": .integer(uncertain),
              "types": .array(definition.referencedTypes.map { .string($0.rawValue) }.sorted { String(describing: $0) < String(describing: $1) }),
            ]))
          }
        }
      }
      for name in options.rule where !ruleDefinitions.contains(where: { $0.name == name }) { throw IndexProjectError("Unknown rule: \(name)") }
      ruleRows.sort(by: rulePrecedes)
      if requested.contains("rules"), !options.noHints,
        let leading = ruleRows.first(where: { count($0, "selected") > 0 }),
        let name = leading.objectValue?["name"]?.stringValue {
        let projectArguments = ["--project-root", root.string,
          "--config", options.config ?? (root + ".md-utils/md-utils.json").string,
        ]
        let fileArguments = options.markdownOnly ? [] : ["--include-non-md"]
        report.hints.append(.init(argv: ["md-utils", "rules", "describe", name] + projectArguments,
          workingDirectory: Path.current.string, explanation: "Explore selection and requirements for \(name), or substitute another rule. Named-rule commands use its full project scope, which may extend beyond this folder."))
        if let path = memberships.keys.sorted().first(where: { memberships[$0]?.contains(name) == true }) {
          report.hints.append(.init(
            argv: ["md-utils", "rules", "matching", (root + path).string, "--explain"] + projectArguments + fileArguments,
            workingDirectory: Path.current.string,
            explanation: "Explain which configured rules match this example file; substitute another file to investigate it.",
          ))
        }
        report.hints.append(.init(
          argv: ["md-utils", "rules", "files-matching", name] + projectArguments + fileArguments,
          workingDirectory: Path.current.string,
          explanation: "List files selected by \(name). This uses the rule's full project scope, which may extend beyond the surveyed folder and its exclusions.",
        ))
      }
      if requested.contains("rules") {
        var table = try SurveyRunner.table(ruleRows, limit: options.limit).objectValue ?? [:]
        let matchingCount = ruleRows.filter { count($0, "selected") > 0 }.count
        let uncertainOnlyCount = ruleRows.filter { count($0, "selected") == 0 && count($0, "unknown") > 0 }.count
        let noMatchCount = ruleRows.count - matchingCount - uncertainOnlyCount
        table["summary"] = .object([
          "rules": .integer(ruleRows.count), "configuredRules": .integer(ruleDefinitions.count),
          "matchingRules": .integer(matchingCount),
          "uncertainOnlyRules": .integer(uncertainOnlyCount),
          "noMatchRules": .integer(noMatchCount),
          "surveyedFiles": .integer(records.count), "selectedFiles": .integer(reportedSelected.count),
          "uncertainFiles": .integer(reportedUnknown.count), "uncertainRuleFilePairs": .integer(uncertainties.count),
          "assessmentComplete": .boolean(uncertainties.isEmpty),
        ])
        table["uncertainties"] = try SurveyRunner.table(uncertainties, limit: options.limit)
        report.metrics["rules"] = .object(table)
      }
      if requested.contains("uncovered") {
        let paths = records.compactMap { $0.context.path?.rawValue }.filter { memberships[$0] == nil && !unknown.contains($0) }
        report.metrics["uncovered"] = .object(["files": try SurveyRunner.table(paths, limit: options.limit), "unknown": try SurveyRunner.table(unknown.sorted(), limit: options.limit), "configuredRules": .integer(ruleDefinitions.count)])
      }
      if requested.contains("overlaps") {
        let rows = memberships.keys.sorted().filter { (memberships[$0]?.count ?? 0) >= 2 }.map { path in
          JSONValue.object(["path": .string(path), "rules": .array((memberships[path] ?? []).sorted().map(JSONValue.string)), "additionalMatchesUnknown": .boolean(unknown.contains(path))])
        }
        report.metrics["overlaps"] = try SurveyRunner.table(rows, limit: options.limit)
      }
      if !unknown.isEmpty {
        for metric in requested.intersection(["uncovered", "overlaps"]) { report.unavailable("Rule applicability is unavailable for \(unknown.count) file(s)", metric: metric) }
      }
      for name in options.type where !definitions.contains(where: { $0.name.rawValue == name }) { throw IndexProjectError("Unknown type: \(name)") }
      let selectedTypes = definitions.filter { options.type.isEmpty || options.type.contains($0.name.rawValue) }.sorted { $0.name.rawValue < $1.name.rawValue }
      if requested.contains("types") {
        let rows: [JSONValue] = selectedTypes.map { definition in JSONValue.object([
          "name": .string(definition.name.rawValue), "source": definition.source.map(JSONValue.string) ?? .null,
          "referencedByApplicableRule": .boolean(referenced.contains(definition.name)),
          "discoveredInScope": .boolean(records.contains { record in record.context.path.map { (root + $0.rawValue).string == definition.source } ?? false }),
        ]) }.sorted { lhs, rhs in
          for key in ["referencedByApplicableRule", "discoveredInScope"] {
            let left = lhs.objectValue?[key] == .boolean(true)
            let right = rhs.objectValue?[key] == .boolean(true)
            if left != right { return left }
          }
          return (lhs.objectValue?["name"]?.stringValue ?? "") < (rhs.objectValue?["name"]?.stringValue ?? "")
        }
        report.metrics["types"] = try SurveyRunner.table(rows, limit: options.limit)
      }
      if requested.contains("type-matches") {
        await progress?.update("Assessing \(selectedTypes.count) types against \(records.count.formatted(.number.grouping(.automatic))) text files…")
        let registry = try MarkdownTypeRegistry(definitions: definitions, schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: root), typeResourceBindings: project.types.typeResourceBindings)
        let checker = MarkdownTypeChecker(registry: registry)
        let needsCollection = selectedTypes.contains { !$0.relationships.isEmpty }
        let collection = needsCollection ? try await MarkdownRelationshipNativeCollection.load(root: root,
          noIndex: options.noIndex, includeNonMarkdown: !options.markdownOnly, configPath: options.config.map { Path($0) }) : nil
        let hasLocalTypes = selectedTypes.contains { $0.relationships.isEmpty }
        var byType: [MarkdownTypeName: [String: [String]]] = [:]
        for record in records where !selectedTypes.isEmpty {
          try Task.checkCancellation()
          guard let path = record.context.path?.rawValue else { continue }
          // Local conformance shares one full analysis. Keep just the current
          // record's parsed state rather than a collection-wide AST cache.
          let analyzed = hasLocalTypes ? await analyze(record, .all, .rulesKind(forFileName: path)) : nil
          try Task.checkCancellation()
          var relationshipSource: MarkdownRecord?
          if let collection, SurveyRunner.isMarkdown(path),
            let source = try await collection.record(at: path), source.content.utf8.elementsEqual(record.content.utf8) {
            relationshipSource = source
          }
          for definition in selectedTypes {
            try Task.checkCancellation()
            let outcome: MarkdownAssessmentOutcome
            if definition.relationships.isEmpty, let analyzed {
              outcome = try checker.assess(analyzed, as: definition.name).outcome
            } else if let source = relationshipSource {
              // Recursive checks retain their collection-aware evaluator and
              // exact snapshot identity. Changed/missing sources stay unavailable.
              outcome = try await checker.assess(source, as: definition.name, collection: collection).outcome
            } else { outcome = .unavailable }
            byType[definition.name, default: [:]][outcome.rawValue, default: []].append(path)
          }
        }
        var rows: [JSONValue] = []
        for definition in selectedTypes {
          var outcomes: [String: [String]] = ["pass": [], "fail": [], "unavailable": []]
          outcomes.merge(byType[definition.name] ?? [:]) { _, paths in paths }
          if !(outcomes["unavailable"] ?? []).isEmpty { report.unavailable("Type \(definition.name.rawValue) has unavailable assessments", metric: "type-matches") }
          rows.append(.object(["type": .string(definition.name.rawValue), "outcomes": .object(try outcomes.mapValues { try SurveyRunner.table($0, limit: options.limit) })]))
        }
        report.metrics["type-matches"] = try SurveyRunner.table(rows, limit: options.limit)
      }
    } catch is CancellationError { throw CancellationError() }
    catch { for metric in requested { report.unavailable("\(metric): \(error)", metric: metric) } }
  }

  private static func count(_ row: JSONValue, _ key: String) -> Int {
    if case .integer(let count) = row.objectValue?[key] { return count }
    return 0
  }

  static func rulePrecedes(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
    for key in ["selected", "unknown"] {
      let left = count(lhs, key), right = count(rhs, key)
      if left != right { return left > right }
    }
    return (lhs.objectValue?["name"]?.stringValue ?? "") < (rhs.objectValue?["name"]?.stringValue ?? "")
  }
}
