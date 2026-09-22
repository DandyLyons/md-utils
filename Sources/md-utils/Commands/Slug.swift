import ArgumentParser
import MarkdownUtilitiesCore

/// Generates a slug without reading or changing files.
struct Slug: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Generate a slug from text without changing files or checking uniqueness.",
  )

  @Argument(help: "Source text; quote spaces. Use -- before text starting with a hyphen.")
  var text: String

  @Option(help: "Slug policy: unicode (default), strictASCII, or preserve.")
  var policy: String = "unicode"

  func run() throws {
    guard let selected = MarkdownSlugPolicy(rawValue: policy) else {
      throw ValidationError("Policy must be unicode, strictASCII, or preserve.")
    }
    print(try MarkdownSlugGenerator.generate(from: text, policy: selected))
  }
}
