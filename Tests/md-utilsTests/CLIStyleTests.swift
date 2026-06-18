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
    #expect(CLIStyle.heading("heading").raw == "heading")
    #expect(CLIStyle.path("path").raw == "path")
    #expect(CLIStyle.success("success").raw == "success")
    #expect(CLIStyle.error("error").raw == "error")
    #expect(CLIStyle.warning("warning").raw == "warning")
  }
}
