import MarkdownUtilitiesCore
import MarkdownUtilitiesTemplates
import Testing

@Suite("Knap integration")
struct KnapIntegrationTests {
  @Test
  func `warnings retain filter code and location without failing rendering`() async throws {
    let result = try await MarkdownTemplateRenderer().render(
      template: "{{ data | date:\"YYYY\" }}", input: .init(data: .string("not-a-date")),
    )
    let warning = try #require(result.warnings.first)
    #expect(warning.code == "template.knap.INVALID_FILTER_INPUT")
    #expect(warning.constraintID == "date")
    #expect(warning.location == "template:1:11")
    #expect(warning.severity == .advisory)
  }

  @Test
  func `execution budgets reject work with structured diagnostics`() async throws {
    do {
      _ = try await MarkdownTemplateRenderer(renderLimits: .init(maxOperations: 1)).render(
        template: "{% for item in data %}{{ item }}{% endfor %}",
        input: .init(data: .array([.integer(1), .integer(2), .integer(3)])),
      )
      Issue.record("Expected limit failure")
    } catch let error as MarkdownTemplateError {
      #expect(error.stage == .template)
      #expect(error.diagnostics.contains { $0.code == "template.knap.LIMIT_EXCEEDED" })
    }
  }

  @Test
  func `concurrent renders keep variables isolated`() async throws {
    try await withThrowingTaskGroup(of: String.self) { group in
      for number in 0..<12 {
        group.addTask {
          try await MarkdownTemplateRenderer().render(
            template: "{{ data | h2 }}", input: .init(data: .string(String(number))),
          ).source
        }
      }
      var outputs: Set<String> = []
      for try await output in group { outputs.insert(output) }
      #expect(outputs == Set((0..<12).map { "## \($0)" }))
    }
  }

  @Test
  func `Markdown filters render typed collections without custom helpers`() async throws {
    let rendered = try await MarkdownTemplateRenderer().render(
      template: "{{ frontmatter.title | h2 }}\n{{ data.tags | bold | join:\", \" }}",
      input: .init(
        frontmatter: ["title": .string("Report")],
        data: .object(["tags": .array([.string("one"), .string("two")])]),
      ),
    )
    #expect(rendered.document.body == "## Report\n**one**, **two**")
  }

  @Test
  func `Knap fallback uses upstream truthiness`() async throws {
    let rendered = try await MarkdownTemplateRenderer().render(
      template: "{{ data.items ?? \"empty\" }}|{{ data.value ?? \"null\" }}",
      input: .init(data: .object(["items": .array([]), "value": .null])),
    )
    #expect(rendered.source == "empty|null")
  }

  @Test
  func `integer input cannot silently lose precision`() async throws {
    do {
      _ = try await MarkdownTemplateRenderer().render(
        template: "{{ data }}", input: .init(data: .integer(9_007_199_254_740_993)),
      )
      Issue.record("Expected a lossless input conversion failure")
    } catch let error as MarkdownTemplateError {
      #expect(error.stage == .input)
      #expect(error.message.contains("string"))
    }
  }
}
