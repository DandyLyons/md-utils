import Parsing

/// Rewrites parsed occurrences without changing surrounding text or link suffixes.
public enum WikilinkRewriter {
  /// The callback returns a replacement target, or nil to preserve the occurrence.
  public static func rewrite(
    _ text: String,
    target: (Wikilink) -> String?,
  ) -> String {
    var remaining = text[...]
    var output = ""
    let parser = WikilinkParser()
    while let brackets = remaining.range(of: "[[") {
      var start = brackets.lowerBound
      if start > remaining.startIndex, remaining[remaining.index(before: start)] == "!" {
        start = remaining.index(before: start)
      }
      var candidate = remaining[start...]
      guard let link = try? parser.parse(&candidate) else {
        output += remaining[..<brackets.upperBound]
        remaining = remaining[brackets.upperBound...]
        continue
      }
      output += remaining[..<start]
      if let replacement = target(link) {
        let prefix = link.isEmbed ? "![[" : "[["
        var interior = link.rawValue.dropFirst(prefix.count).dropLast(2)
        // Consume the raw target with Parsing, retaining the exact fragment/alias suffix.
        while !interior.isEmpty {
          _ = try? Prefix { (character: Character) in
            character != "\\" && character != "#" && character != "|"
          }.parse(&interior)
          guard interior.first == "\\" else { break }
          interior.removeFirst()
          if !interior.isEmpty { interior.removeFirst() }
        }
        output += prefix + replacement.replacingOccurrences(of: "|", with: "\\|") + interior + "]]"
      } else {
        output += link.rawValue
      }
      remaining = candidate
    }
    return output + remaining
  }
}
