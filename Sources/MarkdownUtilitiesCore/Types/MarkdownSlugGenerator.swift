import Foundation
import Parsing

/// Pure slug formatting. Collection uniqueness and suffix allocation belong to the caller.
public enum MarkdownSlugGenerator {
  // Retain the historical heading rules, fallback, and local suffix allocation.
  static func headingAnchor(
    from text: String,
    existingSlugs: Set<String>,
  ) -> String {
    // Step 1: Convert to lowercase
    var slug = text.lowercased()

    // Step 2: Replace spaces with hyphens
    slug = slug.replacingOccurrences(of: " ", with: "-")

    // Step 3: Remove all characters except alphanumerics, hyphens, and underscores
    slug = slug.filter { char in
      char.isLetter || char.isNumber || char == "-" || char == "_"
    }

    // Remove leading/trailing hyphens
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

    // If slug is empty after processing, use a default
    if slug.isEmpty {
      slug = "section"
    }

    // Step 4: Handle duplicates with numeric suffixes
    var uniqueSlug = slug
    var counter = 1
    while existingSlugs.contains(uniqueSlug) {
      uniqueSlug = "\(slug)-\(counter)"
      counter += 1
    }

    return uniqueSlug
  }

  /// A resource slug cannot be generated or accepted under its configured policy.
  public enum Failure: Error, LocalizedError, Equatable, Sendable {
    case emptyResult
    case unrepresentable
    case invalidProvidedValue

    public var errorDescription: String? {
      switch self {
      case .emptyResult: "The source contains no letters or numbers for a slug."
      case .unrepresentable: "The source cannot be represented by the selected slug policy."
      case .invalidProvidedValue: "The supplied slug does not match the selected slug policy."
      }
    }
  }

  /// Generates a slug by joining runs of letters and numbers with a single hyphen.
  ///
  /// Unicode is preserved. ASCII policies reject non-ASCII letters and numbers;
  /// they do not transliterate or silently discard them. No files are renamed.
  public static func generate(
    from source: String,
    policy: MarkdownSlugPolicy = .unicode,
  ) throws -> String {
    var input = (policy == .preserve ? source : source.lowercased())[...]
    let separators = Prefix<Substring> { !$0.isLetter && !$0.isNumber }
    let word = Prefix<Substring>(1...) { $0.isLetter || $0.isNumber }
    var words: [String] = []
    while !input.isEmpty {
      _ = try separators.parse(&input)
      guard !input.isEmpty else { break }
      words.append(String(try word.parse(&input)))
    }
    let result = words.joined(separator: "-")
    guard !result.isEmpty else { throw Failure.emptyResult }
    guard policy.isValid(result) else { throw Failure.unrepresentable }
    return result
  }

  /// Preserves a supplied value exactly, generating only when it is absent.
  ///
  /// An explicitly empty or invalid value fails validation. Call this during
  /// creation, then perform any configured uniqueness check within coordinated
  /// persistence. Re-running it on title edits would regenerate missing slugs.
  public static func resolve(
    provided: String?,
    from source: String,
    policy: MarkdownSlugPolicy = .unicode,
  ) throws -> String {
    guard let provided else { return try generate(from: source, policy: policy) }
    guard policy.isValid(provided) else { throw Failure.invalidProvidedValue }
    return provided
  }
}
