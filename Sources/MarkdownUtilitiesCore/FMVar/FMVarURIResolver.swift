import Foundation
import Parsing

/// Errors produced while parsing or resolving an fm-var RFC 3986 source reference.
public enum FMVarURIResolutionError: Error, Codable, Equatable, Sendable, LocalizedError {
  /// The containing document base was not an absolute, fragment-free URI.
  case invalidBaseURI(String)
  /// The authored `src` did not satisfy the RFC 3986 URI-reference grammar.
  case invalidReference(String)
  /// The authored `src` contained a fragment component, including an empty fragment.
  case fragmentNotAllowed(String)

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURI(let value):
      "The fm-var base URI is not absolute and fragment-free: \(value)"
    case .invalidReference(let value):
      "The fm-var src is not an RFC 3986 URI reference: \(value)"
    case .fragmentNotAllowed(let value):
      "The fm-var src must not contain a URI fragment: \(value)"
    }
  }
}

/// Parses and resolves fragment-free fm-var source references according to RFC 3986.
///
/// The resolver performs identifier processing only. It does not dereference the resulting URI or
/// decide whether a host permits access. See <doc:ResolvingFMVarSources> for provider integration.
public struct FMVarURIResolver: Sendable {
  /// Creates an RFC 3986 source resolver.
  public init() {}

  /// Resolves an authored source reference against an absolute containing-document base URI.
  ///
  /// - Parameters:
  ///   - reference: Authored `src`, or `nil` for the containing document.
  ///   - base: Host-established identifier for the containing document.
  /// - Returns: An absolute, fragment-free resource identifier.
  /// - Throws: ``FMVarURIResolutionError`` when the base or reference is invalid.
  public func resolve(
    reference: String?,
    relativeTo base: FMVarResourceIdentifier
  ) throws -> FMVarResourceIdentifier {
    let baseComponents: URIComponents
    do {
      baseComponents = try URIReferenceParser().parse(base.rawValue)
    } catch {
      throw FMVarURIResolutionError.invalidBaseURI(base.rawValue)
    }
    guard baseComponents.scheme != nil, baseComponents.fragment == nil else {
      throw FMVarURIResolutionError.invalidBaseURI(base.rawValue)
    }

    guard let reference else { return base }
    let source: URIComponents
    do {
      source = try URIReferenceParser().parse(reference)
    } catch {
      throw FMVarURIResolutionError.invalidReference(reference)
    }
    guard source.fragment == nil else {
      throw FMVarURIResolutionError.fragmentNotAllowed(reference)
    }

    let target: URIComponents
    if source.scheme != nil {
      target = URIComponents(
        scheme: source.scheme,
        authority: source.authority,
        path: removeDotSegments(source.path),
        query: source.query
      )
    } else if source.authority != nil {
      target = URIComponents(
        scheme: baseComponents.scheme,
        authority: source.authority,
        path: removeDotSegments(source.path),
        query: source.query
      )
    } else if source.path.isEmpty {
      target = URIComponents(
        scheme: baseComponents.scheme,
        authority: baseComponents.authority,
        path: baseComponents.path,
        query: source.query ?? baseComponents.query
      )
    } else {
      let path = source.path.hasPrefix("/")
        ? source.path
        : merge(base: baseComponents, referencePath: source.path)
      target = URIComponents(
        scheme: baseComponents.scheme,
        authority: baseComponents.authority,
        path: removeDotSegments(path),
        query: source.query
      )
    }

    return FMVarResourceIdentifier(rawValue: target.serialized)
  }

  private func merge(base: URIComponents, referencePath: String) -> String {
    if base.authority != nil, base.path.isEmpty {
      return "/" + referencePath
    }
    guard let slash = base.path.lastIndex(of: "/") else { return referencePath }
    return String(base.path[...slash]) + referencePath
  }

  private func removeDotSegments(_ path: String) -> String {
    var input = path
    var output = ""
    while input.isEmpty == false {
      if input.hasPrefix("../") {
        input.removeFirst(3)
      } else if input.hasPrefix("./") {
        input.removeFirst(2)
      } else if input.hasPrefix("/./") {
        input.removeFirst(2)
      } else if input == "/." {
        input = "/"
      } else if input.hasPrefix("/../") {
        input.removeFirst(3)
        removeLastSegment(from: &output)
      } else if input == "/.." {
        input = "/"
        removeLastSegment(from: &output)
      } else if input == "." || input == ".." {
        input = ""
      } else {
        let segmentEnd: String.Index?
        if input.hasPrefix("/") {
          let afterSlash = input.index(after: input.startIndex)
          segmentEnd = input[afterSlash...].firstIndex(of: "/")
        } else {
          segmentEnd = input.firstIndex(of: "/")
        }
        let end = segmentEnd ?? input.endIndex
        output += input[..<end]
        input.removeSubrange(..<end)
      }
    }
    return output
  }

  private func removeLastSegment(from output: inout String) {
    guard let slash = output.lastIndex(of: "/") else {
      output = ""
      return
    }
    output.removeSubrange(slash...)
  }
}

private struct URIComponents: Equatable, Sendable {
  let scheme: String?
  let authority: String?
  let path: String
  let query: String?
  let fragment: String?

  init(
    scheme: String?,
    authority: String?,
    path: String,
    query: String?,
    fragment: String? = nil
  ) {
    self.scheme = scheme
    self.authority = authority
    self.path = path
    self.query = query
    self.fragment = fragment
  }

  var serialized: String {
    var result = ""
    if let scheme { result += scheme + ":" }
    if let authority { result += "//" + authority }
    result += path
    if let query { result += "?" + query }
    if let fragment { result += "#" + fragment }
    return result
  }
}

private struct URIReferenceParser: Parsing.Parser {
  typealias Input = Substring
  typealias Output = URIComponents

  func parse(_ input: inout Substring) throws -> URIComponents {
    let source = String(input)
    input = input[input.endIndex...]
    guard source.unicodeScalars.allSatisfy({ $0.value < 128 }) else {
      throw URIParseError.invalidCharacter
    }

    let fragmentSplit = splitOnce(source, separator: "#")
    var head = fragmentSplit.before
    let fragment = fragmentSplit.after
    if let fragment, validate(fragment, allowed: isQueryOrFragmentCharacter) == false {
      throw URIParseError.invalidCharacter
    }

    var scheme: String?
    if let colon = head.firstIndex(of: ":"),
      head[..<colon].contains(where: { $0 == "/" || $0 == "?" }) == false
    {
      let candidate = String(head[..<colon])
      guard isScheme(candidate) else { throw URIParseError.invalidScheme }
      scheme = candidate
      head = String(head[head.index(after: colon)...])
    }

    var authority: String?
    if head.hasPrefix("//") {
      head.removeFirst(2)
      let end = head.firstIndex(where: { $0 == "/" || $0 == "?" }) ?? head.endIndex
      authority = String(head[..<end])
      head.removeSubrange(..<end)
      guard let authority, validateAuthority(authority) else {
        throw URIParseError.invalidAuthority
      }
    }

    let querySplit = splitOnce(head, separator: "?")
    let path = querySplit.before
    let query = querySplit.after
    guard validate(path, allowed: isPathCharacter),
      query.map({ validate($0, allowed: isQueryOrFragmentCharacter) }) ?? true
    else {
      throw URIParseError.invalidCharacter
    }
    guard authority == nil || path.isEmpty || path.hasPrefix("/"),
      scheme == nil || authority != nil || path.hasPrefix("//") == false
    else {
      throw URIParseError.invalidPath
    }

    if scheme == nil, authority == nil,
      let firstSegment = path.split(separator: "/", omittingEmptySubsequences: false).first,
      firstSegment.contains(":")
    {
      throw URIParseError.invalidPath
    }

    return URIComponents(
      scheme: scheme,
      authority: authority,
      path: path,
      query: query,
      fragment: fragment
    )
  }

  private func splitOnce(_ source: String, separator: Character) -> (before: String, after: String?) {
    guard let index = source.firstIndex(of: separator) else { return (source, nil) }
    return (
      String(source[..<index]),
      String(source[source.index(after: index)...])
    )
  }

  private func isScheme(_ source: String) -> Bool {
    guard let first = source.unicodeScalars.first, isAlpha(first) else { return false }
    return source.unicodeScalars.dropFirst().allSatisfy { scalar in
      isAlpha(scalar) || isDigit(scalar) || [43, 45, 46].contains(scalar.value)
    }
  }

  private func validate(
    _ source: String,
    allowed: (UnicodeScalar) -> Bool
  ) -> Bool {
    let scalars = Array(source.unicodeScalars)
    var index = 0
    while index < scalars.count {
      let scalar = scalars[index]
      if scalar.value == 37 {
        guard index + 2 < scalars.count,
          isHexDigit(scalars[index + 1]),
          isHexDigit(scalars[index + 2])
        else {
          return false
        }
        index += 3
      } else {
        guard allowed(scalar) else { return false }
        index += 1
      }
    }
    return true
  }

  private func isPathCharacter(_ scalar: UnicodeScalar) -> Bool {
    isUnreserved(scalar) || isSubDelimiter(scalar) || [58, 64, 47].contains(scalar.value)
  }

  private func isQueryOrFragmentCharacter(_ scalar: UnicodeScalar) -> Bool {
    isPathCharacter(scalar) || scalar.value == 63
  }

  private func isUnreserved(_ scalar: UnicodeScalar) -> Bool {
    isAlpha(scalar) || isDigit(scalar) || [45, 46, 95, 126].contains(scalar.value)
  }

  private func isSubDelimiter(_ scalar: UnicodeScalar) -> Bool {
    [33, 36, 38, 39, 40, 41, 42, 43, 44, 59, 61].contains(scalar.value)
  }

  private func isAlpha(_ scalar: UnicodeScalar) -> Bool {
    (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
  }

  private func isDigit(_ scalar: UnicodeScalar) -> Bool {
    (48...57).contains(scalar.value)
  }

  private func isHexDigit(_ scalar: UnicodeScalar) -> Bool {
    isDigit(scalar) || (65...70).contains(scalar.value) || (97...102).contains(scalar.value)
  }

  private func validateAuthority(_ authority: String) -> Bool {
    let atSigns = authority.indices.filter { authority[$0] == "@" }
    guard atSigns.count <= 1 else { return false }
    let hostAndPort: Substring
    if let at = atSigns.first {
      let userInfo = String(authority[..<at])
      guard validate(userInfo, allowed: { isUnreserved($0) || isSubDelimiter($0) || $0.value == 58 })
      else { return false }
      hostAndPort = authority[authority.index(after: at)...]
    } else {
      hostAndPort = authority[...]
    }

    if hostAndPort.hasPrefix("[") {
      guard let close = hostAndPort.firstIndex(of: "]") else { return false }
      let literal = String(hostAndPort[hostAndPort.index(after: hostAndPort.startIndex)..<close])
      let suffix = hostAndPort[hostAndPort.index(after: close)...]
      guard suffix.isEmpty || (suffix.hasPrefix(":") && suffix.dropFirst().allSatisfy(\.isNumber))
      else { return false }
      return validIPLiteral(literal)
    }

    guard hostAndPort.contains("[") == false, hostAndPort.contains("]") == false else { return false }
    let colonCount = hostAndPort.filter { $0 == ":" }.count
    guard colonCount <= 1 else { return false }
    let host: String
    if let colon = hostAndPort.lastIndex(of: ":") {
      host = String(hostAndPort[..<colon])
      guard hostAndPort[hostAndPort.index(after: colon)...].allSatisfy(\.isNumber) else {
        return false
      }
    } else {
      host = String(hostAndPort)
    }
    return validate(host, allowed: { isUnreserved($0) || isSubDelimiter($0) })
  }

  private func validIPLiteral(_ source: String) -> Bool {
    if source.first == "v" || source.first == "V" {
      guard let period = source.firstIndex(of: ".") else { return false }
      let version = source[source.index(after: source.startIndex)..<period]
      let address = source[source.index(after: period)...]
      return version.isEmpty == false
        && version.unicodeScalars.allSatisfy(isHexDigit)
        && address.isEmpty == false
        && address.unicodeScalars.allSatisfy {
          isUnreserved($0) || isSubDelimiter($0) || $0.value == 58
        }
    }
    return validIPv6Address(source)
  }

  private func validIPv6Address(_ source: String) -> Bool {
    guard source.contains(":"),
      source.unicodeScalars.allSatisfy({ isHexDigit($0) || $0.value == 58 || $0.value == 46 })
    else { return false }
    let compressionParts = source.components(separatedBy: "::")
    guard compressionParts.count <= 2 else { return false }
    if compressionParts.count == 2,
      compressionParts[0].hasSuffix(":") || compressionParts[1].hasPrefix(":")
    {
      return false
    }
    var pieces = source.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    var pieceCount = pieces.count
    if let last = pieces.last, last.contains(".") {
      guard validIPv4Address(last) else { return false }
      pieces.removeLast()
      pieceCount += 1
    }
    guard pieces.allSatisfy({
      (1...4).contains($0.count) && $0.unicodeScalars.allSatisfy(isHexDigit)
    }) else { return false }
    return compressionParts.count == 2 ? pieceCount < 8 : pieceCount == 8
  }

  private func validIPv4Address(_ source: String) -> Bool {
    let pieces = source.split(separator: ".", omittingEmptySubsequences: false)
    guard pieces.count == 4 else { return false }
    return pieces.allSatisfy { piece in
      guard piece.isEmpty == false,
        piece.allSatisfy(\.isNumber),
        piece.count == 1 || piece.first != "0",
        UInt8(piece) != nil
      else { return false }
      return true
    }
  }
}

private enum URIParseError: Error {
  case invalidCharacter
  case invalidScheme
  case invalidAuthority
  case invalidPath
}
