/// Structured failure returned by a scalar formatter.
public struct FMVarScalarFormattingFailure: Error, Codable, Equatable, Sendable {
  public let code: FMVarDiagnosticCode
  public let message: String

  public init(code: FMVarDiagnosticCode = .formattingFailed, message: String) {
    self.code = code
    self.message = message
  }
}

/// Supplies presentation text before the evaluator applies mandatory literal escaping.
///
/// This contract is called only for a successfully coerced non-null scalar, never for fallbacks.
public protocol FMVarScalarFormatter: Sendable {
  func format(
    _ scalar: FMVarCoercedScalar,
    declaration: FMVarScalarDeclaration
  ) throws(FMVarScalarFormattingFailure) -> String
}

/// Uses specification default serialization until a host supplies formatting support.
public struct FMVarDefaultScalarFormatter: FMVarScalarFormatter {
  public init() {}

  public func format(
    _ scalar: FMVarCoercedScalar,
    declaration: FMVarScalarDeclaration
  ) throws(FMVarScalarFormattingFailure) -> String {
    guard declaration.format == nil else {
      throw FMVarScalarFormattingFailure(
        code: .unsupportedScalarFormat,
        message: "Explicit scalar formats require a supplied formatter."
      )
    }
    return scalar.defaultSerialization
  }
}

/// Immutable outcome tied to one element in an exact parsed source snapshot.
public struct FMVarScalarEvaluation: Codable, Equatable, Sendable {
  public let elementOrdinal: Int
  public let status: FMVarReferenceStatus
  public let diagnostics: [FMVarDiagnostic]
  /// The injected host result, retaining source/projection failure details.
  public let sourceResolution: FMVarSourceResolution
  /// Absent when evaluation stopped before querying.
  public let queryEvaluation: FMVarJSONPathEvaluation?
  /// Exact authored child bytes, without entity decoding or Unicode normalization.
  public let cachedText: String?
  /// Escaped canonical output; absent on every failure.
  public let expectedCache: String?
  /// Independent of fallback status; absent when no expected cache could be produced.
  public let isFresh: Bool?
  /// Child-range-only replacement; absent on failures and fresh results.
  public let edit: FMVarTextEdit?

  public var nodelist: FMVarNodelist? { queryEvaluation?.nodelist }
  public var selectedNode: FMVarQueryNode? { nodelist?.nodes.first }
  public var selectedNodeCount: Int? { nodelist?.nodes.count }
  public var selectedCardinality: FMVarNodelistCardinality? { nodelist?.cardinality }
  public var selectedValueShape: FMVarValueShape? { selectedNode?.value.shape }

  private enum CodingKeys: String, CodingKey {
    case elementOrdinal = "element-ordinal"
    case status, diagnostics
    case sourceResolution = "source-resolution"
    case queryEvaluation = "query-evaluation"
    case cachedText = "cached-text"
    case expectedCache = "expected-cache"
    case isFresh = "is-fresh"
    case edit
  }
}

/// Pure, per-element orchestration of source/query results, coercion, formatting and cache edits.
///
/// Sources must already have been resolved and projected by the host. This evaluator performs no
/// filesystem or network operations. See <doc:EvaluatingFMVarScalars>.
public struct FMVarScalarEvaluator: Sendable {
  public let queryEvaluator: FMVarJSONPathEvaluator
  public let formatter: any FMVarScalarFormatter

  public init(
    queryEvaluator: FMVarJSONPathEvaluator = FMVarJSONPathEvaluator(),
    formatter: any FMVarScalarFormatter = FMVarDefaultScalarFormatter()
  ) {
    self.queryEvaluator = queryEvaluator
    self.formatter = formatter
  }

  /// Evaluates one parsed scalar against its host-resolved authoritative source.
  ///
  /// An injected query result must correspond to this declaration and source. It is never used
  /// to bypass parsing or source failures. Unknown ordinals and inconsistent provider results
  /// produce structured invalid-input failures, without edits.
  public func evaluate(
    _ snapshot: FMVarParseResult,
    elementOrdinal: Int,
    sourceResolution: FMVarSourceResolution,
    queryEvaluation injectedQuery: FMVarJSONPathEvaluation? = nil
  ) -> FMVarScalarEvaluation {
    let element = snapshot.elements.first { $0.ordinal == elementOrdinal }
    var diagnostics = snapshot.diagnostics.filter { diagnostic in
      if let ordinal = diagnostic.elementOrdinal { return ordinal == elementOrdinal }
      guard let range = diagnostic.range, let element else { return false }
      return range.start.utf8Offset < element.range.end.utf8Offset &&
        range.end.utf8Offset > element.range.start.utf8Offset
    }
    var cachedText: String?
    var query: FMVarJSONPathEvaluation?

    func result(
      _ status: FMVarReferenceStatus,
      expected: String? = nil,
      fresh: Bool? = nil,
      edit: FMVarTextEdit? = nil
    ) -> FMVarScalarEvaluation {
      FMVarScalarEvaluation(
        elementOrdinal: elementOrdinal, status: status, diagnostics: diagnostics.sorted(),
        sourceResolution: sourceResolution, queryEvaluation: query, cachedText: cachedText,
        expectedCache: expected, isFresh: fresh, edit: edit
      )
    }

    func diagnose(
      _ code: FMVarDiagnosticCode,
      _ message: String,
      severity: FMVarDiagnosticSeverity = .error,
      range: FMVarSourceRange? = nil
    ) {
      diagnostics.append(FMVarDiagnostic(
        code: code, severity: severity, range: range ?? element?.openingTagRange,
        elementOrdinal: elementOrdinal, elementKind: element?.kind, message: message
      ))
    }

    guard let element, element.kind == .variable, let cacheRange = element.cacheRange,
      element.closingTagRange != nil
    else {
      diagnose(.invalidEvaluationInput, "The requested element has no complete scalar cache.")
      return result(.invalid)
    }
    do {
      cachedText = try snapshot.text(in: cacheRange)
    } catch {
      diagnose(.invalidEvaluationInput, error.description)
      return result(.invalid)
    }
    guard diagnostics.contains(where: { $0.severity == .error }) == false else {
      return result(.invalid)
    }
    guard case .scalar(let declaration) = snapshot.declaration(forElementOrdinal: elementOrdinal) else {
      diagnose(.invalidEvaluationInput, "The requested element has no scalar declaration.")
      return result(.invalid)
    }
    if let failure = sourceResolution.failure {
      diagnose(failure.code, failure.message, range: element.attribute(named: "src")?.valueRange)
      switch failure.reason {
      case .invalidQueryArgument: return result(.invalidQueryArgument)
      case .accessDenied, .outsideAllowedRoot, .symlinkEscape: return result(.denied)
      case .unsupportedSource, .unsupportedResourceKind, .unsupportedFrontmatterFormat:
        return result(.unsupported)
      default: return result(.invalid)
      }
    }
    guard sourceResolution.status == .resolved, let argument = sourceResolution.queryArgument else {
      diagnose(.invalidEvaluationInput, "Source resolution did not supply a validated query argument.")
      return result(.invalid)
    }
    let evaluation = injectedQuery ?? queryEvaluator.evaluate(query: declaration.query, argument: argument)
    query = evaluation
    guard evaluation.status == .selected, evaluation.failure == nil else {
      let code: FMVarDiagnosticCode
      let status: FMVarReferenceStatus
      switch evaluation.status {
      case .invalidQuery: code = .invalidQuery; status = .invalidQuery
      case .unsupportedCapability: code = .unsupportedQueryCapability; status = .unsupportedQuery
      case .resourceLimited: code = .queryResourceLimitExceeded; status = .queryResourceLimited
      case .notEvaluated, .selected: code = .invalidEvaluationInput; status = .invalid
      }
      // Query-relative coordinates remain in queryEvaluation. The document diagnostic covers
      // the raw attribute, whose entities can make a decoded-query offset unsuitable here.
      diagnose(code, evaluation.failure?.message ?? "Query evaluation did not succeed.",
        range: element.attribute(named: "query")?.valueRange)
      return result(status)
    }
    guard let nodelist = evaluation.nodelist else {
      diagnose(.invalidEvaluationInput, "Successful query evaluation did not supply a nodelist.")
      return result(.invalid)
    }
    if nodelist.nodes.count > 1 {
      diagnose(.additionalScalarNodes, "Only the first of \(nodelist.nodes.count) selected nodes is used.",
        severity: .warning, range: element.attribute(named: "query")?.valueRange)
      if evaluation.mayEnumerateObjectMembers == true {
        diagnose(.objectEnumerationOrder,
          "This query may enumerate object members; the first result can depend on implementation order.",
          severity: .warning, range: element.attribute(named: "query")?.valueRange)
      }
    }

    let text: String
    let fallbackStatus: FMVarReferenceStatus?
    if nodelist.nodes.isEmpty {
      guard let fallback = declaration.defaultZero else {
        diagnose(.unresolvedZeroResult, "The query selected zero nodes and default-zero is absent.")
        return result(.unresolvedZeroResult)
      }
      text = fallback
      fallbackStatus = .zeroResultFallback
    } else if let first = nodelist.nodes.first, first.value.shape == .null {
      guard let fallback = declaration.defaultNull else {
        diagnose(.unresolvedNullResult, "The first selected node is null and default-null is absent.")
        return result(.unresolvedNullResult)
      }
      text = fallback
      fallbackStatus = .nullResultFallback
    } else if let first = nodelist.nodes.first {
      let coercion = FMVarScalarCoercer().coerce(first, as: declaration.type)
      if let failure = coercion.failure {
        diagnose(failure.diagnosticCode, failure.message)
        return result(failure.reason == .unsupportedValueShape ? .wrongValueShape : .invalid)
      }
      guard let scalar = coercion.scalar else {
        diagnose(.invalidEvaluationInput, "Coercion did not supply a scalar.")
        return result(.invalid)
      }
      do {
        text = try formatter.format(scalar, declaration: declaration)
      } catch {
        diagnose(error.code, error.message, range: element.attribute(named: "format")?.valueRange)
        return result(error.code == .unsupportedScalarFormat ? .unsupported : .invalid)
      }
      fallbackStatus = nil
    } else {
      diagnose(.invalidEvaluationInput, "The nodelist has no first node.")
      return result(.invalid)
    }

    let expected: String
    do {
      expected = try FMVarLiteralCacheSerializer().serialize(text)
    } catch {
      diagnose(.unsupportedCharacter, "Cache text contains a line break or character forbidden by XML 1.0.")
      return result(.invalid)
    }
    // Swift String equality is canonically equivalent; freshness must instead compare bytes.
    let fresh = cachedText?.utf8.elementsEqual(expected.utf8) == true
    if fresh == false {
      diagnose(.staleCache, "Cached text differs from the canonical literal serialization.",
        severity: .warning, range: cacheRange)
    }
    return result(
      fallbackStatus ?? (fresh ? .valid : .stale), expected: expected, fresh: fresh,
      edit: fresh ? nil : FMVarTextEdit(range: cacheRange, replacement: expected, elementOrdinal: elementOrdinal)
    )
  }
}
