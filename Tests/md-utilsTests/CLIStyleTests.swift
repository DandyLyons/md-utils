//
//  CLIStyleTests.swift
//  md-utilsTests
//

import Rainbow
import Testing

@testable import md_utils

@Suite("CLI style")
struct CLIStyleTests {
  @Test
  func `styling preserves underlying plain text`() {
    #expect(CLIStyle.metadata("metadata").raw == "metadata")
    #expect(CLIStyle.muted("muted").raw == "muted")
    #expect(CLIStyle.hint("hint").raw == "hint")
    #expect(CLIStyle.heading("heading").raw == "heading")
    #expect(CLIStyle.headingMarker("##", level: 2).raw == "##")
    #expect(CLIStyle.markdownHeading("## Heading", level: 2).raw == "## Heading")
    #expect(CLIStyle.exploreLabel("Frontmatter").raw == "Frontmatter")
    #expect(CLIStyle.path("path").raw == "path")
    #expect(CLIStyle.success("success").raw == "success")
    #expect(CLIStyle.error("error").raw == "error")
    #expect(CLIStyle.warning("warning").raw == "warning")
  }

  @Test
  func `markdown heading styling only changes leading marker`() {
    let styled = CLIStyle.markdownHeading("### A # Heading", level: 3)

    #expect(styled.raw == "### A # Heading")
  }
}
