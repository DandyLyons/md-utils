import MarkdownUtilitiesCore

enum LinuxCoreSmokeError: Error {
  case frontmatterNotParsed
  case bodyNotParsed
  case emptyAST
  case renderMismatch
  case typeAssessmentFailed
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

    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "LinuxDocument"),
      version: "smoke",
      frontmatter: MarkdownFrontmatterDefinition(schemas: [
        .inline(.object([
          "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
          "type": .string("object"),
          "required": .array([.string("title")]),
        ]))
      ]),
      body: MarkdownConstraintGroup(requirements: [
        MarkdownConstraint(
          id: "portable-heading",
          predicate: .heading(MarkdownHeadingPredicate(text: "Portable Core", level: 1))
        )
      ])
    )
    let checker = try MarkdownTypeChecker(
      registry: MarkdownTypeRegistry(definitions: [definition])
    )
    let assessment = try await checker.assess(MarkdownRecord(content: content), as: "LinuxDocument")
    guard assessment.conforms else {
      throw LinuxCoreSmokeError.typeAssessmentFailed
    }

    print("MarkdownUtilitiesCore Linux smoke test passed")
  }
}
