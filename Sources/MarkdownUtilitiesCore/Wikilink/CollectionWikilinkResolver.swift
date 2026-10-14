import Foundation
import Parsing

/// Resolution evidence within one declared collection namespace.
public struct CollectionWikilinkResolution: Codable, Equatable, Sendable {
  public enum Status: String, Codable, Sendable { case resolved, unresolved, ambiguous, unavailable }
  public var status: Status
  public var candidates: [String]
  public var namespaceComplete: Bool
  public var query: String
  public var destination: String? { status == .resolved ? candidates.first : nil }
}

/// Pure resolution over confined collection-relative paths supplied by a host.
public struct CollectionWikilinkResolver: Sendable {
  public let paths: Set<String>
  public let namespaceComplete: Bool
  /// Paths for which the host has independently certified presence or absence.
  public let completeExactPaths: Set<String>
  private let stems: [String: [String]]

  public init(paths: Set<String>, namespaceComplete: Bool, completeExactPaths: Set<String> = []) {
    self.paths = paths
    self.namespaceComplete = namespaceComplete
    self.completeExactPaths = completeExactPaths
    self.stems = Dictionary(grouping: paths.sorted()) { path in
      Self.stem(String(path.split(separator: "/").last ?? "")).lowercased()
    }
  }

  public func resolve(target: String, from source: String) -> CollectionWikilinkResolution {
    if target.isEmpty {
      return .init(status: paths.contains(source) ? .resolved : .unavailable,
        candidates: paths.contains(source) ? [source] : [], namespaceComplete: paths.contains(source), query: source)
    }
    let name = String(target.split(separator: "/").last ?? "")
    let ext = Self.suffix(name)
    var candidates: [String] = []
    var complete = namespaceComplete
    var query = "name:" + target
    if target.contains("/") {
      var input = target[...]
      let relative = (try? OneOf { "./"; "../" }.parse(&input)) != nil
      var components = relative ? source.split(separator: "/").dropLast().map(String.init) : []
      var confined = !target.hasPrefix("/")
      for component in target.split(separator: "/") {
        if component == "." { continue }
        if component == ".." {
          if components.isEmpty { confined = false } else { components.removeLast() }
        } else { components.append(String(component)) }
      }
      let path = components.joined(separator: "/")
      let exact = ext.isEmpty ? [path + ".md", path + ".markdown"] : [path]
      query = "path:" + path
      complete = namespaceComplete || Set(exact).isSubset(of: completeExactPaths)
      if confined { candidates = exact.filter(paths.contains) }
    } else {
      let stem = Self.stem(name).lowercased()
      candidates = (stems[stem] ?? []).filter { path in
        let file = String(path.split(separator: "/").last ?? "")
        let suffix = Self.suffix(file)
        return Self.stem(file).lowercased() == stem
          && (ext.isEmpty ? ["md", "markdown"].contains(suffix) : suffix == ext)
      }.sorted()
    }
    return .init(status: candidates.count > 1 ? .ambiguous : (!complete ? .unavailable : (candidates.isEmpty ? .unresolved : .resolved)),
      candidates: candidates.sorted(), namespaceComplete: complete, query: query)
  }

  private static func suffix(_ name: String) -> String {
    guard let period = name.lastIndex(of: "."), period != name.startIndex else { return "" }
    return String(name[name.index(after: period)...])
  }

  private static func stem(_ name: String) -> String {
    guard let period = name.lastIndex(of: "."), period != name.startIndex else { return name }
    return String(name[..<period])
  }
}
