import Foundation

/// Outcome of evaluating or validating one fm-var reference element.
public enum FMVarReferenceStatus: String, Codable, Equatable, Sendable, CaseIterable {
  /// Reference resolved successfully and its cache is current.
  case valid
  /// Reference resolved successfully but its cache differs from the expected presentation.
  case stale
  /// Zero selected nodes or an empty sequence used `default-zero`.
  case zeroResultFallback = "zero-result-fallback"
  /// Zero selected nodes or an empty sequence had no `default-zero`.
  case unresolvedZeroResult = "unresolved-zero-result"
  /// An applicable null result used `default-null`.
  case nullResultFallback = "null-result-fallback"
  /// An applicable null result had no `default-null`.
  case unresolvedNullResult = "unresolved-null-result"
  /// YAML projection could not construct a valid JSONPath query argument.
  case invalidQueryArgument = "invalid-query-argument"
  /// The authored JSONPath query was malformed or invalid.
  case invalidQuery = "invalid-query"
  /// The query required a valid capability that is unavailable.
  case unsupportedQuery = "unsupported-query"
  /// JSONPath evaluation exceeded a configured resource limit.
  case queryResourceLimited = "query-resource-limited"
  /// Selected nodelist cardinality or value shape did not fit the element contract.
  case wrongValueShape = "wrong-value-shape"
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
  /// A candidate opening or closing tag could not be tokenized completely.
  public static let malformedTag = Self(rawValue: "fm-var.syntax.malformed-tag")
  /// A closing tag appeared without a compatible opening element.
  public static let unexpectedClosingTag = Self(rawValue: "fm-var.syntax.unexpected-closing-tag")
  /// An opening element was followed by a different custom-element closing tag.
  public static let mismatchedClosingTag = Self(rawValue: "fm-var.syntax.mismatched-closing-tag")
  /// One fm-var family element was nested inside another.
  public static let nestedElement = Self(rawValue: "fm-var.syntax.nested-element")
  /// Cached children did not satisfy the element's text-only or list content model.
  public static let invalidContent = Self(rawValue: "fm-var.syntax.invalid-content")
  /// A `src` value was not a valid fragment-free RFC 3986 URI reference.
  public static let invalidSourceReference = Self(rawValue: "fm-var.source.invalid-reference")
  /// The containing document did not provide a valid absolute base URI.
  public static let invalidBaseURI = Self(rawValue: "fm-var.source.invalid-base-uri")
  /// Host policy denied access to the resolved source.
  public static let sourceAccessDenied = Self(rawValue: "fm-var.source.access-denied")
  /// The host does not support the resolved source kind or scheme.
  public static let unsupportedSource = Self(rawValue: "fm-var.source.unsupported")
  /// An authorized source could not be read or decoded.
  public static let unreadableSource = Self(rawValue: "fm-var.source.unreadable")
  /// Resource metadata and URI extension did not identify Markdown or YAML.
  public static let unsupportedResourceKind = Self(rawValue: "fm-var.source.unsupported-kind")
  /// A Markdown source did not contain YAML frontmatter.
  public static let missingYAMLFrontmatter = Self(rawValue: "fm-var.source.missing-frontmatter")
  /// A Markdown source used a non-YAML frontmatter format.
  public static let unsupportedFrontmatterFormat = Self(
    rawValue: "fm-var.source.unsupported-frontmatter-format"
  )
  /// A Markdown YAML frontmatter envelope was incomplete.
  public static let malformedYAMLFrontmatter = Self(
    rawValue: "fm-var.source.malformed-frontmatter"
  )
  /// YAML data could not be projected to an I-JSON-compatible query argument.
  public static let invalidQueryArgument = Self(rawValue: "fm-var.query-argument.invalid")
  /// Yams rejected the YAML stream or document syntax.
  public static let malformedYAML = Self(rawValue: "fm-var.query-argument.malformed-yaml")
  /// A standalone YAML stream did not contain a document root.
  public static let emptyYAMLDocument = Self(rawValue: "fm-var.query-argument.empty-document")
  /// A YAML mapping repeated a key.
  public static let duplicateYAMLKey = Self(rawValue: "fm-var.query-argument.duplicate-key")
  /// A YAML mapping key did not resolve to a string.
  public static let nonStringYAMLKey = Self(rawValue: "fm-var.query-argument.non-string-key")
  /// A YAML alias was cyclic, forward, self-referential, or undefined.
  public static let invalidYAMLAlias = Self(rawValue: "fm-var.query-argument.invalid-alias")
  /// A YAML node used a tag outside the supported Core Schema types.
  public static let unsupportedYAMLTag = Self(rawValue: "fm-var.query-argument.unsupported-tag")
  /// A YAML scalar was not valid for its resolved or explicit tag.
  public static let invalidYAMLScalar = Self(rawValue: "fm-var.query-argument.invalid-scalar")
  /// A YAML float was infinite or NaN.
  public static let nonFiniteYAMLFloat = Self(rawValue: "fm-var.query-argument.non-finite-float")
  /// A YAML integer exceeded RFC 001's interoperable range.
  public static let yamlIntegerOutOfRange = Self(rawValue: "fm-var.query-argument.integer-out-of-range")
  /// A YAML float overflowed finite IEEE 754 binary64.
  public static let yamlFloatOverflow = Self(rawValue: "fm-var.query-argument.float-overflow")
  /// Markdown YAML frontmatter did not have a mapping root.
  public static let invalidYAMLFrontmatterRoot = Self(
    rawValue: "fm-var.query-argument.invalid-frontmatter-root"
  )
  /// A JSONPath query was malformed or invalid under RFC 9535.
  public static let invalidQuery = Self(rawValue: "fm-var.query.invalid")
  /// A valid JSONPath query requires an unavailable capability.
  public static let unsupportedQueryCapability = Self(
    rawValue: "fm-var.query.unsupported-capability"
  )
  /// JSONPath evaluation exceeded a configured resource limit.
  public static let queryResourceLimitExceeded = Self(
    rawValue: "fm-var.query.resource-limit-exceeded"
  )
  /// A query selected no nodes or an empty sequence without `default-zero`.
  public static let unresolvedZeroResult = Self(rawValue: "fm-var.value.unresolved-zero-result")
  /// A query selected an applicable null result without `default-null`.
  public static let unresolvedNullResult = Self(rawValue: "fm-var.value.unresolved-null-result")
  /// A list query selected more than one node.
  public static let wrongNodelistCardinality = Self(rawValue: "fm-var.value.wrong-cardinality")
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
