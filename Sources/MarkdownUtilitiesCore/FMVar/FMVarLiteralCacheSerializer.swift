/// A text value cannot be represented by a version 1 inline cache.
public enum FMVarLiteralCacheError: Error, Equatable, Sendable {
  /// Embedded CR/LF or a character forbidden by XML 1.0.
  case unsupportedCharacter
}

/// Serializes authoritative or fallback text as literal Markdown/custom-element cache content.
public struct FMVarLiteralCacheSerializer: Sendable {
  public init() {}

  /// Escapes once, without interpreting existing entities or recursively evaluating markup.
  public func serialize(_ text: String) throws(FMVarLiteralCacheError) -> String {
    guard Self.isSupportedText(text) else { throw .unsupportedCharacter }
    var output = ""
    for scalar in text.unicodeScalars {
      switch scalar.value {
      case 38: output += "&amp;"
      case 60: output += "&lt;"
      case 62: output += "&gt;"
      case 92, 96, 42, 95, 126, 91, 93, 124: output += "&#\(scalar.value);"
      default: output.unicodeScalars.append(scalar)
      }
    }
    return output
  }

  // Shared by coercion and final output validation, including injected formatter output.
  static func isSupportedText(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { scalar in
      switch scalar.value {
      case 0x09, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: true
      default: false
      }
    }
  }
}
