import Foundation
import MarkdownUtilitiesCore
import PathKit
import Testing
@testable import MarkdownUtilities

struct WikilinkConversionTests {
  @Test(arguments: [WikilinkTargetStyle.path, .name], [WikilinkMarkdownExtension.auto, .include, .omit])
  func `extension policy preserves actual Markdown and attachment suffixes`(
    style: WikilinkTargetStyle,
    policy: WikilinkMarkdownExtension,
  ) throws {
    let root = try vault(["People/Alice.md", "People/Bob.markdown", "People/Notes.txt", "People/image.png", "source.md"])
    defer { try? root.delete() }
    let plan = try WikilinkConversion.plan(
      source: "[[People/Alice.md#Heading|A]] [[People/Bob.markdown]] [[People/Notes.txt]] ![[People/image.png]]",
      file: root + "source.md", resolver: WikilinkResolver(root: root), style: style, markdownExtension: policy,
    )
    let prefix = style == .path ? "People/" : ""
    let omit = policy == .omit || (policy == .auto && style == .name)
    #expect(plan.proposed == "[[\(prefix)Alice\(omit ? "" : ".md")#Heading|A]] [[\(prefix)Bob\(omit ? "" : ".markdown")]] [[\(prefix)Notes.txt]] ![[\(prefix)image.png]]")
  }

  @Test(arguments: [WikilinkTargetStyle.path, .name])
  func `omission that introduces extension ambiguity preserves original`(style: WikilinkTargetStyle) throws {
    let root = try vault(["People/Alice.md", "People/Alice.markdown", "source.md"])
    defer { try? root.delete() }
    let plan = try WikilinkConversion.plan(
      source: "[[People/Alice.md]]", file: root + "source.md",
      resolver: WikilinkResolver(root: root), style: style, markdownExtension: .omit,
    )
    #expect(plan.hasChanges == false)
    #expect(plan.changes.first?.diagnostic != nil)
  }

  private func vault(_ names: [String]) throws -> Path {
    let root = Path(#filePath).parent().parent().parent().parent() + "tmp/links-\(UUID().uuidString)"
    try root.mkpath()
    for name in names {
      let file = root + name
      try file.parent().mkpath()
      try file.write("")
    }
    return root
  }

  @Test
  func `explicit paths never fall back to basename matching`() throws {
    let root = try vault(["People/Alice.md", "Other/Alice.md", "notes/source.md"])
    defer { try? root.delete() }
    let resolver = try WikilinkResolver(root: root)
    #expect(resolver.resolve(target: "People/Alice.md", from: root + "notes/source.md") == .resolved(root + "People/Alice.md"))
    #expect(resolver.resolve(target: "Missing/Alice.md", from: root + "notes/source.md") == .unresolved)
    #expect(resolver.resolve(target: "../Other/Alice.md", from: root + "notes/source.md") == .resolved(root + "Other/Alice.md"))
  }

  @Test
  func `preserves suffix bytes embeds unicode spaces and repeated occurrences`() throws {
    let root = try vault(["People/Álice Smith.md", "Assets/image.png", "source.md"])
    defer { try? root.delete() }
    let source = "[[Álice Smith#Early Life|A\\|B]] ![[image.png#^block|image]] [[Álice Smith]] [[#Local]]"
    let plan = try WikilinkConversion.plan(
      source: source, file: root + "source.md", resolver: WikilinkResolver(root: root), style: .path,
    )
    #expect(plan.proposed == "[[People/Álice Smith.md#Early Life|A\\|B]] ![[Assets/image.png#^block|image]] [[People/Álice Smith.md]] [[#Local]]")
    #expect(plan.changes.count == 3)
    let reverse = try WikilinkConversion.plan(
      source: plan.proposed, file: root + "source.md", resolver: WikilinkResolver(root: root), style: .name,
    )
    #expect(reverse.proposed == source)
  }

  @Test
  func `duplicates missing names root collisions and shadowed paths are skipped`() throws {
    let root = try vault([
      "Alice.md", "People/Alice.md", "Only.md", "notes/source.md",
      "People/Bob.md", "notes/People/Bob.md",
    ])
    defer { try? root.delete() }
    let resolver = try WikilinkResolver(root: root)
    let source = "[[../Alice.md]] [[Alice]] [[Missing]] [[Only]] [[../People/Bob.md]]"
    let plan = try WikilinkConversion.plan(source: source, file: root + "notes/source.md", resolver: resolver, style: .path)
    #expect(plan.proposed == "[[../Alice.md]] [[Alice]] [[Missing]] [[Only.md]] [[../People/Bob.md]]")
    #expect(plan.changes.filter { $0.diagnostic != nil }.count == 4)
    let names = try WikilinkConversion.plan(source: "[[People/Alice.md]]", file: root + "source.md", resolver: resolver, style: .name)
    #expect(names.hasChanges == false)
    #expect(names.changes.first?.diagnostic != nil)
  }

  @Test(arguments: ["yaml", "toml"])
  func `frontmatter keys arrays and body selection preserve unrelated values`(format: String) throws {
    let root = try vault(["People/Alice.md", "source.md"])
    defer { try? root.delete() }
    let source = format == "yaml"
      ? "---\n# comment\nrelated: ['[[Alice]]', '']\nother: '[[Alice]]'\nnullValue: null\n---\nBody [[Alice]]\n"
      : "+++\n# comment\nrelated = ['[[Alice]]', '']\nother = '[[Alice]]'\n+++\nBody [[Alice]]\n"
    let resolver = try WikilinkResolver(root: root)
    let plan = try WikilinkConversion.plan(
      source: source, file: root + "source.md", resolver: resolver, style: .path, scope: .frontmatter, keys: ["related"],
    )
    let result = try MarkdownDocument(content: plan.proposed)
    #expect(result.frontMatter["related"] == .array([.string("[[People/Alice.md]]"), .string("")]))
    #expect(result.frontMatter["other"] == .string("[[Alice]]"))
    #expect(result.body == "Body [[Alice]]\n")
    if format == "yaml" { #expect(result.frontMatter["nullValue"] == .null) }
    let bodyPlan = try WikilinkConversion.plan(
      source: source, file: root + "source.md", resolver: resolver, style: .path, scope: .body,
    )
    #expect(bodyPlan.proposed == source.replacingOccurrences(of: "Body [[Alice]]", with: "Body [[People/Alice.md]]"))
  }

  @Test
  func `stale source prevents application`() throws {
    let root = try vault(["People/Alice.md", "source.md"])
    defer { try? root.delete() }
    let file = root + "source.md"
    try file.write("[[Alice]]")
    let plan = try WikilinkConversion.plan(source: "[[Alice]]", file: file, resolver: WikilinkResolver(root: root), style: .path)
    try file.write("external edit")
    #expect(throws: FrontMatterFileWriteError.self) {
      try FrontMatterFileWriter.write(plan.proposed, to: file, expectedSource: plan.source)
    }
    #expect(try file.read() as String == "external edit")
  }

  @Test
  func `symlinks and outside traversal are not resolution candidates`() throws {
    let root = try vault(["People/Alice.md", "source.md"])
    defer { try? root.delete() }
    try FileManager.default.createSymbolicLink(atPath: (root + "loop").string, withDestinationPath: root.string)
    let resolver = try WikilinkResolver(root: root)
    #expect(resolver.allFiles.count == 2)
    #expect(resolver.resolve(target: "loop/People/Alice.md", from: root + "source.md") == .unresolved)
    #expect(resolver.resolve(target: "../outside.md", from: root + "source.md") == .unresolved)
  }

  @Test
  func `extensionless explicit paths reject multiple Markdown extensions`() throws {
    let root = try vault(["People/Alice.md", "People/Alice.markdown", "source.md"])
    defer { try? root.delete() }
    let resolver = try WikilinkResolver(root: root)
    guard case .ambiguous(let paths) = resolver.resolve(target: "People/Alice", from: root + "source.md") else {
      Issue.record("Expected both Markdown extensions to be ambiguous")
      return
    }
    #expect(paths.count == 2)
  }

  @Test
  func `escaped target pipes and malformed surrounding text retain exact suffixes`() throws {
    let root = try vault(["People/A|B.md", "source.md"])
    defer { try? root.delete() }
    let source = "[[broken [[A\\|B#Heading\\|suffix|label\\|alias]] [[A\\|B]] trailing [["
    let plan = try WikilinkConversion.plan(
      source: source, file: root + "source.md", resolver: WikilinkResolver(root: root), style: .path,
    )
    #expect(plan.proposed == "[[broken [[People/A\\|B.md#Heading\\|suffix|label\\|alias]] [[People/A\\|B.md]] trailing [[")
  }

  @Test
  func `revision comparison detects canonically equivalent byte changes`() throws {
    let root = try vault(["source.md"])
    defer { try? root.delete() }
    let file = root + "source.md"
    let original = "caf\u{00E9}"
    let changed = "cafe\u{0301}"
    #expect(original == changed)
    try file.write(changed)
    #expect(throws: FrontMatterFileWriteError.self) {
      try FrontMatterFileWriter.write("replacement", to: file, expectedSource: original)
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: file.string)) == Data(changed.utf8))
  }
}
