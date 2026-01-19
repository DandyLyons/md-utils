import Foundation
import Testing

@testable import MarkdownUtilities

@Suite("FileMetadata Reader Tests")
struct FileMetadataReaderTests {

  @Test
  func `Read metadata from existing file`() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test-\(UUID()).md")
    let content = "# Test File\n\nThis is a test."

    // Create test file
    try content.write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    // Read metadata
    let reader = FileMetadataReader()
    let metadata = try reader.readMetadata(at: testFile.path, includeExtendedAttributes: false)

    // Verify basic properties
    #expect(metadata.path == testFile.path)
    #expect(metadata.size > 0)
    #expect(metadata.creationDate != nil)
    #expect(metadata.modificationDate != nil)
    #expect(!metadata.isDirectory)
  }

  @Test
  func `Read metadata with extended attributes`() async throws {
    #if canImport(Darwin)
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-\(UUID()).md")
      let content = "# Test File with xattr"

      // Create test file
      try content.write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Set extended attribute
      let xattrName = "com.test.attribute"
      let xattrValue = "test value"
      let xattrData = xattrValue.data(using: .utf8)!
      let result = xattrData.withUnsafeBytes { bytes in
        setxattr(
          testFile.path, xattrName, bytes.baseAddress, bytes.count, 0, 0)
      }
      #expect(result == 0, "Failed to set xattr")

      // First verify we can read xattr directly
      let directAttrs = try readExtendedAttributes(at: testFile.path)
      guard !directAttrs.isEmpty else {
        // Skip test if xattr isn't supported on this filesystem
        return
      }

      // Read metadata with extended attributes
      let reader = FileMetadataReader()
      let metadata = try reader.readMetadata(at: testFile.path, includeExtendedAttributes: true)

      // Verify extended attributes
      #expect(!metadata.extendedAttributes.isEmpty)
      #expect(metadata.extendedAttributes.keys.contains(xattrName))
      if let data = metadata.extendedAttributes[xattrName] {
        let value = String(data: data, encoding: .utf8)
        #expect(value == xattrValue)
      }
    #endif
  }

  @Test
  func `Error on nonexistent file`() async throws {
    let reader = FileMetadataReader()
    let nonexistentPath = "/tmp/nonexistent-\(UUID()).md"

    #expect(throws: FileMetadataError.self) {
      try reader.readMetadata(at: nonexistentPath, includeExtendedAttributes: false)
    }
  }

  @Test
  func `Validate date parsing`() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test-dates-\(UUID()).md")

    // Create test file
    try "Test".write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    // Read metadata
    let reader = FileMetadataReader()
    let metadata = try reader.readMetadata(at: testFile.path, includeExtendedAttributes: false)

    // Verify dates are parsed
    let creationDate = try #require(metadata.creationDate)
    let modificationDate = try #require(metadata.modificationDate)

    // Dates should be recent (within last minute)
    let now = Date()
    let interval = now.timeIntervalSince(creationDate)
    #expect(interval >= 0 && interval < 60, "Creation date should be recent")

    let modInterval = now.timeIntervalSince(modificationDate)
    #expect(modInterval >= 0 && modInterval < 60, "Modification date should be recent")
  }

  @Test
  func `Validate size calculation`() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test-size-\(UUID()).md")
    let content = "Hello World!"

    // Create test file with known content
    try content.write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    // Read metadata
    let reader = FileMetadataReader()
    let metadata = try reader.readMetadata(at: testFile.path, includeExtendedAttributes: false)

    // Verify size matches content
    let expectedSize = content.data(using: .utf8)!.count
    #expect(metadata.size == expectedSize)
  }

  @Test
  func `Validate permissions parsing`() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test-perms-\(UUID()).md")

    // Create test file
    try "Test".write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    // Set specific permissions (0644)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o644],
      ofItemAtPath: testFile.path
    )

    // Read metadata
    let reader = FileMetadataReader()
    let metadata = try reader.readMetadata(at: testFile.path, includeExtendedAttributes: false)

    // Verify permissions
    let perms = try #require(metadata.posixPermissions)
    #expect(perms == 0o644)

    // Verify permission string
    let permString = try #require(metadata.permissionString)
    #expect(permString == "rw-r--r--")
  }

  @Test
  func `Read directory metadata`() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testDir = tempDir.appendingPathComponent("test-dir-\(UUID())")

    // Create test directory
    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: testDir) }

    // Read metadata
    let reader = FileMetadataReader()
    let metadata = try reader.readMetadata(at: testDir.path, includeExtendedAttributes: false)

    // Verify it's recognized as directory
    #expect(metadata.isDirectory)
    #expect(!metadata.isSymbolicLink)
  }

  @Test
  func `Exclude extended attributes when requested`() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test-no-xattr-\(UUID()).md")

    // Create test file
    try "Test".write(to: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: testFile) }

    // Read metadata without extended attributes
    let reader = FileMetadataReader()
    let metadata = try reader.readMetadata(at: testFile.path, includeExtendedAttributes: false)

    // Verify extended attributes are empty
    #expect(metadata.extendedAttributes.isEmpty)
  }
}
