import Foundation

/// Outcome of evaluating or validating one fm-var reference element.
public enum FMVarReferenceStatus: String, Codable, Equatable, Sendable, CaseIterable {
  /// Reference resolved successfully and its cache is current.
  case valid
  /// Reference resolved successfully but its cache differs from the expected presentation.
  case stale
  /// A missing or null value used the element's literal default.
  case fallback
  /// A missing or null value had no default and retained its cache.
  case unresolved
  /// Element syntax, value shape, coercion, formatting, or escaping was invalid.
  case invalid
  /// Host policy denied access to an otherwise valid source reference.
  case denied
  /// The element requested a syntactically valid capability the implementation does not support.
  case unsupported
}

/// Severity assigned to a structured fm-var diagnostic.
public enum FMVarDiagnosticSeverity: String, Codable, Equatable, Sendable, CaseIterable {
  /// Failure that prevents successful evaluation or synchronization.
  case error
  /// Non-fatal problem such as a stale presentation cache.
  case warning
  /// Supplemental context that does not represent a failure.
  case note

  fileprivate var sortOrder: Int {
    switch self {
    case .error: 0
    case .warning: 1
    case .note: 2
    }
  }
}

/// An extensible stable diagnostic identifier in the `fm-var.` namespace.
public struct FMVarDiagnosticCode: RawRepresentable, Codable, Equatable, Hashable, Sendable, Comparable {
  /// Stable namespaced identifier emitted in structured output.
  public let rawValue: String

  /// Creates a diagnostic code, including codes added by future fm-var features.
  ///
  /// Callers defining portable codes should use the `fm-var.` namespace.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// A required element attribute was absent.
  public static let missingAttribute = Self(rawValue: "fm-var.syntax.missing-attribute")
  /// An element repeated an attribute whose meaning must be unique.
  public static let duplicateAttribute = Self(rawValue: "fm-var.syntax.duplicate-attribute")
  /// An element used an attribute not defined for that element kind.
  public static let unknownAttribute = Self(rawValue: "fm-var.syntax.unknown-attribute")
  /// An attribute value did not match its lexical or semantic contract.
  public static let invalidAttribute = Self(rawValue: "fm-var.syntax.invalid-attribute")
  /// An element appeared outside the source context allowed by the specification.
  public static let invalidPlacement = Self(rawValue: "fm-var.syntax.invalid-placement")
  /// An element did not have the required explicit closing tag.
  public static let missingClosingTag = Self(rawValue: "fm-var.syntax.missing-closing-tag")
  /// A `src` value was not a valid fragment-free RFC 3986 URI reference.
  public static let invalidSourceReference = Self(rawValue: "fm-var.source.invalid-reference")
  /// Host policy denied access to the resolved source.
  public static let sourceAccessDenied = Self(rawValue: "fm-var.source.access-denied")
  /// The host does not support the resolved source kind or scheme.
  public static let unsupportedSource = Self(rawValue: "fm-var.source.unsupported")
  /// An authorized source could not be read or decoded.
  public static let unreadableSource = Self(rawValue: "fm-var.source.unreadable")
  /// A `key` value did not conform to the portable key-path grammar.
  public static let invalidKeyPath = Self(rawValue: "fm-var.key-path.invalid")
  /// The selected value was missing or null without an applicable default.
  public static let missingValue = Self(rawValue: "fm-var.value.missing")
  /// A scalar reference selected a sequence or mapping.
  public static let wrongValueShape = Self(rawValue: "fm-var.value.wrong-shape")
  /// A list contained a nested sequence or mapping member.
  public static let unsupportedItemShape = Self(rawValue: "fm-var.value.unsupported-item-shape")
  /// A selected scalar could not be interpreted as its declared type.
  public static let coercionFailed = Self(rawValue: "fm-var.coercion.failed")
  /// A formatting option or value was not valid.
  public static let invalidFormat = Self(rawValue: "fm-var.format.invalid")
  /// A formatting option was incompatible with the targeted value type.
  public static let incompatibleFormat = Self(rawValue: "fm-var.format.incompatible")
  /// Locale-sensitive formatting had no effective locale.
  public static let missingLocale = Self(rawValue: "fm-var.format.missing-locale")
  /// A valid formatting request failed in the active formatting runtime.
  public static let formattingFailed = Self(rawValue: "fm-var.format.failed")
  /// A selected value contained a character unsupported by the v1 serialization rules.
  public static let unsupportedCharacter = Self(rawValue: "fm-var.escaping.unsupported-character")
  /// Cached child text differs from the current serialized presentation.
  public static let staleCache = Self(rawValue: "fm-var.cache.stale")

  /// Orders codes lexically by their stable raw values.
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A structured fm-var diagnostic. Human-readable wording is intentionally not stable API.
///
/// Consumers should branch on ``code`` and ``severity`` rather than ``message``. See
/// <doc:FMVarModels> for deterministic structured-output behavior.
public struct FMVarDiagnostic: Codable, Equatable, Sendable, Comparable {
  /// Stable identifier for the diagnosed condition.
  public let code: FMVarDiagnosticCode
  /// Effect of the condition on evaluation or cache freshness.
  public let severity: FMVarDiagnosticSeverity
  /// Precise source range, or `nil` for a document-wide condition.
  public let range: FMVarSourceRange?
  /// Zero-based source ordinal of the related element, when known.
  public let elementOrdinal: Int?
  /// Related custom-element kind, when known.
  public let elementKind: FMVarElementKind?
  /// Human-readable explanation whose wording may evolve between releases.
  public let message: String

  /// Creates a structured diagnostic for one element or document-wide condition.
  public init(
    code: FMVarDiagnosticCode,
    severity: FMVarDiagnosticSeverity,
    range: FMVarSourceRange? = nil,
    elementOrdinal: Int? = nil,
    elementKind: FMVarElementKind? = nil,
    message: String
  ) {
    self.code = code
    self.severity = severity
    self.range = range
    self.elementOrdinal = elementOrdinal
    self.elementKind = elementKind
    self.message = message
  }

  /// Orders diagnostics by source offset, severity, code, element identity, and message.
  ///
  /// Diagnostics without a source range sort after diagnostics tied to source.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    let lhsOffset = lhs.range?.start.utf8Offset ?? Int.max
    let rhsOffset = rhs.range?.start.utf8Offset ?? Int.max
    if lhsOffset != rhsOffset { return lhsOffset < rhsOffset }
    if lhs.severity.sortOrder != rhs.severity.sortOrder {
      return lhs.severity.sortOrder < rhs.severity.sortOrder
    }
    if lhs.code != rhs.code { return lhs.code < rhs.code }
    if lhs.elementOrdinal != rhs.elementOrdinal {
      return (lhs.elementOrdinal ?? Int.max) < (rhs.elementOrdinal ?? Int.max)
    }
    if lhs.elementKind?.rawValue != rhs.elementKind?.rawValue {
      return (lhs.elementKind?.rawValue ?? "") < (rhs.elementKind?.rawValue ?? "")
    }
    return lhs.message < rhs.message
  }

  private enum CodingKeys: String, CodingKey {
    case code
    case severity
    case range
    case elementOrdinal = "element-ordinal"
    case elementKind = "element-kind"
    case message
  }
}

/// A proposed replacement of one exact half-open child range.
public struct FMVarTextEdit: Codable, Equatable, Sendable, Comparable {
  /// Existing cache-child range to replace.
  public let range: FMVarSourceRange
  /// UTF-8 Swift string to insert in place of ``range``.
  public let replacement: String
  /// Zero-based source ordinal of the reference that owns the cache.
  public let elementOrdinal: Int

  /// Creates a proposed cache-only replacement.
  ///
  /// This model does not apply the edit or verify that the underlying source snapshot is current.
  public init(range: FMVarSourceRange, replacement: String, elementOrdinal: Int) {
    self.range = range
    self.replacement = replacement
    self.elementOrdinal = elementOrdinal
  }

  /// Orders edits by range, element ordinal, and replacement text.
  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.range != rhs.range { return lhs.range < rhs.range }
    if lhs.elementOrdinal != rhs.elementOrdinal { return lhs.elementOrdinal < rhs.elementOrdinal }
    return lhs.replacement < rhs.replacement
  }

  private enum CodingKeys: String, CodingKey {
    case range
    case replacement
    case elementOrdinal = "element-ordinal"
  }
}
