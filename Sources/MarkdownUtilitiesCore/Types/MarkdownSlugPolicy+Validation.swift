extension MarkdownSlugPolicy {
  /// Checks an authored slug without normalizing or allocating a unique value.
  public func isValid(_ value: String) -> Bool {
    guard value.isEmpty == false else { return false }
    switch self {
    case .strictASCII:
      return Self.validSeparatedASCII(value, permitsUppercase: false)
    case .preserve:
      return Self.validSeparatedASCII(value, permitsUppercase: true)
    case .unicode:
      guard value == value.lowercased() else { return false }
      var previousWasSeparator = false
      var foundAlphanumeric = false
      for character in value {
        let isSeparator = character == "-" || character == "_"
        if isSeparator {
          if previousWasSeparator || foundAlphanumeric == false { return false }
          previousWasSeparator = true
        } else {
          guard character.isLetter || character.isNumber else { return false }
          foundAlphanumeric = true
          previousWasSeparator = false
        }
      }
      return foundAlphanumeric && previousWasSeparator == false
    }
  }

  private static func validSeparatedASCII(_ value: String, permitsUppercase: Bool) -> Bool {
    var previousWasHyphen = false
    var foundAlphanumeric = false
    for scalar in value.unicodeScalars {
      let isLowercase = (97...122).contains(scalar.value)
      let isUppercase = permitsUppercase && (65...90).contains(scalar.value)
      let isDigit = (48...57).contains(scalar.value)
      if scalar == "-" {
        if previousWasHyphen || foundAlphanumeric == false { return false }
        previousWasHyphen = true
      } else {
        guard isLowercase || isUppercase || isDigit else { return false }
        foundAlphanumeric = true
        previousWasHyphen = false
      }
    }
    return foundAlphanumeric && previousWasHyphen == false
  }
}
