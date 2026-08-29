import Foundation

public enum FMVarReferenceStatus: String, Codable, Equatable, Sendable, CaseIterable {
  case valid
  case stale
  case fallback
  case unresolved
  case invalid
  case denied
  case unsupported
}

public enum FMVarDiagnosticSeverity: String, Codable, Equatable, Sendable, CaseIterable {
  case error
  case warning
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
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }

  public static let missingAttribute = Self(rawValue: "fm-var.syntax.missing-attribute")
  public static let duplicateAttribute = Self(rawValue: "fm-var.syntax.duplicate-attribute")
  public static let unknownAttribute = Self(rawValue: "fm-var.syntax.unknown-attribute")
  public static let invalidAttribute = Self(rawValue: "fm-var.syntax.invalid-attribute")
  public static let invalidPlacement = Self(rawValue: "fm-var.syntax.invalid-placement")
  public static let missingClosingTag = Self(rawValue: "fm-var.syntax.missing-closing-tag")
  public static let invalidSourceReference = Self(rawValue: "fm-var.source.invalid-reference")
  public static let sourceAccessDenied = Self(rawValue: "fm-var.source.access-denied")
  public static let unsupportedSource = Self(rawValue: "fm-var.source.unsupported")
  public static let unreadableSource = Self(rawValue: "fm-var.source.unreadable")
  public static let invalidKeyPath = Self(rawValue: "fm-var.key-path.invalid")
  public static let missingValue = Self(rawValue: "fm-var.value.missing")
  public static let wrongValueShape = Self(rawValue: "fm-var.value.wrong-shape")
  public static let unsupportedItemShape = Self(rawValue: "fm-var.value.unsupported-item-shape")
  public static let coercionFailed = Self(rawValue: "fm-var.coercion.failed")
  public static let invalidFormat = Self(rawValue: "fm-var.format.invalid")
  public static let incompatibleFormat = Self(rawValue: "fm-var.format.incompatible")
  public static let missingLocale = Self(rawValue: "fm-var.format.missing-locale")
  public static let formattingFailed = Self(rawValue: "fm-var.format.failed")
  public static let unsupportedCharacter = Self(rawValue: "fm-var.escaping.unsupported-character")
  public static let staleCache = Self(rawValue: "fm-var.cache.stale")

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A structured fm-var diagnostic. Human-readable wording is intentionally not stable API.
public struct FMVarDiagnostic: Codable, Equatable, Sendable, Comparable {
  public let code: FMVarDiagnosticCode
  public let severity: FMVarDiagnosticSeverity
  public let range: FMVarSourceRange?
  public let elementOrdinal: Int?
  public let elementKind: FMVarElementKind?
  public let message: String

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
  public let range: FMVarSourceRange
  public let replacement: String
  public let elementOrdinal: Int

  public init(range: FMVarSourceRange, replacement: String, elementOrdinal: Int) {
    self.range = range
    self.replacement = replacement
    self.elementOrdinal = elementOrdinal
  }

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
