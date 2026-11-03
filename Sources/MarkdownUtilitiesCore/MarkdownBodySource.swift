import Parsing

/// A body-editing view that treats the physical frontmatter as opaque text.
/// Uses the shared delimiter parser without decoding YAML or TOML values.
package struct MarkdownBodySource {
  package let document: MarkdownDocument
  private let prefix: String

  package init(content: String) throws {
    var input = Substring(content)
    let (_, body, _) = try FrontMatterParser().parse(&input)
    prefix = String(decoding: content.utf8.prefix(content.utf8.count - body.utf8.count), as: UTF8.self)
    document = MarkdownDocument(frontMatter: FrontMatter(), body: body)
  }

  /// Reattaches the exact original prefix, including delimiters and comments.
  package func render(body: String) -> String {
    prefix + body
  }
}
