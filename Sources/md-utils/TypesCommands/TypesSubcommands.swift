import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit
import Yams

extension CLIEntry.TypesCommands {
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "init",
      abstract: "Initialize the .md-utils/types/ directory"
    )

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    mutating func run() async throws {
      let result = try TypesProject.initialize(root: root)
      print(TypesProject.initializationMessage(result))
    }
  }

  struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "create",
      abstract: "Create a Markdown type-definition scaffold"
    )

    @Argument(help: "Stable, case-sensitive type name")
    var name: String

    @Option(name: .long, help: "Type contract version; Semantic Versioning is recommended")
    var version = "0.1.0"

    @Option(name: .long, help: "Definition format: yaml or json")
    var format: TypesDefinitionFormat = .yaml

    @Option(name: .long, help: "Override the generated definition file", completion: .file(), transform: { Path($0) })
    var output: Path?

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    mutating func run() async throws {
      let destination = try TypesProject.createDefinition(
        name: name,
        version: version,
        format: format,
        root: root,
        output: output
      )
      print("Created Markdown type \"\(name)\": \(destination.string)")
    }
  }

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "list",
      abstract: "List project Markdown type definitions"
    )

    @Option(name: .long, help: "Output format: text, markdown, json, or yaml")
    var format: TypesOutputFormat = .text

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    mutating func run() async throws {
      let files = try MarkdownTypeFileRegistryLoader.definitionFiles(projectRoot: root)
      if files.isEmpty {
        print("No Markdown types found.")
        return
      }
      let registry = try TypesProject.load(root: root)
      print(try TypesRenderer.renderDefinitions(registry.definitions, format: format, root: root))
    }
  }

  struct Describe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "describe",
      abstract: "Describe a Markdown type definition"
    )

    @Argument(help: "Type name to describe")
    var name: String

    @Option(name: .long, help: "Output format: text, markdown, json, or yaml")
    var format: TypesOutputFormat = .text

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    mutating func run() async throws {
      let registry = try TypesProject.load(root: root)
      guard let definition = registry.definition(named: name) else {
        throw ValidationError("Markdown type not found: \(name)")
      }
      print(try TypesRenderer.renderDefinition(definition, format: format))
    }
  }

  struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "doctor",
      abstract: "Validate Markdown type definitions and schema resources"
    )

    @Argument(help: "Optional type name to inspect")
    var name: String?

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    mutating func run() async throws {
      let registry = try TypesProject.load(root: root)
      let definitions: [MarkdownTypeDefinition]
      if let name {
        guard let definition = registry.definition(named: name) else {
          throw ValidationError("Markdown type not found: \(name)")
        }
        definitions = [definition]
      } else {
        definitions = registry.definitions
      }
      print("Checked \(definitions.count) Markdown type definition(s).")
      for definition in definitions {
        print("OK \(definition.name.rawValue)")
        if isSemanticVersion(definition.version) == false {
          print("  ADVISORY type.version.non-semver: \"\(definition.version)\" is valid, but Semantic Versioning is recommended.")
        }
      }
    }
  }

  struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "check",
      abstract: "Assess Markdown records against a named type"
    )

    @Argument(help: "Type name")
    var name: String

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    @Option(name: .long, help: "Output format: text, json, or yaml")
    var format: TypesOutputFormat = .text

    @Flag(name: .long, help: "Include successful results")
    var includeOK = false

    @Flag(name: .customLong("no-advisories"), help: "Hide advisory diagnostics")
    var noAdvisories = false

    mutating func run() async throws {
      let results = try await TypesRunner.assess(
        typeName: name,
        files: try options.resolvedPaths(),
        root: root
      )
      print(try TypesRenderer.renderAssessments(
        results,
        format: format,
        root: root,
        includeOK: includeOK,
        includeAdvisories: noAdvisories == false
      ))
      if results.contains(where: { $0.assessment.conforms == false }) {
        throw ExitCode.failure
      }
    }
  }

  struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "verify",
      abstract: "Verify type hints declared by Markdown records"
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    @Option(name: .long, help: "Output format: text, json, or yaml")
    var format: TypesOutputFormat = .text

    @Flag(name: .long, help: "Include confirmed type hints")
    var includeConfirmed = false

    @Flag(name: .long, help: "Fail when a record declares no type hints")
    var requireHints = false

    mutating func run() async throws {
      let results = try await TypesRunner.verifiedHints(
        files: try options.resolvedPaths(),
        root: root
      )
      print(try TypesRenderer.renderHints(results, format: format, root: root, includeConfirmed: includeConfirmed))
      let failed = results.contains { _, hints in
        (requireHints && hints.isEmpty) || hints.contains { $0.status != .confirmed }
      }
      if failed { throw ExitCode.failure }
    }
  }

  struct Identify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "identify",
      abstract: "Identify all types to which Markdown records conform"
    )

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    @Option(name: .long, help: "Output format: text, json, or yaml")
    var format: TypesOutputFormat = .text

    @Flag(name: .long, help: "Include nonconforming assessments")
    var allAssessments = false

    mutating func run() async throws {
      let results = try await TypesRunner.identifiedTypes(
        files: try options.resolvedPaths(),
        root: root
      )
      print(try TypesRenderer.renderIdentified(results, format: format, root: root, includeAll: allAssessments))
      if results.contains(where: { _, assessments in assessments.contains(where: \.conforms) == false }) {
        throw ExitCode.failure
      }
    }
  }

  struct Find: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "find",
      abstract: "Find Markdown files that successfully conform to a type"
    )

    @Argument(help: "Type name")
    var name: String

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    @Flag(name: .long, help: "Print absolute paths")
    var absolute = false

    mutating func run() async throws {
      let results = try await TypesRunner.assess(
        typeName: name,
        files: try options.resolvedPaths(),
        root: root
      )
      let conforming = results.filter(\.assessment.conforms)
      if conforming.isEmpty {
        print("No records conform to type \"\(name)\".")
      } else {
        for result in conforming {
          print(absolute ? result.file.absolute().string : relativePath(from: root, to: result.file))
        }
      }
    }
  }

  struct Fix: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "fix",
      abstract: "Apply selected fixes for Markdown type conformance"
    )

    @Argument(help: "Type name")
    var name: String

    @OptionGroup var options: GlobalOptions

    @Option(name: .long, help: "Project root directory", completion: .directory, transform: { Path($0) })
    var root: Path = .current

    @Flag(name: .long, help: "Preview fixes without writing")
    var dryRun = false

    @Flag(name: .long, help: "Accept deterministic fixes without prompting")
    var yes = false

    @Option(name: .long, help: "Limit fixes to a constraint identifier")
    var constraint: String?

    @Flag(name: .long, help: "Include fixes for recommendations")
    var includeRecommendations = false

    @Option(name: .customLong("set"), help: "Supply an input-required value as key=value; may be repeated")
    var suppliedValues: [String] = []

    mutating func run() async throws {
      let registry = try TypesProject.load(root: root)
      let checker = MarkdownTypeChecker(registry: registry)
      let inputs = try parseSuppliedValues(suppliedValues)
      var finalResults: [TypeFileAssessment] = []

      for file in try options.resolvedPaths() {
        let record = try MarkdownRecordFileAdapter.read(file, projectRoot: root)
        let initial = try await checker.assess(record, as: name)
        let diagnostics = initial.diagnostics.filter { diagnostic in
          (includeRecommendations || diagnostic.severity == .error)
            && (constraint == nil || diagnostic.constraintID == constraint)
        }
        let candidates = diagnostics.flatMap(\.fixIts)
        var selected: [MarkdownFixIt] = []
        var resolvedInputs = inputs

        for fixIt in candidates {
          print("\(relativePath(from: root, to: file)): [\(fixIt.safety.rawValue)] \(fixIt.title)")
          if dryRun { continue }
          if yes && fixIt.safety == .requiresInput {
            let requestedPaths = fixIt.edits.compactMap { edit -> String? in
              guard case .requestFrontmatterValue(let path) = edit else { return nil }
              return path.joined(separator: ".")
            }
            let suppliedEveryValue = requestedPaths.isEmpty == false
              && requestedPaths.allSatisfy { resolvedInputs[$0] != nil }
            if suppliedEveryValue == false {
              print("Skipping \(fixIt.id): --yes cannot approve an input-required suggestion without explicit --set values.")
              continue
            }
          }
          let accepted = yes || prompt("Apply this fix? [y/N]")
          guard accepted else { continue }
          var canApply = true
          for edit in fixIt.edits {
            guard case .requestFrontmatterValue(let path) = edit else { continue }
            let key = path.joined(separator: ".")
            if resolvedInputs[key] == nil {
              if yes {
                print("Skipping \(fixIt.id): --yes cannot fabricate a value for \(key).")
                canApply = false
              } else {
                guard let rawValue = readPrompt("Value for \(key): ") else {
                  canApply = false
                  continue
                }
                resolvedInputs[key] = try parseInputValue(rawValue)
              }
            }
          }
          if canApply { selected.append(fixIt) }
        }

        if dryRun {
          finalResults.append(TypeFileAssessment(file: file, assessment: initial))
          continue
        }
        let updated = try MarkdownTypeFixer.apply(selected, to: record, inputs: resolvedInputs)
        if selected.isEmpty == false {
          try MarkdownRecordFileAdapter.write(updated, to: file)
        }
        let final = try await checker.assess(updated, as: name)
        finalResults.append(TypeFileAssessment(file: file, assessment: final))
      }

      print(try TypesRenderer.renderAssessments(
        finalResults,
        format: .text,
        root: root,
        includeOK: true
      ))
      if finalResults.contains(where: { $0.assessment.conforms == false }) {
        throw ExitCode.failure
      }
    }
  }

  struct Schema: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "schema",
      abstract: "Print the md-utils Markdown type-definition JSON Schema"
    )

    @Option(name: .long, help: "Output format: json or yaml")
    var format: TypesDefinitionFormat = .json

    mutating func run() async throws {
      let content = try TypesProject.schemaContent()
      if format == .json {
        print(content, terminator: content.hasSuffix("\n") ? "" : "\n")
      } else {
        guard let data = content.data(using: .utf8) else {
          throw ValidationError("Bundled type schema is not UTF-8")
        }
        print(try Yams.dump(object: JSONSerialization.jsonObject(with: data), sortKeys: true))
      }
    }
  }
}

private func isSemanticVersion(_ value: String) -> Bool {
  value.range(
    of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"#,
    options: .regularExpression
  ) != nil
}

private func prompt(_ message: String) -> Bool {
  guard let value = readPrompt(message) else { return false }
  return ["y", "yes"].contains(value.lowercased())
}

private func readPrompt(_ message: String) -> String? {
  print(message, terminator: "")
  return readLine()
}

private func parseSuppliedValues(_ values: [String]) throws -> [String: JSONValue] {
  var result: [String: JSONValue] = [:]
  for value in values {
    guard let separator = value.firstIndex(of: "=") else {
      throw ValidationError("--set values must use key=value syntax: \(value)")
    }
    let key = String(value[..<separator])
    let rawValue = String(value[value.index(after: separator)...])
    guard key.isEmpty == false else {
      throw ValidationError("--set requires a nonempty key")
    }
    result[key] = try parseInputValue(rawValue)
  }
  return result
}

private func parseInputValue(_ value: String) throws -> JSONValue {
  guard let node = try Yams.compose(yaml: value) else { return .string(value) }
  return try JSONValue(any: YAMLConversion.safeNodeToSwiftValue(node))
}
