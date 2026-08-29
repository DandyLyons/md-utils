import Foundation

/// The custom element represented by an fm-var source model.
public enum FMVarElementKind: String, Codable, Equatable, Sendable, CaseIterable {
  case variable = "fm-var"
  case list = "fm-list"
  case format = "fm-format"
}

/// The quote delimiter authored around an attribute value.
public enum FMVarAttributeQuoteStyle: String, Codable, Equatable, Sendable {
  case unquoted
  case single
  case double
}

/// One ordered, lossless attribute captured from an fm-var family element.
public struct FMVarRawAttribute: Codable, Equatable, Sendable {
  public let rawText: String
  public let name: String
  public let value: String?
  public let quoteStyle: FMVarAttributeQuoteStyle?
  public let range: FMVarSourceRange
  public let nameRange: FMVarSourceRange
  public let valueRange: FMVarSourceRange?

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
public struct FMVarElement: Codable, Equatable, Sendable {
  public let kind: FMVarElementKind
  public let ordinal: Int
  public let attributes: [FMVarRawAttribute]
  public let range: FMVarSourceRange
  public let openingTagRange: FMVarSourceRange
  public let cacheRange: FMVarSourceRange?
  public let closingTagRange: FMVarSourceRange?

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

/// Portable scalar interpretations supported by RFC 001 Rev 2.
public enum FMVarValueType: String, Codable, Equatable, Sendable, CaseIterable {
  case string
  case boolean
  case integer
  case number
  case date
  case datetime
  case timestamp
}

/// Value kinds accepted by an `<fm-format for="…">` declaration.
public enum FMVarFormatTarget: String, Codable, Equatable, Sendable, CaseIterable {
  case string
  case boolean
  case integer
  case number
  case date
  case datetime
  case timestamp
  case array
}

public enum FMVarListFormat: String, Codable, Equatable, Sendable, CaseIterable {
  case ordered
  case unordered
  case conjunction
  case disjunction
  case unit
}

public enum FMVarListStyle: String, Codable, Equatable, Sendable, CaseIterable {
  case long
  case short
  case narrow
}

/// Normalized declaration for one scalar `<fm-var>` reference.
public struct FMVarScalarDeclaration: Codable, Equatable, Sendable {
  public let key: String
  public let source: String?
  public let defaultValue: String?
  public let type: FMVarValueType
  public let format: String?
  public let locale: String?

  public init(
    key: String,
    source: String? = nil,
    defaultValue: String? = nil,
    type: FMVarValueType = .string,
    format: String? = nil,
    locale: String? = nil
  ) {
    self.key = key
    self.source = source
    self.defaultValue = defaultValue
    self.type = type
    self.format = format
    self.locale = locale
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case source = "src"
    case defaultValue = "default"
    case type
    case format
    case locale
  }
}

/// Normalized declaration for one `<fm-list>` reference.
public struct FMVarListDeclaration: Codable, Equatable, Sendable {
  public let key: String
  public let source: String?
  public let itemType: FMVarValueType
  public let format: FMVarListFormat
  public let locale: String?
  public let listStyle: FMVarListStyle

  public init(
    key: String,
    source: String? = nil,
    itemType: FMVarValueType = .string,
    format: FMVarListFormat,
    locale: String? = nil,
    listStyle: FMVarListStyle = .long
  ) {
    self.key = key
    self.source = source
    self.itemType = itemType
    self.format = format
    self.locale = locale
    self.listStyle = listStyle
  }

  private enum CodingKeys: String, CodingKey {
    case key
    case source = "src"
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
  public var locale: String?
  public var format: String?
  public var listStyle: FMVarListStyle?
  public var calendar: String?
  public var numberingSystem: String?
  public var timeZone: String?
  public var hourCycle: String?
  public var hour12: Bool?
  public var dateStyle: String?
  public var timeStyle: String?
  public var weekday: String?
  public var era: String?
  public var year: String?
  public var month: String?
  public var day: String?
  public var dayPeriod: String?
  public var hour: String?
  public var minute: String?
  public var second: String?
  public var fractionalSecondDigits: Int?
  public var timeZoneName: String?
  public var formatMatcher: String?

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
  public let targets: [FMVarFormatTarget]?
  public let options: FMVarFormatOptions

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
  case locale
  case format
  case listStyle = "list-style"
  case calendar
  case numberingSystem = "numbering-system"
  case timeZone = "time-zone"
  case hourCycle = "hour-cycle"
  case hour12
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

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum FMVarConfigurationOriginKind: String, Codable, Equatable, Sendable {
  case specificationDefault = "specification-default"
  case unscopedFormat = "unscoped-format"
  case scopedFormat = "scoped-format"
  case element
}

/// The declaration that supplied one effective formatting value.
public struct FMVarConfigurationOrigin: Codable, Equatable, Sendable {
  public let kind: FMVarConfigurationOriginKind
  public let elementOrdinal: Int?

  public init(kind: FMVarConfigurationOriginKind, elementOrdinal: Int? = nil) {
    self.kind = kind
    self.elementOrdinal = elementOrdinal
  }

  private enum CodingKeys: String, CodingKey {
    case kind
    case elementOrdinal = "element-ordinal"
  }
}

public struct FMVarEffectiveOptionOrigin: Codable, Equatable, Sendable, Comparable {
  public let option: FMVarFormatOption
  public let origin: FMVarConfigurationOrigin

  public init(option: FMVarFormatOption, origin: FMVarConfigurationOrigin) {
    self.option = option
    self.origin = origin
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.option < rhs.option }

  private enum CodingKeys: String, CodingKey {
    case option
    case origin
  }
}

/// Flattened formatting values and the declaration that supplied each populated option.
public struct FMVarEffectiveConfiguration: Codable, Equatable, Sendable {
  public let options: FMVarFormatOptions
  public let origins: [FMVarEffectiveOptionOrigin]

  public init(options: FMVarFormatOptions, origins: [FMVarEffectiveOptionOrigin]) {
    self.options = options
    self.origins = origins.sorted()
  }

  private enum CodingKeys: String, CodingKey {
    case options
    case origins
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      options: try container.decode(FMVarFormatOptions.self, forKey: .options),
      origins: try container.decode([FMVarEffectiveOptionOrigin].self, forKey: .origins)
    )
  }
}
