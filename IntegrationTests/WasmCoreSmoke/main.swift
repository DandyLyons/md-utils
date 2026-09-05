import DynamicJSON
import MarkdownUtilitiesCore

enum WasmCoreSmokeError: Error {
  case frontmatterNotParsed
  case emptyAST
  case renderMismatch
  case tomlMismatch
  case typeAssessmentFailed
  case fmVarModelMismatch
  case fmVarParserMismatch
  case dynamicJSONMismatch
  case fmVarJSONPathMismatch
  case fmVarURIResolutionMismatch
  case fmVarYAMLProjectionMismatch
  case fmVarScalarCoercionMismatch
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

    let fmVarSourceMap = FMVarSourceMap(source: "é\r\n<fm-var query=\"$.title\">old</fm-var>")
    let fmVarPosition = try fmVarSourceMap.position(atUTF8Offset: 28)
    let fmVarDeclaration = FMVarScalarDeclaration(
      query: "$.title",
      type: .string,
      locale: "en-US"
    )
    guard fmVarPosition.line == 2,
      fmVarPosition.column == 25,
      try fmVarSourceMap.utf8Offset(
        line: fmVarPosition.line,
        column: fmVarPosition.column
      ) == 28,
      fmVarDeclaration.type == .string
    else {
      throw WasmCoreSmokeError.fmVarModelMismatch
    }

    let fmVarSource = "é\r\n<fm-var query=\"$.title\">old</fm-var>"
    let fmVarParseResult = try FMVarParser().parse(fmVarSource)
    guard fmVarParseResult.isValid,
      fmVarParseResult.elements.count == 1,
      try fmVarParseResult.replacingCache(ofElementOrdinal: 0, with: "new")
        == "é\r\n<fm-var query=\"$.title\">new</fm-var>"
    else {
      throw WasmCoreSmokeError.fmVarParserMismatch
    }

    let dynamicJSON: JSON = [
      "items": [
        ["title": "First"],
        ["title": "Second"],
      ]
    ]
    let dynamicJSONPath = try JSONPath(query: "$.items[*].title", strict: true)
    let dynamicJSONResults = try dynamicJSON.query(dynamicJSONPath)
    guard dynamicJSONResults.map(\.value) == [.string("First"), .string("Second")],
      dynamicJSONResults.map(\.location.description) == [
        "$['items'][0]['title']",
        "$['items'][1]['title']",
      ]
    else {
      throw WasmCoreSmokeError.dynamicJSONMismatch
    }

    let firstTitle = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$['items'][0]['title']"),
      value: .string("First"),
      sourceScalar: FMVarSourceScalar(content: "\"First\"")
    )
    let secondTitle = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$['items'][1]['title']"),
      value: .string("Second"),
      sourceScalar: FMVarSourceScalar(content: "\"Second\"")
    )
    let firstItem = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$['items'][0]"),
      value: .object([FMVarQueryObjectMember(name: "title", node: firstTitle)])
    )
    let secondItem = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$['items'][1]"),
      value: .object([FMVarQueryObjectMember(name: "title", node: secondTitle)])
    )
    let items = FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$['items']"),
      value: .array([firstItem, secondItem])
    )
    let queryArgument = FMVarQueryArgument(root: FMVarQueryNode(
      id: FMVarQueryNodeID(rawValue: "$"),
      value: .object([FMVarQueryObjectMember(name: "items", node: items)])
    ))
    let fmVarJSONPathResult = FMVarJSONPathEvaluator().evaluate(
      query: "$.items[*].title",
      argument: queryArgument
    )
    guard fmVarJSONPathResult.status == .selected,
      fmVarJSONPathResult.nodelist?.nodes.map(\.id.rawValue) == [
        "$['items'][0]['title']",
        "$['items'][1]['title']",
      ],
      fmVarJSONPathResult.nodelist?.nodes.map(\.sourceScalar?.content) == [
        "\"First\"", "\"Second\"",
      ]
    else {
      throw WasmCoreSmokeError.fmVarJSONPathMismatch
    }

    let resolvedIdentifier = try FMVarURIResolver().resolve(
      reference: "../data.yaml?revision=2",
      relativeTo: FMVarResourceIdentifier(rawValue: "https://example.test/docs/page.md")
    )
    guard resolvedIdentifier.rawValue == "https://example.test/data.yaml?revision=2" else {
      throw WasmCoreSmokeError.fmVarURIResolutionMismatch
    }

    let yamlProjection = FMVarYAMLProjector().project(yaml: """
      date: 2001-12-15
      enabled: true
      ratio: 1.2300
      published: 2026-09-05t08:07:06.120z
      """)
    guard let yamlRoot = yamlProjection.argument?.root,
      case .object(let yamlMembers) = yamlRoot.value,
      yamlMembers.first(where: { $0.name == "date" })?.node.value == .string("2001-12-15"),
      yamlMembers.first(where: { $0.name == "enabled" })?.node.value == .boolean(true),
      yamlMembers.first(where: { $0.name == "ratio" })?.node.sourceScalar?.content == "1.2300"
    else {
      throw WasmCoreSmokeError.fmVarYAMLProjectionMismatch
    }

    guard let ratioNode = yamlMembers.first(where: { $0.name == "ratio" })?.node,
      let publishedNode = yamlMembers.first(where: { $0.name == "published" })?.node,
      FMVarScalarCoercer().coerce(ratioNode, as: .number).scalar?.defaultSerialization == "1.2300",
      FMVarScalarCoercer().coerce(
        publishedNode,
        as: .timestamp
      ).scalar?.defaultSerialization == "2026-09-05T08:07:06.120Z"
    else {
      throw WasmCoreSmokeError.fmVarScalarCoercionMismatch
    }

    print("MarkdownUtilitiesCore WebAssembly smoke test passed")
  }
}
