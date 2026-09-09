import ArgumentParser
import Foundation
import MarkdownUtilities
import MarkdownUtilitiesCore
import PathKit

/// Conservative migration of required-schema rules, with complete preflight before writes.
enum StandaloneConfigMigration {
  static func migrate(config: MdUtilsConfig, path: Path, root explicitRoot: Path?, dryRun: Bool) throws -> ConfigMigrationResult {
    let path = path.absolute().normalize()
    let root: Path
    if let explicitRoot { root = explicitRoot.absolute().normalize() }
    else if path.lastComponent == "md-utils.json" && path.parent().lastComponent == ".md-utils" {
      root = path.parent().parent()
    } else { throw ValidationError("A nonstandard config location requires --project-root") }
    _ = try config.compiledRuleRegistry(root: root)
    let original = try Data(contentsOf: URL(fileURLWithPath: path.string))
    guard let raw = try JSONSerialization.jsonObject(with: original) as? [String: Any],
      let payloads = raw[config.configVersion == "0.1.0" ? "schemaRules" : "rules"] as? [[String: Any]] else {
      throw ValidationError("Expected embedded legacy rules")
    }
    func encode(_ object: [String: Any]) throws -> Data {
      var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
      data.append(10)
      return data
    }
    var writes: [(Path, Data)] = [(path.parent() + "md-utils.legacy-\(config.configVersion).json", original)]
    var definitions: [MarkdownTypeDefinition] = []
    let existingTypes = (root + ".md-utils/types").exists
      ? try MarkdownTypeFileRegistryLoader.load(projectRoot: root).definitions : []
    let existingRules = try MarkdownRuleFileStore(projectRoot: root).load()
    let legacyNames = Set(config.schemaRules.map(\.name))
    if let unrelated = existingRules.first(where: { !legacyNames.contains($0.name) }) {
      throw ValidationError("Migration would activate an unrelated rule: \(unrelated.source). Move it outside rules/ before retrying.")
    }
    for rule in config.schemaRules {
      let filename = rule.name + ".mdtype.json"
      _ = try MarkdownRuleTypeExpression.decode(.string(filename), source: path.string)
      guard rule.name.contains("/") == false,
        existingRules.contains(where: { $0.name == rule.name && $0.source != (root + ".md-utils/rules/\(rule.name).mdrule.json").string }) == false else {
        throw ValidationError("Migration rule name is unsafe or conflicts with an active rule: \(rule.name)")
      }
      var schemas: [[String: String]] = []
      for check in rule.checks {
        guard case .frontmatterSchema(let schema, let required) = check, required else {
          throw ValidationError("Rule \"\(rule.name)\" cannot be automatically migrated: only required-schema checks currently have a supported conversion. Keep the legacy config or revise the rule manually.")
        }
        let reference = try MarkdownRuleSchemaReferenceMigration.plan(schema: schema,
          schemaDirectory: config.schemaDirectory, projectRoot: root, typeFile: filename)
        schemas.append(["ref": reference.typeRelativeReference])
      }
      guard !schemas.isEmpty else { throw ValidationError("Rule \"\(rule.name)\" has no supported checks") }
      let typePath = root + ".md-utils/types/\(filename)"
      let typeData = try encode([
        "md-utils-type-schema": "1", "name": rule.name, "version": "1.0.0",
        "frontmatter": ["presence": "required", "schemas": schemas],
        "body": ["requirements": [], "recommendations": []],
        "context": ["requirements": [], "recommendations": []],
      ])
      let definition = try MarkdownTypeDefinitionDecoder.decode(String(decoding: typeData, as: UTF8.self), format: .json, source: typePath.string)
      if existingTypes.contains(where: { $0.name == definition.name && $0.source != definition.source }) {
        throw ValidationError("Migration type identity already exists: \(rule.name)")
      }
      definitions.append(definition)
      guard let payload = payloads.first(where: { $0["name"] as? String == rule.name }) else {
        throw ValidationError("Original rule payload not found: \(rule.name)")
      }
      let ruleData = try encode(["name": rule.name, "match": rule.match.jsonObject, "types": filename])
      _ = try MarkdownRuleFile.decode(String(decoding: ruleData, as: UTF8.self), source: rule.name)
      writes.append((typePath, typeData))
      writes.append((root + ".md-utils/rules/legacy/\(rule.name).mdrule.legacy-\(config.configVersion).json", try encode(payload)))
      writes.append((root + ".md-utils/rules/\(rule.name).mdrule.json", ruleData))
    }
    _ = try MarkdownTypeRegistry(definitions: definitions, schemaProvider: FileMarkdownSchemaResourceProvider(projectRoot: root))
    let active = try encode(["configVersion": "0.3.0", "$schema": ConfigSchemaRegistry.publicSchemaURL(for: "0.3.0")])
    let normalizedDestinations = writes.map { $0.0.string.lowercased() }
    guard Set(normalizedDestinations).count == normalizedDestinations.count else {
      throw ValidationError("Migration filenames collide after case normalization; rename the conflicting legacy rules first")
    }
    // Reject symlinks in destination paths; lexical and canonical containment must agree.
    let canonicalRoot = URL(fileURLWithPath: root.string).resolvingSymlinksInPath().path
    for (destination, data) in writes {
      let canonical = URL(fileURLWithPath: destination.string).resolvingSymlinksInPath().path
      guard canonical.hasPrefix(canonicalRoot + "/"), canonical == destination.string else {
        throw ValidationError("Migration destination must remain inside the project without symlinks: \(destination)")
      }
      var parent = destination.parent()
      while parent != root && parent != parent.parent() {
        if parent.exists && !parent.isDirectory {
          throw ValidationError("Migration destination parent is not a directory: \(parent)")
        }
        parent = parent.parent()
      }
      if destination.exists, try Data(contentsOf: URL(fileURLWithPath: destination.string)) != data {
        throw ValidationError("Migration destination has conflicting contents: \(destination)")
      }
    }
    let warnings = [
      "Back up the complete .md-utils/ directory before migrating.",
      "Migrated rules use mdtype diagnostics and newly reject malformed $md-utils.typeHints; correct malformed hint metadata. Valid type hints remain supported.",
      "Writes are not a multi-file transaction. On interruption, the legacy config remains active until the last write. Restore your backup or review generated files before retrying; conflicting files are never overwritten.",
    ]
    if !dryRun {
      var completed: [String] = []
      do {
        for (destination, data) in writes {
          try destination.parent().mkpath()
          if destination.exists {
            guard try Data(contentsOf: URL(fileURLWithPath: destination.string)) == data else {
              throw ValidationError("Migration destination changed after preflight: \(destination)")
            }
          } else {
            try data.write(to: URL(fileURLWithPath: destination.string), options: .withoutOverwriting)
          }
          completed.append(destination.string)
        }
        guard try Data(contentsOf: URL(fileURLWithPath: path.string)) == original else {
          throw ValidationError("Active config changed during migration")
        }
        try active.write(to: URL(fileURLWithPath: path.string), options: .atomic)
      } catch {
        throw ValidationError("Migration interrupted: \(error.localizedDescription). Completed writes/reuses: \(completed.joined(separator: ", ")). Restore your backup or inspect these files before retrying; legacy artifacts have not been deleted.")
      }
    }
    return ConfigMigrationResult(configPath: path.string, from: config.configVersion, to: "0.3.0",
      changed: true, dryRun: dryRun, updatedSchemaReference: true, updatedLocalSchema: false,
      files: writes.map { $0.0.string } + [path.string], warnings: warnings)
  }
}
