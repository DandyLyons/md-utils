//
//  GlobalOptionsTests.swift
//  md-utilsTests
//

import Testing
import Foundation
import PathKit
@testable import md_utils

@Suite("GlobalOptions path resolution and sorting")
struct GlobalOptionsTests {

  // MARK: - Helper Methods

  /// Create a properly initialized GlobalOptions instance
  private func createGlobalOptions(
    paths: [Path] = [],
    recursive: Bool = true,
    includeHidden: Bool = false,
    extensions: String = "md,markdown",
    noSort: Bool = false
  ) -> GlobalOptions {
    var options = GlobalOptions()
    options.paths = paths
    options.recursive = recursive
    options.includeHidden = includeHidden
    options.extensions = extensions
    options.noSort = noSort
    return options
  }

  @Test
  func `resolvedPaths returns files in alphabetical order by default`() async throws {
    // Create temporary directory structure
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create files in non-alphabetical order
    let file1 = tempDir + "zebra.md"
    let file2 = tempDir + "alpha.md"
    let file3 = tempDir + "middle.md"

    try file1.write("---\ntitle: Zebra\n---")
    try file2.write("---\ntitle: Alpha\n---")
    try file3.write("---\ntitle: Middle\n---")

    // Create GlobalOptions with the temp directory
    let options = createGlobalOptions(paths: [tempDir])

    // Resolve paths
    let resolved = try options.resolvedPaths()

    // Verify alphabetical order
    #expect(resolved.count == 3)
    #expect(resolved[0].lastComponent == "alpha.md")
    #expect(resolved[1].lastComponent == "middle.md")
    #expect(resolved[2].lastComponent == "zebra.md")
  }

  @Test
  func `resolvedPaths sorts by full path including directory structure`() async throws {
    // Create nested directory structure
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let dirA = tempDir + "a"
    let dirB = tempDir + "b"
    try dirA.mkpath()
    try dirB.mkpath()

    // Create files: a/z.md should come before b/a.md when sorted by full path
    let fileAZ = dirA + "z.md"
    let fileBA = dirB + "a.md"
    let fileRoot = tempDir + "m.md"

    try fileAZ.write("---\ntitle: AZ\n---")
    try fileBA.write("---\ntitle: BA\n---")
    try fileRoot.write("---\ntitle: Root\n---")

    let options = createGlobalOptions(paths: [tempDir])

    let resolved = try options.resolvedPaths()

    // Expected order: a/z.md, b/a.md, m.md (alphabetical by full path)
    #expect(resolved.count == 3)

    // Verify the paths end with expected components
    let path0 = resolved[0].string
    let path1 = resolved[1].string
    let path2 = resolved[2].string

    #expect(path0.hasSuffix("a/z.md"))
    #expect(path1.hasSuffix("b/a.md"))
    #expect(path2.hasSuffix("m.md"))
  }

  @Test
  func `no-sort flag preserves filesystem traversal order`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create files
    let file1 = tempDir + "zebra.md"
    let file2 = tempDir + "alpha.md"
    let file3 = tempDir + "middle.md"

    try file1.write("---\ntitle: Zebra\n---")
    try file2.write("---\ntitle: Alpha\n---")
    try file3.write("---\ntitle: Middle\n---")

    let options = createGlobalOptions(paths: [tempDir], noSort: true)

    let resolved = try options.resolvedPaths()

    // Should have all files, but order is not guaranteed to be alphabetical
    #expect(resolved.count == 3)

    // Verify all files are present (regardless of order)
    let fileNames = Set(resolved.map { $0.lastComponent })
    #expect(fileNames.contains("alpha.md"))
    #expect(fileNames.contains("middle.md"))
    #expect(fileNames.contains("zebra.md"))
  }

  @Test
  func `resolvedPaths handles mixed files and directories`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let subDir = tempDir + "subdir"
    try subDir.mkpath()

    // Create files both in root and subdirectory
    let rootFile = tempDir + "root.md"
    let subFile = subDir + "sub.md"

    try rootFile.write("---\ntitle: Root\n---")
    try subFile.write("---\ntitle: Sub\n---")

    // Pass both specific file and directory
    let options = createGlobalOptions(paths: [rootFile, subDir])

    let resolved = try options.resolvedPaths()

    // Should contain both files, sorted alphabetically
    #expect(resolved.count == 2)

    // First should be root.md, second should be subdir/sub.md
    // (when sorted by full path, "root.md" comes before "subdir/sub.md")
    #expect(resolved[0].string.hasSuffix("root.md"))
    #expect(resolved[1].string.hasSuffix("subdir/sub.md"))
  }

  @Test
  func `resolvedPaths returns empty array when no matching files`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create directory with only non-markdown files
    let txtFile = tempDir + "file.txt"
    try txtFile.write("Not markdown")

    let options = createGlobalOptions(paths: [tempDir])

    let resolved = try options.resolvedPaths()

    // Should be empty since no .md or .markdown files exist
    #expect(resolved.isEmpty)
  }

  @Test
  func `resolvedPaths filters by extension`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    // Create files with different extensions
    let mdFile = tempDir + "file.md"
    let markdownFile = tempDir + "file.markdown"
    let txtFile = tempDir + "file.txt"

    try mdFile.write("---\ntitle: MD\n---")
    try markdownFile.write("---\ntitle: Markdown\n---")
    try txtFile.write("Not markdown")

    // Default extensions are "md,markdown"
    let options = createGlobalOptions(paths: [tempDir])

    let resolved = try options.resolvedPaths()

    // Should only include .md and .markdown files
    #expect(resolved.count == 2)

    let extensions = Set(resolved.compactMap { $0.extension })
    #expect(extensions.contains("md"))
    #expect(extensions.contains("markdown"))
  }

  @Test
  func `resolvedPaths respects recursive flag`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let subDir = tempDir + "subdir"
    try subDir.mkpath()

    let rootFile = tempDir + "root.md"
    let subFile = subDir + "sub.md"

    try rootFile.write("---\ntitle: Root\n---")
    try subFile.write("---\ntitle: Sub\n---")

    // Test with recursive = false
    let nonRecursiveOptions = createGlobalOptions(paths: [tempDir], recursive: false)
    let nonRecursive = try nonRecursiveOptions.resolvedPaths()

    // Should only find root.md (not sub.md in subdirectory)
    #expect(nonRecursive.count == 1)
    #expect(nonRecursive[0].lastComponent == "root.md")

    // Test with recursive = true (default)
    let recursiveOptions = createGlobalOptions(paths: [tempDir], recursive: true)
    let recursive = try recursiveOptions.resolvedPaths()

    // Should find both files
    #expect(recursive.count == 2)
  }

  @Test
  func `resolvedPaths respects includeHidden flag`() async throws {
    let tempDir = Path(NSTemporaryDirectory()) + "md-utils-test-\(UUID().uuidString)"
    try tempDir.mkpath()
    defer { try? tempDir.delete() }

    let normalFile = tempDir + "normal.md"
    let hiddenFile = tempDir + ".hidden.md"

    try normalFile.write("---\ntitle: Normal\n---")
    try hiddenFile.write("---\ntitle: Hidden\n---")

    // Test with includeHidden = false (default)
    let withoutHiddenOptions = createGlobalOptions(paths: [tempDir], includeHidden: false)
    let withoutHidden = try withoutHiddenOptions.resolvedPaths()

    // Should only find normal.md
    #expect(withoutHidden.count == 1)
    #expect(withoutHidden[0].lastComponent == "normal.md")

    // Test with includeHidden = true
    let withHiddenOptions = createGlobalOptions(paths: [tempDir], includeHidden: true)
    let withHidden = try withHiddenOptions.resolvedPaths()

    // Should find both files
    #expect(withHidden.count == 2)

    let fileNames = Set(withHidden.map { $0.lastComponent })
    #expect(fileNames.contains("normal.md"))
    #expect(fileNames.contains(".hidden.md"))
  }
}
