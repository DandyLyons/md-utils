import ArgumentParser
import DynamicJSON
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates
import PathKit
import Yams

struct InstanceCreationOptions: ParsableArguments {
  @Option(help: "JSON object file containing template variables (single instance).") var value: String?
  @Option(help: "JSON array file containing a nonempty batch of input objects.") var values: String?
  @Option(help: "JSON object file in a batch; repeat this option for each file.") var valueFile: [String] = []
  @Option(help: "Exact output filename, with any extension or no extension.") var filename: String?
  @Option(help: "JSONPath selecting exactly one filename stem after defaults.") var filenameData: String?
  @Option(name: .customLong("extension"), help: "Suffix for --filename-data (default md); use an empty string for no extension.")
  var fileExtension: String?
  @Flag(help: "Render and assess without creating files.") var dryRun = false

  func validate() throws {
    guard [value != nil, values != nil, !valueFile.isEmpty].filter({ $0 }).count == 1 else {
      throw ValidationError("Supply exactly one input form: --value, --values, or repeated --value-file.")
    }
    guard !isBulk || (filename == nil && filenameData != nil) else {
      throw ValidationError("Bulk creation requires --filename-data; --filename is only for single instances.")
    }
    guard (filename != nil) != (filenameData != nil) else {
      throw ValidationError("Supply exactly one of --filename and --filename-data.")
    }
    guard filename == nil || fileExtension == nil else {
      throw ValidationError("--extension cannot be combined with --filename; an explicit filename is complete.")
    }
  }

  var isBulk: Bool { values != nil || !valueFile.isEmpty }

  func outputName(input: JSONValue) throws -> String {
    try validate()
    let name: String
    if let filename { name = filename }
    else if let query = filenameData {
      let path = try JSONPath(query: query, strict: true)
      let results = try JSONPathEvaluator(value: JSON(encodable: input), strict: true).query(path)
      guard results.count == 1, let selected = results.first, case .string(let stem) = selected.value else {
        throw ValidationError("--filename-data \(query) must select exactly one string; selected \(results.count) value(s).")
      }
      try Self.validateName(stem)
      let suffix = fileExtension ?? "md"
      if !suffix.isEmpty { try Self.validateName(suffix) }
      name = stem + (suffix.isEmpty ? "" : "." + suffix)
    } else { throw ValidationError("A filename is required.") }
    try Self.validateName(name)
    return name
  }

  private static func validateName(_ value: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value != ".", value != "..", !value.contains("/"), !value.contains("\\"),
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw ValidationError("Unsafe filename or stem \(String(reflecting: value)): use a nonempty single filename without path separators or control characters.")
    }
  }
}

extension CLIEntry.TypesCommands {
  struct New: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a Markdown instance and report type conformance.")
    @Option(name: .customLong("type"), help: "Type name whose creation template to use.") var typeName: String
    @Option(help: "Project root directory.", transform: { Path($0) }) var root: Path = .current
    @Argument(help: "Existing destination directory (for example ./Books/).") var destination: String
    @OptionGroup var creation: InstanceCreationOptions

    mutating func run() async throws {
      try creation.validate()
      let registry = try MarkdownTypeFileRegistryLoader.load(projectRoot: root)
      try await InstanceCreation.run(options: creation, typeName: typeName, registry: registry,
        root: root, directory: Path(destination))
    }
  }
}

extension CLIEntry.RulesCommands {
  struct New: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a Markdown instance and report type and rule conformance.")
    @Option(name: .customLong("rule"), help: "Rule with an explicit creation directory.") var ruleName: String
    @OptionGroup var project: RuleProjectOptions
    @OptionGroup var creation: InstanceCreationOptions

    mutating func run() async throws {
      try creation.validate()
      let loaded = try MarkdownStandaloneRuleProject(configPath: project.configPath, projectRoot: project.root)
      guard let rule = loaded.files.first(where: { $0.name == ruleName }) else { throw ValidationError("Unknown rule: \(ruleName)") }
      guard let target = rule.creation else { throw ValidationError("Rule \(ruleName) requires creation.directory; destinations are never inferred from globs.") }
      let bindings = try MarkdownRuleFileStore(projectRoot: loaded.projectRoot).typeBindings(for: rule, registry: loaded.types)
      let candidates = Set(bindings.values.map(\.rawValue))
      let type: String
      if let explicit = target.type {
        guard candidates.contains(explicit) else { throw ValidationError("creation.type \(explicit) is not a type referenced by rule \(ruleName).") }
        type = explicit
      } else if candidates.count == 1, let only = candidates.first { type = only }
      else { throw ValidationError("Rule \(ruleName) has multiple possible types; declare creation.type.") }
      let configured = Path(target.directory)
      guard !configured.isAbsolute else { throw ValidationError("creation.directory must be relative to the project root.") }
      let directory = (loaded.projectRoot + configured).absolute().normalize()
      try InstanceCreation.requireContained(directory, root: loaded.projectRoot)
      let rules = try loaded.compile(capabilities: [.modificationDate, .frontmatterJMESPath], queryProvider: JMESPathRuleCapabilityProvider())
      try await InstanceCreation.run(options: creation, typeName: type, registry: loaded.types,
        root: loaded.projectRoot, directory: directory, ruleName: ruleName, rules: rules)
    }
  }
}

/// Native command orchestration; rendering and schema preparation stay reusable.
enum InstanceCreation {
  static func run(options: InstanceCreationOptions, typeName: String, registry: MarkdownTypeRegistry,
    root: Path, directory: Path, ruleName: String? = nil, rules: MarkdownRuleRegistry? = nil,
  ) async throws {
    guard let definition = registry.definition(named: typeName), let template = definition.creation else {
      throw ValidationError("Type \(typeName) is unknown or has no creation template.")
    }
    guard directory.isDirectory else { throw ValidationError("Destination directory must already exist: \(directory.string)/") }
    let source: String
    if let inline = template.inline { source = inline }
    else if let reference = template.reference, let declaring = definition.source {
      let file = (Path(declaring).parent() + reference).absolute().normalize()
      guard !Path(reference).isAbsolute else { throw ValidationError("Template references must be relative.") }
      try requireContained(file, root: root)
      guard let text = String(data: try read(file.string, limit: MarkdownTemplateLimits().templateBytes), encoding: .utf8) else {
        throw ValidationError("Template must be UTF-8: \(file)")
      }
      source = text
    } else { throw ValidationError("Cannot resolve creation template source.") }
    let schema: JSONValue?
    switch template.inputSchema {
    case .inline(let value): schema = value
    case .reference(let reference):
      guard let declaring = definition.source, !Path(reference).isAbsolute else {
        throw ValidationError("Input schema references must be relative to a type definition.")
      }
      let path = (Path(declaring).parent() + reference).absolute().normalize()
      try requireContained(path, root: root)
      let bytes = try read(path.string, limit: MarkdownTemplateLimits().inputBytes)
      if path.extension?.lowercased() == "json" { schema = try JSONDecoder().decode(JSONValue.self, from: bytes) }
      else {
        guard let text = String(data: bytes, encoding: .utf8), let node = try Yams.compose(yaml: text) else {
          throw ValidationError("Input schema must be UTF-8 JSON or YAML: \(path)")
        }
        schema = try JSONValue(any: YAMLConversion.safeNodeToSwiftValue(node))
      }
    case nil: schema = nil
    }
    var items = try CreationBatch.load(options: options)
    var outputBytes = 0
    for index in items.indices {
      try Task.checkCancellation()
      guard let raw = items[index].input else { continue }
      let input: JSONValue
      do { input = try TemplateInputDefaults.prepare(raw, schema: schema) }
      catch is CancellationError { throw CancellationError() }
      catch {
        items[index].failures.append("Template input: \(error)")
        continue
      }
      do {
        let filename = try options.outputName(input: input)
        items[index].destination = URL(fileURLWithPath: directory.absolute().string, isDirectory: true).appendingPathComponent(filename)
      } catch { items[index].failures.append("Filename: \(error)") }
      // Rendering is independent of filename selection, so collect both failures.
      do {
        let rendered = try await MarkdownTemplateRenderer().render(template: source, variables: input, mode: template.mode)
        outputBytes += rendered.source.utf8.count
        guard outputBytes <= CreationBatch.byteLimit else {
          throw ValidationError("Aggregate rendered output exceeds \(CreationBatch.byteLimit) bytes.")
        }
        items[index].content = Data(rendered.source.utf8)
        items[index].details.append(schema == nil ? "Template input schema: not declared" : "Template input schema: passed")
        if let destination = items[index].destination {
          items[index].details += try await assess(source: rendered.source, destination: destination,
            root: root, typeName: typeName, registry: registry, ruleName: ruleName, rules: rules)
        }
        for warning in rendered.warnings {
          items[index].details.append("Template warning: \(warning.location): \(warning.message)")
        }
      } catch is CancellationError { throw CancellationError() }
      catch { items[index].failures.append("Rendering/assessment: \(error)") }
      items[index].input = nil
    }
    CreationBatch.checkDestinations(&items)
    if items.contains(where: { !$0.failures.isEmpty }) {
      let diagnostics = items.flatMap { item in item.failures.map { "- \(item.label): \($0)" } }
      throw ValidationError((["Creation failed; no files were written."] + diagnostics).joined(separator: "\n"))
    }
    let results = CreationBatch.persist(items, dryRun: options.dryRun)
    for result in results {
      print("\(result.status) \(result.item.label)\(result.error.map { ": \($0)" } ?? "")")
      for detail in result.item.details { print("  \(detail)") }
    }
    guard !results.contains(where: { $0.error != nil }) else { throw ExitCode.failure }
  }

  static func assess(source: String, destination: URL, root: Path, typeName: String,
    registry: MarkdownTypeRegistry, ruleName: String?, rules: MarkdownRuleRegistry?,
  ) async throws -> [String] {
    let rootURL = URL(fileURLWithPath: root.absolute().string).standardizedFileURL
    let outputURL = destination.standardizedFileURL
    // Explicit type destinations may be outside the project. In that case the path
    // is unavailable to project-relative constraints rather than misrepresented.
    let prefix = rootURL.path + "/"
    let logical = outputURL.path.hasPrefix(prefix) ? try MarkdownRecordPath(String(outputURL.path.dropFirst(prefix.count))) : nil
    let record = MarkdownRecord(identity: .init(rawValue: outputURL.path), content: source,
      context: .init(path: logical, modificationDate: Date()))
    let assessment = try await MarkdownTypeChecker(registry: registry).assess(record, as: typeName)
    let ruleAssessment: MarkdownRuleAssessment?
    if let rules, let ruleName {
      ruleAssessment = try await MarkdownRuleChecker(registry: rules).assess(record, ruleNamed: ruleName)
    } else { ruleAssessment = nil }
    try Task.checkCancellation()
    var details = ["Type \(String(reflecting: typeName)): \(assessment.conforms ? "conforms" : "does not conform (advisory)")"]
    for diagnostic in assessment.diagnostics { details.append("\(diagnostic.domain.rawValue): \(diagnostic.location): \(diagnostic.message)") }
    if let ruleAssessment, let ruleName {
      details.append("Rule \(String(reflecting: ruleName)): \(ruleAssessment.status.rawValue) (advisory)")
      for diagnostic in ruleAssessment.applicabilityDiagnostics + ruleAssessment.diagnostics {
        details.append("\(diagnostic.location): \(diagnostic.message)")
      }
      if ruleAssessment.status == .notApplicable { details.append("The created document does not match this rule's selection conditions.") }
      for explanation in ruleAssessment.typeExpressionAssessment?.explanation ?? [] { details.append(explanation) }
    }
    return details
  }

  static func requireContained(_ path: Path, root: Path) throws {
    let base = URL(fileURLWithPath: root.absolute().string).resolvingSymlinksInPath().path
    let target = URL(fileURLWithPath: path.absolute().string).resolvingSymlinksInPath().path
    guard target == base || target.hasPrefix(base + "/") else { throw ValidationError("Creation reference escapes project root: \(path)") }
  }

  static func read(_ path: String, limit: Int) throws -> Data {
    let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
    defer { try? file.close() }
    var data = Data()
    while let chunk = try file.read(upToCount: min(65_536, limit + 1 - data.count)), !chunk.isEmpty {
      data.append(chunk)
      guard data.count <= limit else { throw ValidationError("Input exceeds \(limit) bytes: \(path)") }
    }
    return data
  }

  static func create(_ data: Data, at destination: URL) throws {
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".md-utils-create-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try data.write(to: temporary, options: .withoutOverwriting)
    let handle = try FileHandle(forWritingTo: temporary)
    defer { try? handle.close() }
    try handle.synchronize()
    try Task.checkCancellation()
    // Same-directory hard linking publishes complete bytes atomically and fails
    // if another writer has claimed the destination, including a dangling symlink.
    try FileManager.default.linkItem(at: temporary, to: destination)
  }
}
