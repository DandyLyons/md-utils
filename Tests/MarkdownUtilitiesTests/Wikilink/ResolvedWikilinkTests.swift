//
//  ResolvedWikilinkTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import Foundation
import PathKit
@testable import MarkdownUtilities

@Suite("ResolvedWikilink Tests")
struct ResolvedWikilinkTests {

  // MARK: - Status Formatting

  @Test
  func `Resolved status is set correctly`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page]]",
      target: "Page",
      displayText: nil,
      anchor: nil,
      isEmbed: false
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .resolved(Path("/vault/Page.md"))
    )

    #expect(resolved.status == "resolved")
    #expect(resolved.resolvedPath == "/vault/Page.md")
    #expect(resolved.candidates == nil)
  }

  @Test
  func `Unresolved status is set correctly`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Missing]]",
      target: "Missing",
      displayText: nil,
      anchor: nil,
      isEmbed: false
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .unresolved
    )

    #expect(resolved.status == "unresolved")
    #expect(resolved.resolvedPath == nil)
    #expect(resolved.candidates == nil)
  }

  @Test
  func `Ambiguous status is set correctly`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page]]",
      target: "Page",
      displayText: nil,
      anchor: nil,
      isEmbed: false
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .ambiguous([Path("/vault/a/Page.md"), Path("/vault/b/Page.md")])
    )

    #expect(resolved.status == "ambiguous")
    #expect(resolved.resolvedPath == nil)
    let candidates = try #require(resolved.candidates)
    #expect(candidates.count == 2)
  }

  // MARK: - Anchor Formatting

  @Test
  func `Heading anchor formats correctly`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page#Intro]]",
      target: "Page",
      displayText: nil,
      anchor: .heading("Intro"),
      isEmbed: false
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .unresolved
    )

    #expect(resolved.anchor == "#Intro")
  }

  @Test
  func `Block ID anchor formats correctly`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page#^abc]]",
      target: "Page",
      displayText: nil,
      anchor: .blockID("abc"),
      isEmbed: false
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .unresolved
    )

    #expect(resolved.anchor == "#^abc")
  }

  @Test
  func `No anchor produces nil`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page]]",
      target: "Page",
      displayText: nil,
      anchor: nil,
      isEmbed: false
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .unresolved
    )

    #expect(resolved.anchor == nil)
  }

  // MARK: - Properties Passthrough

  @Test
  func `Display text and embed flag pass through`() async throws {
    let wikilink = Wikilink(
      rawValue: "![[Image.png|300]]",
      target: "Image.png",
      displayText: "300",
      anchor: nil,
      isEmbed: true
    )
    let resolved = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .resolved(Path("/vault/Image.png"))
    )

    #expect(resolved.target == "Image.png")
    #expect(resolved.displayText == "300")
    #expect(resolved.isEmbed == true)
  }

  // MARK: - Codable Round-Trip

  @Test
  func `Codable round-trip preserves all fields`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page#Intro|Display]]",
      target: "Page",
      displayText: "Display",
      anchor: .heading("Intro"),
      isEmbed: false
    )
    let original = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .resolved(Path("/vault/Page.md"))
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(ResolvedWikilink.self, from: data)

    #expect(decoded == original)
  }

  @Test
  func `Codable round-trip for ambiguous result`() async throws {
    let wikilink = Wikilink(
      rawValue: "[[Page]]",
      target: "Page",
      displayText: nil,
      anchor: nil,
      isEmbed: false
    )
    let original = ResolvedWikilink(
      wikilink: wikilink,
      resolution: .ambiguous([Path("/vault/a/Page.md"), Path("/vault/b/Page.md")])
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(ResolvedWikilink.self, from: data)

    #expect(decoded == original)
  }
}
