import Foundation

/// An explicit preference only selects among outputs permitted by a loaded contract.
public struct WikilinkContractPreferences: Sendable {
  public var style: String?
  public var markdownExtension: String?
  public var keys: [String]
  public var includeRecommendations: Bool

  public init(style: String? = nil, markdownExtension: String? = nil,
    keys: [String] = [], includeRecommendations: Bool = false,
  ) {
    self.style = style
    self.markdownExtension = markdownExtension
    self.keys = keys
    self.includeRecommendations = includeRecommendations
  }
}

/// One declared whole-value occurrence; paths distinguish literal keys from indices.
public struct WikilinkContractChange: Codable, Equatable, Sendable {
  public let path: [WikilinkPropertyComponent]
  public let original: JSONValue
  public var replacement: String?
  public var status: String
  public var reason: String?
  public let declarations: [String]
}

/// Portable conversion result, independent of filesystem reads and persistence.
public struct WikilinkContractPlan: Sendable {
  public let source: MarkdownRecord
  public var proposed: MarkdownRecord
  public var changes: [WikilinkContractChange]
  public var hasChanges: Bool { !source.content.utf8.elementsEqual(proposed.content.utf8) }
  public var unresolved: Bool { changes.contains { $0.status == "unresolved" } }

  /// Reject the combined edit without losing the occurrence-level preview evidence.
  public mutating func reject(_ reason: String) {
    proposed = source
    for index in changes.indices where changes[index].replacement != nil {
      changes[index].status = "unresolved"
      changes[index].reason = reason
    }
  }
}

/// Plans bounded lexical repairs using schema-directed occurrences and supplied
/// destination evidence. Schema validity remains owned by the existing adapter.
public enum WikilinkContractConversion {
  public static func plan(record: MarkdownRecord, type: String, registry: MarkdownTypeRegistry,
    resolver: CollectionWikilinkResolver, preferences: WikilinkContractPreferences = .init(),
  ) async throws -> WikilinkContractPlan {
    guard let definition = registry.definition(named: type), definition.typeSchemaVersion == "2",
      let source = record.context.path?.rawValue else {
      throw MarkdownTypeDefinitionError.invalidField("Contract conversion requires a loaded mdtype v2 and a source path")
    }
    guard preferences.style.map({ ["name", "vault-path", "relative-path", "self-anchor"].contains($0) }) ?? true,
      preferences.markdownExtension.map({ ["include", "omit"].contains($0) }) ?? true else {
      throw MarkdownTypeDefinitionError.invalidField("Invalid contract conversion preference")
    }
    let analyzed = await MarkdownRecordAnalyzer.analyze(record)
    guard analyzed.parseDiagnostics.isEmpty else {
      throw MarkdownTypeDefinitionError.invalidField("Cannot convert malformed Markdown/frontmatter")
    }
    let instance = JSONValue.object(analyzed.userFrontmatter ?? [:])
    let required = registry.resolvedSchemas(for: definition.name)
    let schemas = required + (preferences.includeRecommendations ? registry.resolvedRecommendedSchemas(for: definition.name) : [])
    var walker = ContractWalker()
    for (index, schema) in schemas.enumerated() {
      let location = "\(definition.source ?? type)#frontmatter/\(index < required.count ? "schemas/\(index)" : "recommendedSchemas/\(index - required.count)")"
      let context = SemanticSchemaDiagnostics(root: schema, instance: instance, nativePaths: analyzed.nativeTemporalPaths,
        severity: .error, constraint: location, source: definition.source)
      try walker.walk(schema, value: instance, path: [], location: location, base: "", context: context)
    }
    var changes: [WikilinkContractChange] = []
    var edits: [MarkdownRecordEdit] = []
    for slot in walker.slots {
      try Task.checkCancellation()
      if !preferences.keys.isEmpty {
        guard case .key(let key)? = slot.path.first, preferences.keys.contains(key) else { continue }
      }
      var change = WikilinkContractChange(path: slot.path, original: slot.value, replacement: nil,
        status: "unchanged", reason: nil, declarations: slot.checks.map(\.location).sorted())
      if let blocked = slot.blocked {
        change.status = "unresolved"; change.reason = blocked
      } else if let text = slot.value.stringValue, let link = try? Wikilink.parse(text, context: .standard) {
        if try slot.accepts(link.rawValue) {
          changes.append(change); continue
        }
        guard let destination = resolver.resolve(target: link.target, from: source).destination else {
          change.status = "unresolved"; change.reason = "Original destination is missing, ambiguous, or unavailable"
          changes.append(change); continue
        }
        var candidates: [String] = []
        for target in spellings(destination: destination, source: source, hasAnchor: link.anchor != nil) {
          let replacement = WikilinkRewriter.rewrite(text) { _ in target }
          guard let parsed = try? Wikilink.parse(replacement, context: .standard),
            parsed.target == target, parsed.anchor == link.anchor, parsed.displayText == link.displayText,
            parsed.isEmbed == link.isEmbed,
            resolver.resolve(target: target, from: source).destination == destination,
            try slot.accepts(replacement) else { continue }
          if let style = preferences.style {
            let preference = try WikilinkStylePolicy(.object(["styles": .array([.string(style)])]), path: "preference")
            if !preference.failures(parsed).isEmpty { continue }
          }
          if let ext = preferences.markdownExtension, destination.hasSuffix(".md") || destination.hasSuffix(".markdown") {
            let hasExtension = target.hasSuffix(".md") || target.hasSuffix(".markdown")
            if hasExtension != (ext == "include") { continue }
          }
          if !candidates.contains(replacement) { candidates.append(replacement) }
        }
        if candidates.count == 1, let replacement = candidates.first {
          change.replacement = replacement; change.status = "would-change"
          edits.append(.setFrontmatterOccurrence(path: slot.path, value: .string(replacement)))
        } else {
          change.status = "unresolved"
          change.reason = candidates.isEmpty ? "No representable, destination-preserving output satisfies the contract and preferences"
            : "Multiple permissible outputs; supply an explicit style and/or Markdown extension preference"
        }
      } else {
        change.status = "unresolved"; change.reason = "Declared value is not a whole standard-context wikilink"
      }
      changes.append(change)
    }
    let proposed = edits.isEmpty ? record : try MarkdownTypeFixer.apply([
      .init(id: "wikilink-contract", title: "Convert declared wikilinks", safety: .requiresInput, edits: edits),
    ], to: record)
    return .init(source: record, proposed: proposed, changes: changes)
  }

  private static func spellings(destination: String, source: String, hasAnchor: Bool) -> [String] {
    var from = source.split(separator: "/").dropLast().map(String.init)
    var to = destination.split(separator: "/").map(String.init)
    let name = to.last ?? destination
    while !from.isEmpty && !to.isEmpty && from.first == to.first { from.removeFirst(); to.removeFirst() }
    let relative = (from.isEmpty ? "./" : String(repeating: "../", count: from.count)) + to.joined(separator: "/")
    var targets = [name, relative]
    if destination.contains("/") { targets.append(destination) }
    if destination == source && hasAnchor { targets.append("") }
    return targets.flatMap { target in
      if target.hasSuffix(".markdown") { return [target, String(target.dropLast(9))] }
      if target.hasSuffix(".md") { return [target, String(target.dropLast(3))] }
      return [target]
    }
  }
}

private struct ContractCheck {
  let schema: JSONValue
  let context: SemanticSchemaDiagnostics
  let base: String
  let location: String
}

private struct ContractSlot {
  let path: [WikilinkPropertyComponent]
  let value: JSONValue
  var checks: [ContractCheck]
  var blocked: String?

  func accepts(_ text: String) throws -> Bool {
    for check in checks {
      if try !check.context.valid(check.schema, value: .string(text), path: pointer, base: check.base) { return false }
    }
    return true
  }

  var pointer: String { path.map { component in
    switch component { case .key(let key): "/" + SemanticSchemaAdapter.escape(key); case .index(let index): "/\(index)" }
  }.joined() }
}

/// Walk only schema-owned value positions. Alternative/negative/existential
/// ambiguity is explicit; a failed sibling is never made a mandatory policy.
private struct ContractWalker {
  var slots: [ContractSlot] = []
  var slotIndices: [[WikilinkPropertyComponent]: Int] = [:]
  var remaining = 100_000

  mutating func walk(_ schema: JSONValue, value: JSONValue, path: [WikilinkPropertyComponent],
    location: String, base: String, context: SemanticSchemaDiagnostics, blocked: String? = nil, depth: Int = 0,
  ) throws {
    try Task.checkCancellation()
    remaining -= 1
    guard remaining >= 0, depth < 128 else { throw MarkdownTypeDefinitionError.invalidField("Contract conversion schema budget exceeded") }
    guard let object = schema.objectValue else { return }
    let base = object["$id"]?.stringValue ?? base
    let pointer = ContractSlot(path: path, value: value, checks: []).pointer
    if ["Wikilink", "Wikilink/Obsidian"].contains(object["format"]?.stringValue ?? "") {
      let check = ContractCheck(schema: schema, context: context, base: base, location: location)
      if let index = slotIndices[path] {
        slots[index].checks.append(check)
        slots[index].blocked = slots[index].blocked ?? blocked
      } else {
        slotIndices[path] = slots.count
        slots.append(.init(path: path, value: value, checks: [check], blocked: blocked))
      }
    }
    if let ref = object["$ref"]?.stringValue {
      let absolute = ref.hasPrefix("#") ? base + ref : ref
      guard let resolved = context.resolve(absolute) else { throw MarkdownTypeDefinitionError.invalidField("Unresolved conversion schema: \(absolute)") }
      try walk(resolved, value: value, path: path, location: absolute, base: String(absolute.split(separator: "#", omittingEmptySubsequences: false).first ?? ""),
        context: context, blocked: blocked, depth: depth + 1)
    }
    if case .array(let branches)? = object["allOf"] {
      for (index, child) in branches.enumerated() {
        try walk(child, value: value, path: path, location: location + "/allOf/\(index)", base: base,
          context: context, blocked: blocked, depth: depth + 1)
      }
    }
    for keyword in ["anyOf", "oneOf"] {
      guard case .array(let branches)? = object[keyword] else { continue }
      // Already satisfied alternatives need no repair, even if other branches fail.
      if try context.valid(.object([keyword: .array(branches)]), value: value, path: pointer, base: base) {
        let valid = try branches.indices.filter { try context.valid(branches[$0], value: value, path: pointer, base: base) }
        if valid.count == 1, let index = valid.first {
          try walk(branches[index], value: value, path: path, location: location + "/\(keyword)/\(index)", base: base,
            context: context, blocked: blocked, depth: depth + 1)
        }
        continue
      }
      var eligible: [Int] = []
      for (index, child) in branches.enumerated() {
        let expanded = try context.expanded(child, base: base, depth: 0)
        let relaxed = try SemanticSchemaAdapter.transform(expanded) { object, _ in
          var object = object; object.removeValue(forKey: "wikilink"); return object
        }
        if try context.valid(relaxed, value: value, path: pointer) { eligible.append(index) }
      }
      let selected = eligible.count == 1 ? eligible : Array(branches.indices)
      for index in selected {
        try walk(branches[index], value: value, path: path, location: location + "/\(keyword)/\(index)", base: base,
          context: context, blocked: blocked ?? (eligible.count == 1 ? nil : "Schema alternatives do not establish unique rewrite intent"), depth: depth + 1)
      }
    }
    if let condition = object["if"] {
      let branch = try context.valid(condition, value: value, path: pointer, base: base) ? "then" : "else"
      if let child = object[branch] {
        var linkCondition = false
        _ = try SemanticSchemaAdapter.transform(context.expanded(condition, base: base, depth: 0)) { object, _ in
          if object["wikilink"] != nil || ["Wikilink", "Wikilink/Obsidian"].contains(object["format"]?.stringValue ?? "") { linkCondition = true }
          return object
        }
        try walk(child, value: value, path: path, location: location + "/" + branch, base: base, context: context,
          blocked: blocked ?? (linkCondition ? "Link-dependent condition requires review" : nil), depth: depth + 1)
      }
    }
    if let child = object["not"], try !context.valid(.object(["not": child]), value: value, path: pointer, base: base) {
      try walk(child, value: value, path: path, location: location + "/not", base: base, context: context,
        blocked: blocked ?? "Negated declarations do not authorize a rewrite", depth: depth + 1)
    }
    if case .object(let values) = value {
      let properties = object["properties"]?.objectValue ?? [:]
      let patterns = object["patternProperties"]?.objectValue ?? [:]
      for (key, child) in values.sorted(by: { $0.key < $1.key }) {
        var children: [(String, JSONValue)] = []
        if let property = properties[key] { children.append(("properties/" + SemanticSchemaAdapter.escape(key), property)) }
        for pattern in patterns.keys.sorted() where key.range(of: pattern, options: .regularExpression) != nil {
          if let property = patterns[pattern] { children.append(("patternProperties/" + SemanticSchemaAdapter.escape(pattern), property)) }
        }
        if children.isEmpty, let additional = object["additionalProperties"] { children.append(("additionalProperties", additional)) }
        for (name, childSchema) in children {
          try walk(childSchema, value: child, path: path + [.key(key)], location: location + "/" + name,
            base: base, context: context, blocked: blocked, depth: depth + 1)
        }
      }
      for key in (object["dependentSchemas"]?.objectValue ?? [:]).keys.sorted() where values[key] != nil {
        if let child = object["dependentSchemas"]?.objectValue?[key] {
          try walk(child, value: value, path: path, location: location + "/dependentSchemas/" + SemanticSchemaAdapter.escape(key),
            base: base, context: context, blocked: blocked, depth: depth + 1)
        }
      }
    }
    if case .array(let values) = value {
      for keyword in ["items", "contains"] {
        guard let child = object[keyword] else { continue }
        if keyword == "contains", try context.valid(.object(["contains": child]), value: value, path: pointer, base: base) { continue }
        for (index, item) in values.enumerated() {
          try walk(child, value: item, path: path + [.index(index)], location: location + "/" + keyword,
            base: base, context: context, blocked: blocked ?? (keyword == "contains" ? "Existential array constraints do not select repair occurrences" : nil), depth: depth + 1)
        }
      }
    }
  }
}
