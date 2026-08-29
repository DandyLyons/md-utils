import MarkdownUtilitiesCore

enum WasmCoreSmokeError: Error {
  case frontmatterNotParsed
  case emptyAST
  case renderMismatch
  case tomlMismatch
  case typeAssessmentFailed
  case fmVarModelMismatch
}

@main
struct WasmCoreSmoke {
  static func main() async throws {
    let content = """
      ---
      title: WebAssembly
      ratio: 1.25
      ---
      # Portable Core

      - [x] Parsed with swift-cmark

      | Runtime | Status |
      | --- | --- |
      | WASI | supported |
      """
    let document = try MarkdownDocument(content: content)

    guard document.hasFrontMatter else {
      throw WasmCoreSmokeError.frontmatterNotParsed
    }

    let ast = try await document.parseAST()
    guard !ast.children.isEmpty else {
      throw WasmCoreSmokeError.emptyAST
    }

    let rendered = try document.render()
    guard rendered.contains("ratio: 1.25"), rendered.contains("# Portable Core") else {
      throw WasmCoreSmokeError.renderMismatch
    }

    let tomlDocument = try MarkdownDocument(content: """
      +++
      title = "WebAssembly TOML"
      tags = ["swift", "wasm"]
      +++
      # TOML
      """)
    let tomlRendered = try tomlDocument.render()
    guard tomlDocument.frontMatterFormat == .toml,
      tomlDocument.frontMatter["tags"]?.sequence?.count == 2,
      tomlRendered.hasPrefix("+++\n"),
      tomlRendered.contains("title = \"WebAssembly TOML\"")
    else {
      throw WasmCoreSmokeError.tomlMismatch
    }

    let definition = MarkdownTypeDefinition(
      name: MarkdownTypeName(rawValue: "WasmDocument"),
      version: "smoke",
      frontmatter: MarkdownFrontmatterDefinition(schemas: [
        .inline(.object([
          "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
          "type": .string("object"),
          "required": .array([.string("title"), .string("ratio")]),
          "properties": .object([
            "title": .object(["type": .string("string")]),
            "ratio": .object(["type": .string("number")]),
          ]),
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
    let assessment = try await checker.assess(
      MarkdownRecord(content: content),
      as: "WasmDocument"
    )
    guard assessment.conforms else {
      throw WasmCoreSmokeError.typeAssessmentFailed
    }

    let fmVarSourceMap = FMVarSourceMap(source: "é\r\n<fm-var key=\"title\">old</fm-var>")
    let fmVarPosition = try fmVarSourceMap.position(atUTF8Offset: 24)
    let fmVarDeclaration = FMVarScalarDeclaration(
      key: "title",
      type: .string,
      locale: "en-US"
    )
    guard fmVarPosition.line == 2,
      fmVarPosition.column == 21,
      try fmVarSourceMap.utf8Offset(
        line: fmVarPosition.line,
        column: fmVarPosition.column
      ) == 24,
      fmVarDeclaration.type == .string
    else {
      throw WasmCoreSmokeError.fmVarModelMismatch
    }

    print("MarkdownUtilitiesCore WebAssembly smoke test passed")
  }
}
