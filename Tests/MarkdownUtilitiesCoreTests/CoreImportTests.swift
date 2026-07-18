import MarkdownUtilitiesCore
import Testing

@Suite("MarkdownUtilitiesCore public import")
struct CoreImportTests {
  @Test
  func `Core parses content without native context`() throws {
    let document = try MarkdownDocument(content: "# Linux-ready")

    #expect(document.body == "# Linux-ready")
  }
}
