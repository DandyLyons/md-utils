import Foundation

/// The custom element represented by an fm-var source model.
public enum FMVarElementKind: String, Codable, Equatable, Sendable, CaseIterable {
  /// Inline scalar reference represented by `<fm-var>`.
  case variable = "fm-var"
  /// Scalar-sequence reference represented by `<fm-list>`.
  case list = "fm-list"
  /// Document-wide formatting declaration represented by `<fm-format>`.
  case format = "fm-format"
}

/// The quote delimiter authored around an attribute value.
public enum FMVarAttributeQuoteStyle: String, Codable, Equatable, Sendable {
  /// Attribute value had no quote delimiter.
  case unquoted
  /// Attribute value used single quotes.
  case single
  /// Attribute value used double quotes.
  case double
}

/// One ordered, lossless attribute captured from an fm-var family element.
///
/// ``rawText`` preserves authored spelling for exact inspection while ``name`` and ``value``
/// provide the scanner's extracted components. See <doc:FMVarModels> for serialization details.
public struct FMVarRawAttribute: Codable, Equatable, Sendable {
  /// Exact source text occupied by the attribute.
  public let rawText: String
  /// Authored attribute name without normalization.
  public let name: String
  /// Extracted attribute value, or `nil` when no value was authored.
  public let value: String?
  /// Authored quote delimiter, or `nil` when the attribute had no value.
  public let quoteStyle: FMVarAttributeQuoteStyle?
  /// Full half-open source range occupied by the attribute.
  public let range: FMVarSourceRange
  /// Half-open source range occupied by the authored name.
  public let nameRange: FMVarSourceRange
  /// Half-open range of the value without its delimiters, when present.
  public let valueRange: FMVarSourceRange?

  /// Creates a lossless raw-attribute description.
  ///
  /// The initializer stores scanner output without validating attribute semantics or checking
  /// that the supplied ranges are nested.
  public init(
    rawText: String,
    name: String,
    value: String? = nil,
    quoteStyle: FMVarAttributeQuoteStyle? = nil,
    range: FMVarSourceRange,
    nameRange: FMVarSourceRange,
    valueRange: FMVarSourceRange? = nil
  ) {
    self.rawText = rawText
    self.name = name
    self.value = value
    self.quoteStyle = quoteStyle
    self.range = range
    self.nameRange = nameRange
    self.valueRange = valueRange
  }

  private enum CodingKeys: String, CodingKey {
    case rawText = "raw-text"
    case name
    case value
    case quoteStyle = "quote-style"
    case range
    case nameRange = "name-range"
    case valueRange = "value-range"
  }
}

/// Lossless source ranges and attributes for one scanned fm-var family element.
///
/// Optional child and closing ranges allow scanners to represent incomplete syntax and attach
/// precise diagnostics without discarding the opening tag.
public struct FMVarElement: Codable, Equatable, Sendable {
  /// Custom-element family member found in source.
  public let kind: FMVarElementKind
  /// Zero-based element order within the source snapshot.
  public let ordinal: Int
  /// Attributes in authored source order.
  public let attributes: [FMVarRawAttribute]
  /// Range of the complete element, or all recognized bytes for incomplete syntax.
  public let range: FMVarSourceRange
  /// Range containing the opening tag and its delimiters.
  public let openingTagRange: FMVarSourceRange
  /// Child range used as cached presentation, when recognized.
  public let cacheRange: FMVarSourceRange?
  /// Range containing the explicit closing tag, when recognized.
  public let closingTagRange: FMVarSourceRange?

  /// Creates a lossless element description from scanner-produced ranges and attributes.
  public init(
    kind: FMVarElementKind,
    ordinal: Int,
    attributes: [FMVarRawAttribute],
    range: FMVarSourceRange,
    openingTagRange: FMVarSourceRange,
    cacheRange: FMVarSourceRange? = nil,
    closingTagRange: FMVarSourceRange? = nil
  ) {
    self.kind = kind
    self.ordinal = ordinal
    self.attributes = attributes
    self.range = range
    self.openingTagRange = openingTagRange
    self.cacheRange = cacheRange
    self.closingTagRange = closingTagRange
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case ordinal
    case attributes
    case range
    case openingTagRange = "opening-tag-range"
    case cacheRange = "cache-range"
    case closingTagRange = "closing-tag-range"
  }
}

/// Portable scalar interpretations supported by RFC 001 Rev 3.
public enum FMVarValueType: String, Codable, Equatable, Sendable, CaseIterable {
  /// Plain text with no numeric or temporal interpretation.
  case string
  /// Boolean value rendered according to the effective format.
  case boolean
  /// Base-10 integer value.
  case integer
  /// Finite numeric value whose default rendering preserves source spelling.
  case number
  /// Calendar date without a time component.
  case date
  /// Date and local time without a required UTC offset.
  case datetime
  /// Date and time carrying a UTC designation or numeric offset.
  case timestamp
}

/// Value kinds accepted by an `<fm-format for="…">` declaration.
public enum FMVarFormatTarget: String, Codable, Equatable, Sendable, CaseIterable {
  /// String scalar references.
  case string
  /// Boolean scalar references.
  case boolean
  /// Integer scalar references.
  case integer
  /// Finite-number scalar references.
  case number
  /// Date scalar references.
  case date
  /// Local date-time scalar references.
  case datetime
  /// Offset-aware timestamp scalar references.
  case timestamp
  /// One-dimensional scalar lists.
  case array
}

/// Cache representation selected for one `<fm-list>` reference.
public enum FMVarListFormat: String, Codable, Equatable, Sendable, CaseIterable {
  /// Block cache containing an HTML `<ol>`.
  case ordered
  /// Block cache containing an HTML `<ul>`.
  case unordered
  /// Locale-aware inline conjunction such as “A, B, and C”.
  case conjunction
  /// Locale-aware inline disjunction such as “A, B, or C”.
  case disjunction
  /// Locale-aware inline unit sequence.
  case unit
}

/// ECMA-402 list-width style for inline list formatting.
public enum FMVarListStyle: String, Codable, Equatable, Sendable, CaseIterable {
  /// Full locale-specific words and punctuation.
  case long
  /// Abbreviated locale-specific output.
  case short
  /// Most compact locale-specific output.
  case narrow
}

/// Normalized declaration for one scalar `<fm-var>` reference.
public struct FMVarScalarDeclaration: Codable, Equatable, Sendable {
  /// Authored complete RFC 9535 JSONPath query selecting the authoritative scalar.
  public let query: String
  /// Authored `src` URI reference, or `nil` for the containing document.
  public let source: String?
  /// Literal presentation fallback used only when the query selects zero nodes.
  public let defaultZero: String?
  /// Literal presentation fallback used only when the first selected node is null.
  public let defaultNull: String?
  /// Requested scalar interpretation, defaulting to ``FMVarValueType/string``.
  public let type: FMVarValueType
  /// Type-specific local format override.
  public let format: String?
  /// BCP 47 local locale override.
  public let locale: String?

  /// Creates a normalized scalar-reference declaration.
  public init(
    query: String,
    source: String? = nil,
    defaultZero: String? = nil,
    defaultNull: String? = nil,
    type: FMVarValueType = .string,
    format: String? = nil,
    locale: String? = nil
  ) {
    self.query = query
    self.source = source
    self.defaultZero = defaultZero
    self.defaultNull = defaultNull
    self.type = type
    self.format = format
    self.locale = locale
  }

  private enum CodingKeys: String, CodingKey {
    case query
    case source = "src"
    case defaultZero = "default-zero"
    case defaultNull = "default-null"
    case type
    case format
    case locale
  }
}

/// Normalized declaration for one `<fm-list>` reference.
public struct FMVarListDeclaration: Codable, Equatable, Sendable {
  /// Authored complete RFC 9535 JSONPath query selecting the authoritative sequence.
  public let query: String
  /// Authored `src` URI reference, or `nil` for the containing document.
  public let source: String?
  /// Literal empty-state fallback for zero nodes or an empty selected sequence.
  public let defaultZero: String?
  /// Literal empty-state fallback for a null result or a sequence containing only null members.
  public let defaultNull: String?
  /// Requested interpretation applied atomically to every sequence member.
  public let itemType: FMVarValueType
  /// Required block or inline cache representation.
  public let format: FMVarListFormat
  /// BCP 47 local locale override.
  public let locale: String?
  /// Width used by locale-aware inline list formats.
  public let listStyle: FMVarListStyle

  /// Creates a normalized list-reference declaration.
  public init(
    query: String,
    source: String? = nil,
    defaultZero: String? = nil,
    defaultNull: String? = nil,
    itemType: FMVarValueType = .string,
    format: FMVarListFormat,
    locale: String? = nil,
    listStyle: FMVarListStyle = .long
  ) {
    self.query = query
    self.source = source
    self.defaultZero = defaultZero
    self.defaultNull = defaultNull
    self.itemType = itemType
    self.format = format
    self.locale = locale
    self.listStyle = listStyle
  }

  private enum CodingKeys: String, CodingKey {
    case query
    case source = "src"
    case defaultZero = "default-zero"
    case defaultNull = "default-null"
    case itemType = "item-type"
    case format
    case locale
    case listStyle = "list-style"
  }
}

/// The complete v1 formatting vocabulary shared by local and document-wide declarations.
///
/// String-valued ECMA-402 options remain strings so validation and runtime support can be
/// introduced independently without losing values recognized by newer locale runtimes.
public struct FMVarFormatOptions: Codable, Equatable, Sendable {
  /// BCP 47 locale for locale-sensitive formatting.
  public var locale: String?
  /// Type-specific scalar format or list-format name.
  public var format: String?
  /// Width used by locale-aware inline list formatting.
  public var listStyle: FMVarListStyle?
  /// ECMA-402 calendar identifier.
  public var calendar: String?
  /// ECMA-402 numbering-system identifier.
  public var numberingSystem: String?
  /// IANA time-zone name used for temporal formatting.
  public var timeZone: String?
  /// ECMA-402 hour-cycle identifier, such as `h12` or `h23`.
  public var hourCycle: String?
  /// Whether formatted hours use a 12-hour clock.
  public var hour12: Bool?
  /// ECMA-402 date style, such as `long` or `short`.
  public var dateStyle: String?
  /// ECMA-402 time style, such as `medium` or `short`.
  public var timeStyle: String?
  /// ECMA-402 weekday presentation.
  public var weekday: String?
  /// ECMA-402 era presentation.
  public var era: String?
  /// ECMA-402 year presentation.
  public var year: String?
  /// ECMA-402 month presentation.
  public var month: String?
  /// ECMA-402 day presentation.
  public var day: String?
  /// ECMA-402 day-period presentation.
  public var dayPeriod: String?
  /// ECMA-402 hour presentation.
  public var hour: String?
  /// ECMA-402 minute presentation.
  public var minute: String?
  /// ECMA-402 second presentation.
  public var second: String?
  /// Number of fractional-second digits requested by ECMA-402.
  public var fractionalSecondDigits: Int?
  /// ECMA-402 time-zone-name presentation.
  public var timeZoneName: String?
  /// ECMA-402 matching algorithm; the portable default is `basic`.
  public var formatMatcher: String?

  /// Creates a collection of explicitly declared formatting options.
  ///
  /// Every `nil` property represents an omitted option rather than an inherited or defaulted
  /// value. ``FMVarEffectiveConfiguration`` carries the result after defaults and declarations
  /// have been combined.
  public init(
    locale: String? = nil,
    format: String? = nil,
    listStyle: FMVarListStyle? = nil,
    calendar: String? = nil,
    numberingSystem: String? = nil,
    timeZone: String? = nil,
    hourCycle: String? = nil,
    hour12: Bool? = nil,
    dateStyle: String? = nil,
    timeStyle: String? = nil,
    weekday: String? = nil,
    era: String? = nil,
    year: String? = nil,
    month: String? = nil,
    day: String? = nil,
    dayPeriod: String? = nil,
    hour: String? = nil,
    minute: String? = nil,
    second: String? = nil,
    fractionalSecondDigits: Int? = nil,
    timeZoneName: String? = nil,
    formatMatcher: String? = nil
  ) {
    self.locale = locale
    self.format = format
    self.listStyle = listStyle
    self.calendar = calendar
    self.numberingSystem = numberingSystem
    self.timeZone = timeZone
    self.hourCycle = hourCycle
    self.hour12 = hour12
    self.dateStyle = dateStyle
    self.timeStyle = timeStyle
    self.weekday = weekday
    self.era = era
    self.year = year
    self.month = month
    self.day = day
    self.dayPeriod = dayPeriod
    self.hour = hour
    self.minute = minute
    self.second = second
    self.fractionalSecondDigits = fractionalSecondDigits
    self.timeZoneName = timeZoneName
    self.formatMatcher = formatMatcher
  }

  private enum CodingKeys: String, CodingKey {
    case locale
    case format
    case listStyle = "list-style"
    case calendar
    case numberingSystem = "numbering-system"
    case timeZone = "time-zone"
    case hourCycle = "hour-cycle"
    case hour12 = "hour12"
    case dateStyle = "date-style"
    case timeStyle = "time-style"
    case weekday
    case era
    case year
    case month
    case day
    case dayPeriod = "day-period"
    case hour
    case minute
    case second
    case fractionalSecondDigits = "fractional-second-digits"
    case timeZoneName = "time-zone-name"
    case formatMatcher = "format-matcher"
  }
}

/// One top-level `<fm-format>` declaration.
public struct FMVarFormatDeclaration: Codable, Equatable, Sendable {
  /// Value kinds named by `for`, or `nil` for an unscoped declaration.
  public let targets: [FMVarFormatTarget]?
  /// Options authored on the declaration.
  public let options: FMVarFormatOptions

  /// Creates a normalized document-wide formatting declaration.
  public init(targets: [FMVarFormatTarget]? = nil, options: FMVarFormatOptions) {
    self.targets = targets
    self.options = options
  }

  private enum CodingKeys: String, CodingKey {
    case targets = "for"
    case options
  }
}

/// One formatting field whose origin can be explained to callers.
public enum FMVarFormatOption: String, Codable, Equatable, Sendable, CaseIterable, Comparable {
  /// ``FMVarFormatOptions/locale``.
  case locale
  /// ``FMVarFormatOptions/format``.
  case format
  /// ``FMVarFormatOptions/listStyle``.
  case listStyle = "list-style"
  /// ``FMVarFormatOptions/calendar``.
  case calendar
  /// ``FMVarFormatOptions/numberingSystem``.
  case numberingSystem = "numbering-system"
  /// ``FMVarFormatOptions/timeZone``.
  case timeZone = "time-zone"
  /// ``FMVarFormatOptions/hourCycle``.
  case hourCycle = "hour-cycle"
  /// ``FMVarFormatOptions/hour12``.
  case hour12
  /// ``FMVarFormatOptions/dateStyle``.
  case dateStyle = "date-style"
  /// ``FMVarFormatOptions/timeStyle``.
  case timeStyle = "time-style"
  /// ``FMVarFormatOptions/weekday``.
  case weekday
  /// ``FMVarFormatOptions/era``.
  case era
  /// ``FMVarFormatOptions/year``.
  case year
  /// ``FMVarFormatOptions/month``.
  case month
  /// ``FMVarFormatOptions/day``.
  case day
  /// ``FMVarFormatOptions/dayPeriod``.
  case dayPeriod = "day-period"
  /// ``FMVarFormatOptions/hour``.
  case hour
  /// ``FMVarFormatOptions/minute``.
  case minute
  /// ``FMVarFormatOptions/second``.
  case second
  /// ``FMVarFormatOptions/fractionalSecondDigits``.
  case fractionalSecondDigits = "fractional-second-digits"
  /// ``FMVarFormatOptions/timeZoneName``.
  case timeZoneName = "time-zone-name"
  /// ``FMVarFormatOptions/formatMatcher``.
  case formatMatcher = "format-matcher"

  /// Orders option identifiers by their stable structured-output names.
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Precedence layer that supplied an effective formatting option.
public enum FMVarConfigurationOriginKind: String, Codable, Equatable, Sendable {
  /// Value came from the fm-var specification's defaults.
  case specificationDefault = "specification-default"
  /// Value came from an unscoped `<fm-format>` declaration.
  case unscopedFormat = "unscoped-format"
  /// Value came from a matching scoped `<fm-format for="…">` declaration.
  case scopedFormat = "scoped-format"
  /// Value came directly from the reference element.
  case element
}

/// The declaration that supplied one effective formatting value.
public struct FMVarConfigurationOrigin: Codable, Equatable, Sendable {
  /// Precedence layer that supplied the value.
  public let kind: FMVarConfigurationOriginKind
  /// Zero-based source ordinal of the supplying element, when applicable.
  public let elementOrdinal: Int?

  /// Creates the provenance for one effective formatting value.
  public init(kind: FMVarConfigurationOriginKind, elementOrdinal: Int? = nil) {
    self.kind = kind
    self.elementOrdinal = elementOrdinal
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case elementOrdinal = "element-ordinal"
  }
}

/// Associates one populated effective option with the declaration that supplied it.
public struct FMVarEffectiveOptionOrigin: Codable, Equatable, Sendable, Comparable {
  /// Populated formatting field being explained.
  public let option: FMVarFormatOption
  /// Precedence layer and optional element that supplied the value.
  public let origin: FMVarConfigurationOrigin

  /// Creates one option-provenance association.
  public init(option: FMVarFormatOption, origin: FMVarConfigurationOrigin) {
    self.option = option
    self.origin = origin
  }

  /// Orders associations by the stable option identifier.
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.option < rhs.option }

  private enum CodingKeys: String, CodingKey {
    case option
    case origin
  }
}

/// Flattened formatting values and the declaration that supplied each populated option.
public struct FMVarEffectiveConfiguration: Codable, Equatable, Sendable {
  /// Values after applying defaults, document declarations, and element overrides.
  public let options: FMVarFormatOptions
  /// Deterministically ordered provenance for each populated option.
  public let origins: [FMVarEffectiveOptionOrigin]

  /// Creates an effective configuration and orders its provenance by option identifier.
  public init(options: FMVarFormatOptions, origins: [FMVarEffectiveOptionOrigin]) {
    self.options = options
    self.origins = origins.sorted()
  }

  private enum CodingKeys: String, CodingKey {
    case options
    case origins
  }

  /// Decodes an effective configuration and restores deterministic provenance ordering.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      options: try container.decode(FMVarFormatOptions.self, forKey: .options),
      origins: try container.decode([FMVarEffectiveOptionOrigin].self, forKey: .origins)
    )
  }
}
