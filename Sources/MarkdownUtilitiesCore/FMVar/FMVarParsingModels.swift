import Foundation

/// A normalized declaration parsed from one fm-var family element.
public enum FMVarDeclaration: Equatable, Sendable {
  /// Attributes from an `<fm-var>` element.
  case scalar(FMVarScalarDeclaration)
  /// Attributes from an `<fm-list>` element.
  case list(FMVarListDeclaration)
  /// Attributes from an `<fm-format>` element.
  case format(FMVarFormatDeclaration)

  /// The custom-element kind that authored the declaration.
  public var elementKind: FMVarElementKind {
    switch self {
    case .scalar: .variable
    case .list: .list
    case .format: .format
    }
  }
}

/// Associates a normalized declaration with its lossless source element.
public struct FMVarParsedDeclaration: Equatable, Sendable {
  /// Zero-based ordinal of the corresponding ``FMVarElement``.
  public let elementOrdinal: Int
  /// Attribute values normalized into the declaration model for the element kind.
  public let declaration: FMVarDeclaration

  /// Creates an ordinal-to-declaration association.
  public init(elementOrdinal: Int, declaration: FMVarDeclaration) {
    self.elementOrdinal = elementOrdinal
    self.declaration = declaration
  }
}

/// Lossless parser output tied to one immutable Markdown source snapshot.
///
/// See <doc:ParsingFMVarElements> for range, recovery, and placement guarantees.
public struct FMVarParseResult: Equatable, Sendable {
  /// Exact Markdown source whose UTF-8 bytes define every returned range.
  public let source: String
  /// Recognized opening elements in deterministic source order, including recoverable failures.
  public let elements: [FMVarElement]
  /// Normalized declarations for elements whose attributes could be interpreted.
  public let declarations: [FMVarParsedDeclaration]
  /// Syntax and placement diagnostics in deterministic source order.
  public let diagnostics: [FMVarDiagnostic]

  /// Creates parser output for one immutable source snapshot.
  ///
  /// Diagnostics are sorted deterministically during initialization.
  public init(
    source: String,
    elements: [FMVarElement],
    declarations: [FMVarParsedDeclaration],
    diagnostics: [FMVarDiagnostic]
  ) {
    self.source = source
    self.elements = elements
    self.declarations = declarations
    self.diagnostics = diagnostics.sorted()
  }

  /// Whether parsing found no syntax or placement errors.
  public var isValid: Bool {
    diagnostics.contains(where: { $0.severity == .error }) == false
  }

  /// Returns the exact text covered by a range from this result's source snapshot.
  ///
  /// - Parameter range: Half-open UTF-8 range returned for this snapshot.
  /// - Returns: Exact source text in the range.
  /// - Throws: ``FMVarParseResultError`` if the range is outside this snapshot, has coordinates
  ///   from another snapshot, or splits a UTF-8 scalar.
  public func text(
    in range: FMVarSourceRange
  ) throws(FMVarParseResultError) -> String {
    let bytes = Array(source.utf8)
    try validate(range, byteCount: bytes.count)
    let byteSlice = bytes[range.start.utf8Offset..<range.end.utf8Offset]
    guard let text = String(bytes: byteSlice, encoding: .utf8) else {
      throw FMVarParseResultError.rangeSplitsUTF8Scalar(range)
    }
    return text
  }

  /// Returns the normalized declaration associated with an element ordinal, when available.
  public func declaration(forElementOrdinal ordinal: Int) -> FMVarDeclaration? {
    declarations.first(where: { $0.elementOrdinal == ordinal })?.declaration
  }

  /// Replaces exactly one parsed cache range while preserving every other source byte.
  ///
  /// This in-memory helper demonstrates the cache-only edit contract. Native host layers remain
  /// responsible for revision checks and atomic file replacement.
  ///
  /// - Parameters:
  ///   - ordinal: Zero-based ordinal of the parsed reference element.
  ///   - replacement: UTF-8 text to place between the element's opening and closing tags.
  /// - Returns: A new source snapshot with only the cache bytes replaced.
  /// - Throws: ``FMVarParseResultError`` if the element is absent or has no safe cache range.
  public func replacingCache(
    ofElementOrdinal ordinal: Int,
    with replacement: String
  ) throws(FMVarParseResultError) -> String {
    guard let element = elements.first(where: { $0.ordinal == ordinal }) else {
      throw FMVarParseResultError.unknownElementOrdinal(ordinal)
    }
    guard element.kind != .format, let cacheRange = element.cacheRange else {
      throw FMVarParseResultError.cacheUnavailable(ordinal)
    }

    var bytes = Array(source.utf8)
    try validate(cacheRange, byteCount: bytes.count)
    bytes.replaceSubrange(
      cacheRange.start.utf8Offset..<cacheRange.end.utf8Offset,
      with: replacement.utf8
    )
    guard let updated = String(bytes: bytes, encoding: .utf8) else {
      throw FMVarParseResultError.replacementProducedInvalidUTF8
    }
    return updated
  }

  /// Confirms that a range belongs to the retained snapshot before byte slicing or replacement.
  ///
  /// Bounds are checked first so translating offsets through ``FMVarSourceMap`` cannot fail.
  /// The derived line and column values are then compared with the authored positions to reject
  /// ranges copied from a different source snapshot with coincidentally valid offsets.
  ///
  /// - Parameters:
  ///   - range: Candidate half-open range to validate.
  ///   - byteCount: UTF-8 byte count of ``source`` cached by the caller.
  /// - Throws: ``FMVarParseResultError/rangeOutsideSnapshot(_:)`` when an offset is out of bounds,
  ///   or ``FMVarParseResultError/rangeFromDifferentSnapshot(_:)`` when its coordinates disagree
  ///   with this snapshot.
  private func validate(
    _ range: FMVarSourceRange,
    byteCount: Int
  ) throws(FMVarParseResultError) {
    guard range.start.utf8Offset >= 0,
      range.end.utf8Offset >= range.start.utf8Offset,
      range.end.utf8Offset <= byteCount
    else {
      throw FMVarParseResultError.rangeOutsideSnapshot(range)
    }

    let sourceMap = FMVarSourceMap(source: source)
    let expectedStart: FMVarSourcePosition
    let expectedEnd: FMVarSourcePosition
    do {
      expectedStart = try sourceMap.position(atUTF8Offset: range.start.utf8Offset)
      expectedEnd = try sourceMap.position(atUTF8Offset: range.end.utf8Offset)
    } catch {
      // Bounds were checked above, so this protects the public error contract if the map's
      // invariants ever change without exposing an unrelated source-location error.
      throw FMVarParseResultError.rangeOutsideSnapshot(range)
    }
    guard expectedStart == range.start, expectedEnd == range.end else {
      throw FMVarParseResultError.rangeFromDifferentSnapshot(range)
    }
  }
}

/// Failures while reading or editing one ``FMVarParseResult`` source snapshot.
public enum FMVarParseResultError: Error, Equatable, Sendable, CustomStringConvertible {
  /// No parsed element has the requested ordinal.
  case unknownElementOrdinal(Int)
  /// The element is malformed, is configuration-only, or otherwise has no editable cache.
  case cacheUnavailable(Int)
  /// A range falls outside the retained source snapshot.
  case rangeOutsideSnapshot(FMVarSourceRange)
  /// The offsets are valid but their line or column coordinates describe another snapshot.
  case rangeFromDifferentSnapshot(FMVarSourceRange)
  /// A range boundary falls within a multi-byte UTF-8 scalar.
  case rangeSplitsUTF8Scalar(FMVarSourceRange)
  /// The cache replacement could not be represented as UTF-8.
  case replacementProducedInvalidUTF8

  /// Human-readable description of the failed snapshot operation.
  public var description: String {
    switch self {
    case .unknownElementOrdinal(let ordinal):
      return "No parsed fm-var element has ordinal \(ordinal)"
    case .cacheUnavailable(let ordinal):
      return "Parsed fm-var element \(ordinal) has no replaceable cache range"
    case .rangeOutsideSnapshot:
      return "The source range is outside the retained fm-var snapshot"
    case .rangeFromDifferentSnapshot:
      return "The source range coordinates do not match the retained fm-var snapshot"
    case .rangeSplitsUTF8Scalar:
      return "The source range splits a multi-byte UTF-8 scalar"
    case .replacementProducedInvalidUTF8:
      return "The cache replacement produced invalid UTF-8"
    }
  }
}

extension FMVarElement {
  /// Returns attributes with an exact, case-sensitive authored name.
  public func attributes(named name: String) -> [FMVarRawAttribute] {
    attributes.filter { $0.name == name }
  }

  /// Returns the first attribute with an exact, case-sensitive authored name.
  public func attribute(named name: String) -> FMVarRawAttribute? {
    attributes.first { $0.name == name }
  }
}
