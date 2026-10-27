import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndexNative
import PathKit

enum SurveyContracts {
  static func populate(
    root: Path, records: [MarkdownRecord], requested: Set<String>, options: SurveyOptions,
    report: inout SurveyReport,
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
      var ruleRows: [JSONValue] = []
      var memberships: [String: [String]] = [:]
      var unknown: Set<String> = []
      var referenced: Set<MarkdownTypeName> = []
      if !requested.intersection(["rules", "uncovered", "overlaps", "types"]).isEmpty, let registry = project.rules {
        let checker = MarkdownRuleChecker(registry: registry)
        for definition in ruleDefinitions.sorted(by: { $0.name < $1.name }) {
          try Task.checkCancellation()
          var selected: [String] = []
          var uncertain: [String] = []
          for record in records {
            guard let path = record.context.path?.rawValue else { continue }
            let requirements = registry.rule(named: definition.name).map { checker.analysisRequirements(for: $0) } ?? []
            let analyzed = await MarkdownRecordAnalyzer.analyze(record, requirements: requirements,
              contentKind: .rulesKind(forFileName: path))
            let result = try checker.assessApplicability(analyzed, rule: definition)
            if result.unavailable { uncertain.append(path); unknown.insert(path) }
            else if result.matches { selected.append(path); memberships[path, default: []].append(definition.name) }
          }
          if !selected.isEmpty || !uncertain.isEmpty { referenced.formUnion(definition.referencedTypes) }
          if options.rule.isEmpty || options.rule.contains(definition.name) {
            ruleRows.append(.object([
              "name": .string(definition.name), "selected": .integer(selected.count), "unknown": .integer(uncertain.count),
              "types": .array(definition.referencedTypes.map { .string($0.rawValue) }.sorted { String(describing: $0) < String(describing: $1) }),
            ]))
            if !options.noHints && !selected.isEmpty {
              report.hints.append(.init(argv: ["md-utils", "rules", "validate", definition.name, "--project-root", root.string, "--include-non-md"] + (options.config.map { ["--config", $0] } ?? []),
                workingDirectory: Path.current.string, explanation: "Validate declared requirements for \(definition.name). This checks its full rule scope, which may extend beyond the surveyed folder."))
            }
          }
        }
      }
      for name in options.rule where !ruleDefinitions.contains(where: { $0.name == name }) { throw IndexProjectError("Unknown rule: \(name)") }
      if requested.contains("rules") { report.metrics["rules"] = try SurveyRunner.table(ruleRows, limit: options.limit) }
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
        for metric in requested.intersection(["rules", "uncovered", "overlaps"]) { report.unavailable("Rule applicability is unavailable for \(unknown.count) file(s)", metric: metric) }
      }
      for name in options.type where !definitions.contains(where: { $0.name.rawValue == name }) { throw IndexProjectError("Unknown type: \(name)") }
      let selectedTypes = definitions.filter { options.type.isEmpty || options.type.contains($0.name.rawValue) }.sorted { $0.name.rawValue < $1.name.rawValue }
      if requested.contains("types") {
        let rows: [JSONValue] = selectedTypes.map { definition in JSONValue.object([
          "name": .string(definition.name.rawValue), "source": definition.source.map(JSONValue.string) ?? .null,
          "referencedByApplicableRule": .boolean(referenced.contains(definition.name)),
          "discoveredInScope": .boolean(records.contains { record in record.context.path.map { (root + $0.rawValue).string == definition.source } ?? false }),
        ]) }
        report.metrics["types"] = try SurveyRunner.table(rows, limit: options.limit)
      }
      if requested.contains("type-matches") {
        let registry = try MarkdownTypeRegistry(definitions: definitions, schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: root), typeResourceBindings: project.types.typeResourceBindings)
        let checker = MarkdownTypeChecker(registry: registry)
        let needsCollection = selectedTypes.contains { !$0.relationships.isEmpty }
        let collection = needsCollection ? try await MarkdownRelationshipNativeCollection.load(root: root,
          noIndex: options.noIndex, includeNonMarkdown: !options.markdownOnly, configPath: options.config.map { Path($0) }) : nil
        var rows: [JSONValue] = []
        for definition in selectedTypes {
          var outcomes: [String: [String]] = ["pass": [], "fail": [], "unavailable": []]
          for record in records {
            try Task.checkCancellation()
            guard let path = record.context.path?.rawValue else { continue }
            let analyzed = await MarkdownRecordAnalyzer.analyze(record, contentKind: .rulesKind(forFileName: path))
            let assessment: MarkdownTypeAssessment
            if definition.relationships.isEmpty {
              assessment = try checker.assess(analyzed, as: definition.name)
            } else if SurveyRunner.isMarkdown(path) {
              assessment = try await checker.assess(record, as: definition.name, collection: collection)
            } else {
              outcomes["unavailable", default: []].append(path)
              continue
            }
            outcomes[assessment.outcome.rawValue, default: []].append(path)
          }
          if !(outcomes["unavailable"] ?? []).isEmpty { report.unavailable("Type \(definition.name.rawValue) has unavailable assessments", metric: "type-matches") }
          rows.append(.object(["type": .string(definition.name.rawValue), "outcomes": .object(try outcomes.mapValues { try SurveyRunner.table($0, limit: options.limit) })]))
        }
        report.metrics["type-matches"] = try SurveyRunner.table(rows, limit: options.limit)
      }
    } catch is CancellationError { throw CancellationError() }
    catch { for metric in requested { report.unavailable("\(metric): \(error)", metric: metric) } }
  }
}
