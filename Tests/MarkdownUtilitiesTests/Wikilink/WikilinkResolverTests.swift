//
//  WikilinkResolverTests.swift
//  MarkdownUtilitiesTests
//

import Testing
import Foundation
import PathKit
@testable import MarkdownUtilities

@Suite("WikilinkResolver Tests")
struct WikilinkResolverTests {

  /// Creates a temporary vault directory with the given file structure.
  /// Keys are relative paths, values are file contents.
  private func createVault(_ files: [String: String]) throws -> Path {
    let vault = Path(NSTemporaryDirectory()) + "test-vault-\(UUID().uuidString)"
    try vault.mkpath()

    for (relativePath, content) in files {
      let filePath = vault + relativePath
      try filePath.parent().mkpath()
      try filePath.write(content)
    }

    return vault
  }

  // MARK: - Initialization

  @Test
  func `Resolver initializes with valid root`() async throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    #expect(resolver.root == vault.absolute())
  }

  @Test
  func `Resolver throws for nonexistent root`() async throws {
    let bogus = Path(NSTemporaryDirectory()) + "nonexistent-\(UUID().uuidString)"

    #expect(throws: WikilinkResolverError.self) {
      _ = try WikilinkResolver(root: bogus)
    }
  }

  @Test
  func `Resolver throws for file root`() async throws {
    let vault = try createVault(["page.md": "# Page"])
    defer { try? vault.delete() }

    let filePath = vault + "page.md"
    #expect(throws: WikilinkResolverError.self) {
      _ = try WikilinkResolver(root: filePath)
    }
  }

  // MARK: - Filename Match

  @Test
  func `Resolves simple filename match`() async throws {
    let vault = try createVault([
      "notes/MyPage.md": "# My Page",
      "source.md": "See [[MyPage]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "MyPage", from: vault + "source.md")

    #expect(result == .resolved((vault + "notes/MyPage.md").absolute()))
  }

  @Test
  func `Resolves case-insensitive filename match`() async throws {
    let vault = try createVault([
      "MyPage.md": "# My Page",
      "source.md": "See [[mypage]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "mypage", from: vault + "source.md")

    #expect(result == .resolved((vault + "MyPage.md").absolute()))
  }

  @Test
  func `No-extension target only matches markdown files`() async throws {
    let vault = try createVault([
      "notes.txt": "text file",
      "notes.md": "# Notes",
      "source.md": "See [[notes]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "notes", from: vault + "source.md")

    #expect(result == .resolved((vault + "notes.md").absolute()))
  }

  @Test
  func `Explicit extension matches exactly`() async throws {
    let vault = try createVault([
      "image.png": "binary",
      "image.md": "# Image page",
      "source.md": "![[image.png]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "image.png", from: vault + "source.md")

    #expect(result == .resolved((vault + "image.png").absolute()))
  }

  // MARK: - Ambiguity

  @Test
  func `Detects ambiguous matches`() async throws {
    let vault = try createVault([
      "folder1/Page.md": "# Page 1",
      "folder2/Page.md": "# Page 2",
      "source.md": "See [[Page]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "Page", from: vault + "source.md")

    if case .ambiguous(let paths) = result {
      #expect(paths.count == 2)
    } else {
      Issue.record("Expected ambiguous result, got \(result)")
    }
  }

  // MARK: - Relative Path

  @Test
  func `Resolves relative path from source directory`() async throws {
    let vault = try createVault([
      "notes/sub/Target.md": "# Target",
      "notes/source.md": "See [[sub/Target]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "sub/Target", from: vault + "notes/source.md")

    #expect(result == .resolved((vault + "notes/sub/Target.md").absolute()))
  }

  // MARK: - Absolute Path (from root)

  @Test
  func `Resolves absolute path from root`() async throws {
    let vault = try createVault([
      "deep/nested/Page.md": "# Page",
      "other/source.md": "See [[deep/nested/Page]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "deep/nested/Page", from: vault + "other/source.md")

    #expect(result == .resolved((vault + "deep/nested/Page.md").absolute()))
  }

  // MARK: - Empty Target (Self-Reference)

  @Test
  func `Empty target resolves to source file`() async throws {
    let vault = try createVault([
      "source.md": "See [[#heading]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let sourceFile = vault + "source.md"
    let result = resolver.resolve(target: "", from: sourceFile)

    #expect(result == .resolved(sourceFile.absolute()))
  }

  // MARK: - Unresolved

  @Test
  func `Returns unresolved for missing target`() async throws {
    let vault = try createVault([
      "source.md": "See [[NonExistent]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "NonExistent", from: vault + "source.md")

    #expect(result == .unresolved)
  }

  // MARK: - Hidden Files

  @Test
  func `Hidden files are excluded from index`() async throws {
    let vault = try createVault([
      ".hidden/secret.md": "# Secret",
      "source.md": "See [[secret]]",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(target: "secret", from: vault + "source.md")

    #expect(result == .unresolved)
  }

  // MARK: - Markdown Files List

  @Test
  func `markdownFiles contains only md and markdown files`() async throws {
    let vault = try createVault([
      "page.md": "# Page",
      "doc.markdown": "# Doc",
      "image.png": "binary",
      "data.json": "{}",
    ])
    defer { try? vault.delete() }

    let resolver = try WikilinkResolver(root: vault)
    #expect(resolver.markdownFiles.count == 2)
  }

  // MARK: - Wikilink Struct Resolution

  @Test
  func `Resolves Wikilink struct`() async throws {
    let vault = try createVault([
      "Target.md": "# Target",
      "source.md": "[[Target]]",
    ])
    defer { try? vault.delete() }

    let wikilink = Wikilink(
      rawValue: "[[Target]]",
      target: "Target",
      displayText: nil,
      anchor: nil,
      isEmbed: false
    )

    let resolver = try WikilinkResolver(root: vault)
    let result = resolver.resolve(wikilink, from: vault + "source.md")

    #expect(result == .resolved((vault + "Target.md").absolute()))
  }
}
