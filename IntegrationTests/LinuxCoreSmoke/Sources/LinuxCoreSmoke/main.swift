import MarkdownUtilitiesCore

enum LinuxCoreSmokeError: Error {
  case frontmatterNotParsed
  case bodyNotParsed
  case emptyAST
  case renderMismatch
}

@main
struct LinuxCoreSmoke {
  static func main() async throws {
    let content = """
      ---
      title: Linux
      ---
      # Portable Core
      """
    let document = try MarkdownDocument(content: content)

    guard document.hasFrontMatter else {
      throw LinuxCoreSmokeError.frontmatterNotParsed
    }
    guard document.body.contains("# Portable Core") else {
      throw LinuxCoreSmokeError.bodyNotParsed
    }

    let ast = try await document.parseAST()
    guard !ast.children.isEmpty else {
      throw LinuxCoreSmokeError.emptyAST
    }

    let rendered = try document.render()
    guard rendered.contains("title: Linux"), rendered.contains("# Portable Core") else {
      throw LinuxCoreSmokeError.renderMismatch
    }

    print("MarkdownUtilitiesCore Linux smoke test passed")
  }
}
