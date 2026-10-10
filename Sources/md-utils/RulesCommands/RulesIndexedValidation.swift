import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesIndexNative
import PathKit

extension RulesValidatorRunner {
  /// Uses an existing cache as an optimization; authoritative validation remains available.
  static func validate(
    ruleName: String? = nil,
    includeNonMarkdown: Bool = false,
    root: Path = .current,
    configPath: Path = RulesPaths.configFile,
    projectRoot: Path? = nil,
    noIndex: Bool = false,
    verifyHashes: Bool = false,
    warning: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
  ) async throws -> RuleValidationSummary {
    try Task.checkCancellation()
    let config = try MdUtilsConfig.load(from: configPath, projectRoot: projectRoot)
    let resolvedRoot = config.standaloneProject?.projectRoot ?? projectRoot ?? root
    let rules = try selectedRules(config: config, ruleName: ruleName)
    let canonicalRoot = URL(fileURLWithPath: resolvedRoot.absolute().normalize().string).resolvingSymlinksInPath()
    let databasePath = canonicalRoot.appendingPathComponent(".md-utils/index.sqlite").path
    let hasIndex = FileManager.default.fileExists(atPath: databasePath)
    if hasIndex && !noIndex && !rules.isEmpty {
      do {
        let directory = canonicalRoot.appendingPathComponent(".md-utils/", isDirectory: true)
        guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path,
          URL(fileURLWithPath: databasePath).resolvingSymlinksInPath().path == databasePath else {
          throw IndexProjectError("The project index must not be a symlink.")
        }
        let database = try SQLiteIndexDatabase(path: databasePath)
        let cached = try await IndexedRuleValidation.validate(database: database, root: Path(canonicalRoot.path),
          configPath: configPath, ruleNames: rules.map(\.name), includeNonMarkdown: includeNonMarkdown,
          verifyHashes: verifyHashes)
        let schemaPaths = Dictionary(uniqueKeysWithValues: rules.map { rule in
          (rule.name, rule.schema.isEmpty ? "" : RulesPaths.schemaFile(rule: rule, config: config, root: resolvedRoot).string)
        })
        let ruleOrder = Dictionary(uniqueKeysWithValues: rules.enumerated().map { ($0.element.name, $0.offset) })
        let results = cached.results.map { result in
          let status: RuleValidationResult.Status = switch result.status {
          case .passed: .ok
          case .skipped: .skipped
          case .failed, .notApplicable: .error
          }
          return RuleValidationResult(ruleName: result.ruleName, schemaPath: schemaPaths[result.ruleName] ?? "",
            filePath: result.path, status: status,
            errors: status == .skipped ? [RuleValidationErrorDetail(path: "frontmatter", message: "not present")]
              : result.diagnostics.map { RuleValidationErrorDetail(path: $0.location,
                message: validationMessage(code: $0.code, message: $0.message)) })
        }.sorted {
          if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
          return (ruleOrder[$0.ruleName] ?? 0) < (ruleOrder[$1.ruleName] ?? 0)
        }
        return RuleValidationSummary(results: results, totalFiles: cached.totalFiles, indexReport: cached.report)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        try Task.checkCancellation()
        warning("Warning: index validation unavailable (\(error)); validating source files directly.")
      }
    }
    let summary = try await validateDirect(ruleName: ruleName, includeNonMarkdown: includeNonMarkdown,
      root: root, configPath: configPath, projectRoot: projectRoot)
    if !hasIndex && !noIndex && summary.totalFiles > 1_000 && !rules.isEmpty {
      let options = " --config \(shellQuote(configPath.absolute().normalize().string)) --project-root \(shellQuote(canonicalRoot.path + "/"))"
        + (includeNonMarkdown ? " --include-non-md" : "")
      let commands = rules.map { "md-utils index rule \(shellQuote($0.name))\(options)" }.joined(separator: "\n  ")
      warning("Tip: scanned \(summary.totalFiles) files without an index. An index can speed up repeated validation. Create rule scopes with:\n  \(commands)")
    }
    return summary
  }

  private static func selectedRules(config: MdUtilsConfig, ruleName: String?) throws -> [Rule] {
    guard let ruleName else { return config.schemaRules }
    guard let rule = config.schemaRules.first(where: { $0.name == ruleName }) else {
      throw ValidationError("Rule not found: \"\(ruleName)\"")
    }
    return [rule]
  }

  static func validationMessage(code: String, message: String) -> String {
    switch code {
    case "record.frontmatter.invalid-yaml": message.replacingOccurrences(of: "Invalid YAML:", with: "invalid YAML:")
    case "record.frontmatter.invalid-toml": message.replacingOccurrences(of: "Invalid TOML:", with: "invalid TOML:")
    default: message
    }
  }

  private static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
