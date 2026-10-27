import Foundation
import Parsing

/// An observed frontmatter state, independent of any declared type requirements.
public enum MarkdownSurveyState: String, Codable, Sendable {
  case absent, parsed, malformed, unsupported, binary
}

/// Invalid statistical requests are usage failures, not document findings.
public enum MarkdownSurveyError: Error, Equatable {
  case invalidPointer
  case invalidOptions
}

/// A typed observed value. Temporal paths retain evidence lost in the JSON projection.
public struct MarkdownSurveyValue: Codable, Equatable, Sendable {
  public var value: JSONValue
  public var kind: String
  public var temporalKinds: [String: String]

  /// Stable typed identity preserves container order and nested temporal distinctions.
  package func identity() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(self), as: UTF8.self)
  }
}

/// Portable evidence for a single file; safe to persist without retaining its body.
public struct MarkdownSurveyObservation: Codable, Sendable {
  public var path: String
  public var state: MarkdownSurveyState
  public var frontmatter: [String: JSONValue]?
  public var nativeTemporalPaths: Set<String>
  public var nativeTemporalKinds: [String: String]
  public var format: FrontMatterFormat?
  public var diagnostics: [MarkdownDiagnostic]

  /// Reuses the existing host-file parsers without interpreting declarations as syntax errors.
  public static func read(_ record: MarkdownRecord) async throws -> Self {
    try Task.checkCancellation()
    guard let path = record.context.path?.rawValue else { throw MarkdownSurveyError.invalidOptions }
    let analyzed = await MarkdownRecordAnalyzer.analyze(
      record, requirements: [],
      contentKind: .rulesKind(forFileName: path),
    )
    try Task.checkCancellation()
    return fromAnalysis(analyzed, path: path)
  }

  package static func fromAnalysis(_ analyzed: AnalyzedMarkdownRecord, path: String) -> Self {
    let syntaxErrors = analyzed.parseDiagnostics.filter { $0.code.hasPrefix("record.frontmatter.") }
    let state: MarkdownSurveyState
    if analyzed.record.content.utf8.contains(0)
      || isNonText(Data(analyzed.record.content.utf8.prefix(8192))) { state = .binary }
    else if analyzed.unavailableFrontmatterExtension != nil { state = .unsupported }
    else if !syntaxErrors.isEmpty { state = .malformed }
    else { state = analyzed.hasFrontmatter ? .parsed : .absent }
    return Self(
      path: path, state: state,
      frontmatter: state == .parsed ? (analyzed.relationshipFrontmatter ?? [:]) : nil,
      nativeTemporalPaths: analyzed.nativeTemporalPaths, nativeTemporalKinds: analyzed.nativeTemporalKinds,
      format: analyzed.frontmatterFormat, diagnostics: syntaxErrors,
    )
  }

  /// Recognize common attachment signatures and NUL bytes without relying on extensions.
  /// Invalid UTF-8 alone is not proof of non-text: it can be another text encoding.
  package static func isNonText(_ prefix: Data) -> Bool {
    let signatures: [[UInt8]] = [
      Array("%PDF-".utf8), [0x89, 0x50, 0x4e, 0x47], [0xff, 0xd8, 0xff],
      Array("GIF87a".utf8), Array("GIF89a".utf8), [0x50, 0x4b, 0x03, 0x04],
      [0x50, 0x4b, 0x05, 0x06], [0x1f, 0x8b],
    ]
    return prefix.contains(0) || signatures.contains { prefix.starts(with: $0) }
  }

  /// Reads a literal top-level key, or an explicitly selected RFC 6901 pointer.
  public func value(at key: String, pointer: Bool = false) throws -> MarkdownSurveyValue? {
    let components = try pointer ? SurveyPointerParser.components(key) : [key]
    guard let frontmatter else { return nil }
    var value = JSONValue.object(frontmatter)
    var path = ""
    for component in components {
      switch value {
      case .object(let object):
        guard let child = object[component] else { return nil }
        value = child
      case .array(let array):
        guard let index = Int(component), index >= 0, String(index) == component,
          array.indices.contains(index) else { return nil }
        value = array[index]
      default: return nil
      }
      path += "/" + Self.escape(component)
    }
    return observed(value, path: path)
  }

  package func observed(_ value: JSONValue, path: String) -> MarkdownSurveyValue {
    let kind: String
    if let temporal = nativeTemporalKinds[path] { kind = temporal }
    else {
      switch value {
      case .null: kind = "null"
      case .boolean: kind = "boolean"
      case .integer: kind = "integer"
      case .number: kind = "number"
      case .string: kind = "string"
      case .array: kind = "array"
      case .object: kind = "object"
      }
    }
    return MarkdownSurveyValue(
      value: value, kind: kind,
      temporalKinds: Dictionary(uniqueKeysWithValues: nativeTemporalKinds.filter { $0.key == path || $0.key.hasPrefix(path + "/") }
        .map { (String($0.key.dropFirst(path.count)), $0.value) }),
    )
  }

  package static func escape(_ key: String) -> String {
    key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
  }
}

/// Concrete JSON Pointer grammar. No dotted-key guessing or wildcard expansion.
package struct SurveyPointerParser: Parser {
  package static func components(_ value: String) throws -> [String] {
    var input = Substring(value)
    return try Self().parse(&input)
  }
  package func parse(_ input: inout Substring) throws -> [String] {
    guard input.isEmpty || input.first == "/" else { throw MarkdownSurveyError.invalidPointer }
    var components: [String] = []
    while !input.isEmpty {
      input.removeFirst()
      var component = ""
      while let character = input.first, character != "/" {
        input.removeFirst()
        if character == "~" {
          guard let escape = input.first, escape == "0" || escape == "1" else {
            throw MarkdownSurveyError.invalidPointer
          }
          input.removeFirst()
          component.append(escape == "0" ? "~" : "/")
        } else { component.append(character) }
      }
      components.append(component)
    }
    return components
  }
}

/// Key prevalence with all denominators retained, even when presentation is bounded.
public struct MarkdownSurveyKey: Codable, Sendable {
  public var key: String
  public var present = 0
  public var missing = 0
  public var unassessable = 0
  public var kinds: [String: Int] = [:]
  public var outlierPaths: [String] = []
  public var minFiles: Int
  public var minShare: Double
}

/// A bounded ranked table with explicit truncation.
public struct MarkdownSurveyTable<Row: Codable & Sendable>: Codable, Sendable {
  public var rows: [Row]
  public var total: Int
  public var omitted: Int
}

public struct MarkdownSurveyValueFrequency: Codable, Sendable {
  public var value: MarkdownSurveyValue
  public var count: Int
  public var proportion: Double
}

public struct MarkdownSurveyValues: Codable, Sendable {
  public var rows: [MarkdownSurveyValueFrequency]
  public var total: Int
  public var omitted: Int
  public var omittedCount: Int
  public var present: Int
  public var missing: Int
  public var unassessable: Int
  public var nonArrays: Int
  public var emptyArrays: Int
  public var denominator: Int
  public var counting: String
}

/// Pure descriptive statistics. Findings do not create conformance obligations.
public enum MarkdownSurveyStatistics {
  public static func keys(
    _ records: [MarkdownSurveyObservation], top: Int = 10, minFiles: Int = 1,
  ) throws -> MarkdownSurveyTable<MarkdownSurveyKey> {
    try Task.checkCancellation()
    guard top >= 0, minFiles > 0 else { throw MarkdownSurveyError.invalidOptions }
    var totals: [String: MarkdownSurveyKey] = [:]
    var assessable = 0
    for record in records {
      try Task.checkCancellation()
      guard record.state == .parsed || record.state == .absent else { continue }
      assessable += 1
      for (name, value) in record.frontmatter ?? [:] {
        var row = totals[name] ?? MarkdownSurveyKey(key: name, minFiles: minFiles, minShare: 0.95)
        row.present += 1
        let kind = record.observed(value, path: "/" + MarkdownSurveyObservation.escape(name)).kind
        row.kinds[kind, default: 0] += 1
        totals[name] = row
      }
    }
    var rows: [MarkdownSurveyKey] = []
    let unassessable = records.count - assessable
    for original in totals.values where original.present >= minFiles {
      var row = original
      row.missing = assessable - row.present
      row.unassessable = unassessable
      rows.append(row)
    }
    rows.sort { $0.present == $1.present ? $0.key < $1.key : $0.present > $1.present }
    let visible = top <= 0 ? rows : Array(rows.prefix(top))
    return MarkdownSurveyTable(rows: visible, total: rows.count, omitted: rows.count - visible.count)
  }

  public static func key(
    _ records: [MarkdownSurveyObservation], key: String, pointer: Bool = false,
    outliers: Bool = false, minFiles: Int = 20, minShare: Double = 0.95,
  ) throws -> MarkdownSurveyKey {
    guard minFiles > 0, minShare.isFinite, minShare > 0.5, minShare <= 1 else {
      throw MarkdownSurveyError.invalidOptions
    }
    if pointer { _ = try SurveyPointerParser.components(key) }
    var report = MarkdownSurveyKey(key: key, minFiles: minFiles, minShare: minShare)
    var kindsByPath: [(String, String)] = []
    for record in records {
      try Task.checkCancellation()
      guard record.state == .parsed || record.state == .absent else {
        report.unassessable += 1
        continue
      }
      guard let value = try record.value(at: key, pointer: pointer) else {
        report.missing += 1
        continue
      }
      report.present += 1
      report.kinds[value.kind, default: 0] += 1
      kindsByPath.append((record.path, value.kind))
    }
    if outliers, report.present >= minFiles,
      let dominant = report.kinds.max(by: { $0.value < $1.value }),
      Double(dominant.value) / Double(report.present) >= minShare {
      report.outlierPaths = kindsByPath.filter { $0.1 != dominant.key }.map(\.0).sorted()
    }
    return report
  }

  public static func values(
    _ records: [MarkdownSurveyObservation], key: String, pointer: Bool = false,
    elements: Bool = false, occurrences: Bool = false, top: Int = 10,
  ) throws -> MarkdownSurveyValues {
    guard top >= 0, !occurrences || elements else { throw MarkdownSurveyError.invalidOptions }
    let components = try pointer ? SurveyPointerParser.components(key) : [key]
    let path = components.map { "/" + MarkdownSurveyObservation.escape($0) }.joined()
    var report = MarkdownSurveyValues(
      rows: [], total: 0, omitted: 0, omittedCount: 0, present: 0, missing: 0,
      unassessable: 0, nonArrays: 0, emptyArrays: 0, denominator: 0,
      counting: occurrences ? "occurrences" : "documents",
    )
    var counts: [String: (MarkdownSurveyValue, Int)] = [:]
    for record in records {
      try Task.checkCancellation()
      guard record.state == .parsed || record.state == .absent else { report.unassessable += 1; continue }
      guard let value = try record.value(at: key, pointer: pointer) else { report.missing += 1; continue }
      report.present += 1
      let observations: [MarkdownSurveyValue]
      if elements {
        guard case .array(let array) = value.value else { report.nonArrays += 1; continue }
        if array.isEmpty { report.emptyArrays += 1 }
        observations = array.enumerated().map { record.observed($0.element, path: path + "/\($0.offset)") }
      } else { observations = [value] }
      report.denominator += occurrences ? observations.count : 1
      var seen: Set<String> = []
      for observation in observations {
        let identity = try observation.identity()
        if occurrences || seen.insert(identity).inserted {
          counts[identity] = (observation, (counts[identity]?.1 ?? 0) + 1)
        }
      }
    }
    let ordered = counts.sorted { $0.value.1 == $1.value.1 ? $0.key < $1.key : $0.value.1 > $1.value.1 }
    let visible = top == 0 ? ordered : Array(ordered.prefix(top))
    report.total = ordered.count
    report.omitted = ordered.count - visible.count
    report.omittedCount = ordered.dropFirst(visible.count).reduce(0) { $0 + $1.value.1 }
    report.rows = visible.map { MarkdownSurveyValueFrequency(
      value: $0.value.0, count: $0.value.1,
      proportion: report.denominator == 0 ? 0 : Double($0.value.1) / Double(report.denominator),
    ) }
    return report
  }
}
