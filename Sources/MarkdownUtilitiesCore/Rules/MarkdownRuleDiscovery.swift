import Parsing

extension MarkdownRuleChecker {
  /// Conservative directory roots implied by positive path globs.
  /// Recursive match expressions retain full discovery until their boolean
  /// semantics can be narrowed without losing possible members.
  package func discoveryDirectories(for rule: CompiledMarkdownRule) -> [String] {
    let applicability: MarkdownRuleApplicability
    if let expression = rule.definition.matchExpression {
      guard case .leaf(let leaf) = expression else { return [""] }
      applicability = leaf
    } else { applicability = rule.definition.applicability }
    guard !applicability.paths.isEmpty else { return [""] }
    var directories: [String] = []
    for pattern in applicability.paths {
      var input = pattern[...]
      let parser = Prefix<Substring> { $0 != "*" && $0 != "?" }
      guard let literal = try? parser.parse(&input) else { return [""] }
      let components = literal.split(separator: "/", omittingEmptySubsequences: false).dropLast()
      guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else { return [""] }
      let directory = components.joined(separator: "/") + "/"
      if directories.contains(where: { directory.hasPrefix($0) }) { continue }
      directories.removeAll { $0.hasPrefix(directory) }
      directories.append(directory)
    }
    return directories.sorted()
  }
}
