//
//  Unique.swift
//  md-utils
//

import ArgumentParser
import Foundation
import JMESPath
import MarkdownUtilitiesCore
import PathKit

extension CLIEntry.FrontMatterCommands {
  /// Checks that a selected frontmatter scalar is unique across Markdown files.
  struct Unique: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "unique",
      abstract: "Check that a frontmatter value is unique across files",
      discussion: """
        Evaluates one JMESPath expression against each file's YAML frontmatter and
        checks that the selected scalar value is unique.

        COLLECTION MODE:
          By default, every duplicate value across the resolved paths is reported.

          md-utils fm unique 'id' notes/
          md-utils fm unique 'metadata.id' foo.md bar.md other-notes/

        REFERENCE MODE:
          Use --reference to compare only one note's value against the resolved
          paths. Unrelated collisions in the comparison set are ignored.

          md-utils fm unique 'id' --reference foo.md notes/

        SCALAR VALUES ONLY:
          The expression must select one string, number, or boolean per note.
          Arrays and objects are unsupported. Array projections such as
          authors[].id are unsupported.

        MISSING VALUES:
          Missing and null results are skipped by default. Use --require-value to
          require a selected value in every checked note.

        JMESPATH AND SHELL QUOTING:
          Simple selectors such as id and metadata.id are safe unquoted. Still,
          single-quote the entire expression so Bash and Zsh preserve JMESPath
          syntax exactly:

          md-utils fm unique 'id' notes/
          md-utils fm unique 'metadata.id' notes/
          md-utils fm unique '"record-id"' notes/
          md-utils fm unique 'to_string(id)' notes/

          Richer expressions may contain shell-active syntax such as backticks,
          &&, ||, |, !, parentheses, wildcards, or quoted identifiers. Do not use
          double quotes around expressions containing JMESPath backtick literals;
          Bash and Zsh interpret backticks as command substitution.

        EXIT STATUS:
          Exits successfully only when the requested uniqueness invariant holds,
          required values are present, and every file was evaluated successfully.
        """
    )

    @Argument(help: "JMESPath expression selecting one scalar frontmatter value")
    var expression: String

    @OptionGroup var options: GlobalOptions
    @OptionGroup var frontmatterSource: FrontMatterSourceOptions

    @Option(
      name: .long,
      help: "Compare only this note's selected value against the resolved paths",
      completion: .file(),
      transform: { Path($0) }
    )
    var reference: Path?

    @Flag(name: .long, help: "Fail when any checked note has a missing or null result")
    var requireValue = false

    @Option(name: .long, help: "Output format: text, json, or yaml")
    var format: UniqueOutputFormat = .text

    mutating func run() async throws {
      let compiledExpression: JMESExpression
      do {
        compiledExpression = try FrontMatterJMESPath.compile(expression)
      } catch {
        throw ValidationError("""
          Invalid JMESPath expression: "\(expression)"
          \(FrontMatterJMESPath.message(for: error))

          See https://jmespath.org for syntax reference
          """)
      }

      let reader = try frontmatterSource.makeReader()
      let resolved = try options.resolvedPaths(includeAllExtensions: frontmatterSource.includeNonMarkdown)
      guard resolved.isEmpty == false else {
        throw ValidationError("No Markdown files found to process")
      }

      let files = UniquePathResolver.canonicalized(resolved, sort: options.noSort == false)
      let referencePath = try reference.map(UniquePathResolver.validateReference)
      let comparisonFiles: [Path]
      if let referencePath {
        comparisonFiles = files.filter { $0.string != referencePath.string }
      } else {
        comparisonFiles = files
      }

      let report = UniqueAnalyzer.analyze(
        expression: expression,
        compiledExpression: compiledExpression,
        files: comparisonFiles,
        reference: referencePath,
        reader: reader
      )
      print(try UniqueRenderer.render(report, format: format, requireValue: requireValue))

      if report.hasFailure(requireValue: requireValue) {
        throw ExitCode.failure
      }
    }
  }
}

enum UniqueOutputFormat: String, ExpressibleByArgument {
  case text
  case json
  case yaml
}

enum UniqueMode: String {
  case collection
  case reference
}

enum UniqueValueType: String {
  case string
  case number
  case boolean
}

enum UniqueScalar: Hashable {
  case string(String)
  case number(Decimal)
  case boolean(Bool)

  var type: UniqueValueType {
    switch self {
    case .string: return .string
    case .number: return .number
    case .boolean: return .boolean
    }
  }

  var foundationValue: Any {
    switch self {
    case .string(let value): return value
    case .number(let value): return NSDecimalNumber(decimal: value)
    case .boolean(let value): return value
    }
  }

  var displayValue: String {
    switch self {
    case .string(let value):
      let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
      return "\"\(escaped)\""
    case .number(let value):
      return NSDecimalNumber(decimal: value).stringValue
    case .boolean(let value):
      return value ? "true" : "false"
    }
  }

  var sortKey: String {
    "\(type.rawValue):\(displayValue)"
  }

  static func scalar(from value: Any?) throws -> UniqueScalar? {
    guard let value else { return nil }
    if value is NSNull { return nil }
    if let value = value as? Bool { return .boolean(value) }
    if let value = value as? String { return .string(value) }
    if let value = value as? NSNumber {
      let decimal = value.decimalValue
      guard decimal.isNaN == false, value.doubleValue.isFinite else {
        throw UniqueEvaluationError.nonFiniteNumber
      }
      return .number(decimal)
    }
    if value is [Any] {
      throw UniqueEvaluationError.unsupportedResult("array")
    }
    if value is [String: Any] {
      throw UniqueEvaluationError.unsupportedResult("object")
    }
    throw UniqueEvaluationError.unsupportedResult(String(describing: Swift.type(of: value)))
  }
}

enum UniqueEvaluationError: LocalizedError {
  case unsupportedResult(String)
  case nonFiniteNumber

  var errorDescription: String? {
    switch self {
    case .unsupportedResult(let type):
      return "JMESPath result is an unsupported \(type); select one string, number, or boolean"
    case .nonFiniteNumber:
      return "JMESPath result is a non-finite number; select a finite number"
    }
  }
}

struct UniqueCollision {
  var value: UniqueScalar
  var paths: [String]

  var foundationObject: [String: Any] {
    [
      "valueType": value.type.rawValue,
      "value": value.foundationValue,
      "paths": paths,
    ]
  }
}

struct UniqueDiagnostic {
  var path: String
  var message: String

  var foundationObject: [String: Any] {
    ["path": path, "message": message]
  }
}

struct UniqueReport {
  var expression: String
  var mode: UniqueMode
  var referencePath: String?
  var checkedFiles: Int
  var filesWithValue: Int
  var missingPaths: [String]
  var collisions: [UniqueCollision]
  var diagnostics: [UniqueDiagnostic]

  func hasFailure(requireValue: Bool) -> Bool {
    collisions.isEmpty == false
      || diagnostics.isEmpty == false
      || (requireValue && missingPaths.isEmpty == false)
  }

  var foundationObject: [String: Any] {
    var result: [String: Any] = [
      "expression": expression,
      "mode": mode.rawValue,
      "checkedFiles": checkedFiles,
      "filesWithValue": filesWithValue,
      "missingPaths": missingPaths,
      "collisions": collisions.map(\.foundationObject),
      "diagnostics": diagnostics.map(\.foundationObject),
    ]
    if let referencePath {
      result["referencePath"] = referencePath
    }
    return result
  }
}

enum UniquePathResolver {
  static func canonicalized(_ paths: [Path], sort: Bool) -> [Path] {
    var seen: Set<String> = []
    var result: [Path] = []
    for path in paths {
      let canonical = canonical(path)
      if seen.insert(canonical.string).inserted {
        result.append(canonical)
      }
    }
    if sort {
      result.sort { $0.string < $1.string }
    }
    return result
  }

  static func validateReference(_ path: Path) throws -> Path {
    guard path.exists else {
      throw ValidationError("Reference path does not exist: \(path.string)")
    }
    guard path.isFile else {
      throw ValidationError("Reference path is not a file: \(path.string)")
    }
    return canonical(path)
  }

  private static func canonical(_ path: Path) -> Path {
    let normalized = path.absolute().normalize()
    return Path(URL(fileURLWithPath: normalized.string).resolvingSymlinksInPath().path)
  }
}

enum UniqueAnalyzer {
  static func analyze(
    expression: String,
    compiledExpression: JMESExpression,
    files: [Path],
    reference: Path?,
    reader: FrontMatterFileReader? = nil
  ) -> UniqueReport {
    let evaluations = files.map { evaluate($0, using: compiledExpression, reader: reader) }
    let missingPaths = evaluations.compactMap { evaluation in
      evaluation.isMissing ? evaluation.path : nil
    }
    let diagnostics = evaluations.compactMap(\.diagnostic)
    let filesWithValue = evaluations.filter { $0.value != nil }.count

    let collisions: [UniqueCollision]
    if let reference {
      let referenceEvaluation = evaluate(reference, using: compiledExpression, reader: reader)
      var combinedMissing = missingPaths
      var combinedDiagnostics = diagnostics
      if referenceEvaluation.isMissing {
        combinedMissing.append(referenceEvaluation.path)
      }
      if let diagnostic = referenceEvaluation.diagnostic {
        combinedDiagnostics.append(diagnostic)
      }

      if let referenceValue = referenceEvaluation.value {
        let matches = evaluations.filter { $0.value == referenceValue }.map(\.path)
        if matches.isEmpty {
          collisions = []
        } else {
          collisions = [UniqueCollision(
            value: referenceValue,
            paths: ([referenceEvaluation.path] + matches).sorted()
          )]
        }
      } else {
        collisions = []
      }

      return UniqueReport(
        expression: expression,
        mode: .reference,
        referencePath: reference.string,
        checkedFiles: files.count,
        filesWithValue: filesWithValue,
        missingPaths: combinedMissing.sorted(),
        collisions: collisions,
        diagnostics: combinedDiagnostics.sorted { lhs, rhs in
          lhs.path == rhs.path ? lhs.message < rhs.message : lhs.path < rhs.path
        }
      )
    }

    var grouped: [UniqueScalar: [String]] = [:]
    for evaluation in evaluations {
      guard let value = evaluation.value else { continue }
      grouped[value, default: []].append(evaluation.path)
    }
    collisions = grouped.compactMap { value, paths in
      guard paths.count > 1 else { return nil }
      return UniqueCollision(value: value, paths: paths.sorted())
    }.sorted { lhs, rhs in
      lhs.value.sortKey < rhs.value.sortKey
    }

    return UniqueReport(
      expression: expression,
      mode: .collection,
      referencePath: nil,
      checkedFiles: files.count,
      filesWithValue: filesWithValue,
      missingPaths: missingPaths.sorted(),
      collisions: collisions,
      diagnostics: diagnostics.sorted { lhs, rhs in
        lhs.path == rhs.path ? lhs.message < rhs.message : lhs.path < rhs.path
      }
    )
  }

  private static func evaluate(
    _ path: Path,
    using expression: JMESExpression,
    reader: FrontMatterFileReader?
  ) -> UniqueFileEvaluation {
    do {
      let document = if let reader {
        try reader.document(at: path)
      } else {
        try MarkdownDocument(content: path.read(.utf8))
      }
      let object = try FrontMatterJMESPath.object(from: document)
      let result = try expression.search(object: object)
      let scalar = try UniqueScalar.scalar(from: result)
      return UniqueFileEvaluation(path: path.string, value: scalar, isMissing: scalar == nil, diagnostic: nil)
    } catch {
      return UniqueFileEvaluation(
        path: path.string,
        value: nil,
        isMissing: false,
        diagnostic: UniqueDiagnostic(path: path.string, message: error.localizedDescription)
      )
    }
  }
}

private struct UniqueFileEvaluation {
  var path: String
  var value: UniqueScalar?
  var isMissing: Bool
  var diagnostic: UniqueDiagnostic?
}

enum UniqueRenderer {
  static func render(
    _ report: UniqueReport,
    format: UniqueOutputFormat,
    requireValue: Bool
  ) throws -> String {
    switch format {
    case .text:
      return renderText(report, requireValue: requireValue)
    case .json:
      return try YAMLConversion.anyToJSON(report.foundationObject, options: [.prettyPrinted, .sortedKeys])
    case .yaml:
      return try YAMLConversion.anyToYAML(report.foundationObject)
    }
  }

  private static func renderText(_ report: UniqueReport, requireValue: Bool) -> String {
    var lines: [String] = []

    for collision in report.collisions {
      lines.append(
        "\(CLIStyle.error("✗")) \(report.expression) = \(collision.value.displayValue) occurs in \(collision.paths.count) files"
      )
      lines.append(contentsOf: collision.paths.map { "    \(CLIStyle.path($0))" })
      lines.append("")
    }

    if requireValue, report.missingPaths.isEmpty == false {
      lines.append(
        "\(CLIStyle.error("✗")) \(report.missingPaths.count) file(s) had a missing or null value for \"\(report.expression)\""
      )
      lines.append(contentsOf: report.missingPaths.map { "    \(CLIStyle.path($0))" })
      lines.append("")
    }

    for diagnostic in report.diagnostics {
      lines.append(
        "\(CLIStyle.error("✗")) \(CLIStyle.path(diagnostic.path)): \(CLIStyle.error(diagnostic.message))"
      )
    }
    if report.diagnostics.isEmpty == false {
      lines.append("")
    }

    if report.hasFailure(requireValue: requireValue) == false {
      if report.mode == .reference, let referencePath = report.referencePath {
        lines.append(
          "\(CLIStyle.success("✓")) Value selected by \"\(report.expression)\" in \(CLIStyle.path(referencePath)) is unique"
        )
      } else {
        lines.append(
          "\(CLIStyle.success("✓")) All \(report.filesWithValue) values selected by \"\(report.expression)\" are unique"
        )
      }
    }

    let collisionLabel = report.collisions.count == 1 ? "collision group" : "collision groups"
    lines.append(
      CLIStyle.metadata(
        "Checked \(report.checkedFiles) files: \(report.filesWithValue) values, \(report.missingPaths.count) missing, \(report.collisions.count) \(collisionLabel)"
      )
    )
    return lines.joined(separator: "\n")
  }
}
