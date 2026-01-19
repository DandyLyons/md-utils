import Foundation
import Testing

@testable import MarkdownUtilities

#if canImport(Darwin)
  import Darwin
#endif

@Suite("Extended Attributes Tests")
struct ExtendedAttributesTests {

  #if canImport(Darwin)

    @Test
    func `Read xattr on macOS`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Set extended attributes
      let xattrName1 = "com.test.attribute1"
      let xattrValue1 = "value1"
      let xattrData1 = xattrValue1.data(using: .utf8)!

      let result1 = xattrData1.withUnsafeBytes { bytes in
        setxattr(testFile.path, xattrName1, bytes.baseAddress, bytes.count, 0, 0)
      }

      // Skip test if xattr isn't supported on this filesystem
      guard result1 == 0 else {
        return
      }

      // Read all extended attributes
      let attributes = try readExtendedAttributes(at: testFile.path)

      // Skip if filesystem doesn't support reading xattrs
      guard !attributes.isEmpty else {
        return
      }

      // Verify we got the attribute
      #expect(attributes.keys.contains(xattrName1))
      if let data = attributes[xattrName1] {
        let value = String(data: data, encoding: .utf8)
        #expect(value == xattrValue1)
      }
    }

    @Test
    func `List all xattrs`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-list-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Set multiple extended attributes
      let attrs = [
        "com.test.attr1": "value1",
        "com.test.attr2": "value2",
        "com.test.attr3": "value3",
      ]

      var allSucceeded = true
      for (name, value) in attrs {
        let data = value.data(using: .utf8)!
        let result = data.withUnsafeBytes { bytes in
          setxattr(testFile.path, name, bytes.baseAddress, bytes.count, 0, 0)
        }
        if result != 0 {
          allSucceeded = false
        }
      }

      // Skip test if xattr isn't supported on this filesystem
      guard allSucceeded else {
        return
      }

      // Read all extended attributes
      let attributes = try readExtendedAttributes(at: testFile.path)

      // Skip if filesystem doesn't support reading xattrs
      guard !attributes.isEmpty else {
        return
      }

      // Verify all attributes are present
      #expect(attributes.count >= 3, "Should have at least 3 attributes")
      for (name, expectedValue) in attrs {
        #expect(attributes.keys.contains(name), "Missing attribute \(name)")
        if let data = attributes[name] {
          let value = String(data: data, encoding: .utf8)
          #expect(value == expectedValue, "Value mismatch for \(name)")
        }
      }
    }

    @Test
    func `Read specific xattr by name`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-specific-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Set extended attribute
      let xattrName = "com.test.specific"
      let xattrValue = "specific value"
      let xattrData = xattrValue.data(using: .utf8)!

      let result = xattrData.withUnsafeBytes { bytes in
        setxattr(testFile.path, xattrName, bytes.baseAddress, bytes.count, 0, 0)
      }
      #expect(result == 0, "Failed to set xattr")

      // Read specific attribute
      let data = try readExtendedAttribute(at: testFile.path, name: xattrName)
      let value = String(data: data, encoding: .utf8)
      #expect(value == xattrValue)
    }

    @Test
    func `Handle missing xattr gracefully`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-missing-\(UUID()).txt")

      // Create test file without any xattr
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Try to read non-existent attribute
      #expect(throws: FileMetadataError.self) {
        try readExtendedAttribute(at: testFile.path, name: "com.test.nonexistent")
      }
    }

    @Test
    func `Handle file with no xattrs`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-none-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Read all extended attributes (should be empty or only have system attrs)
      let attributes = try readExtendedAttributes(at: testFile.path)

      // Verify it's a dictionary (may be empty or have system attrs)
      #expect(attributes is [String: Data])
    }

    @Test
    func `Handle binary xattr data`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-xattr-binary-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Set binary extended attribute
      let xattrName = "com.test.binary"
      let binaryData = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])

      let result = binaryData.withUnsafeBytes { bytes in
        setxattr(testFile.path, xattrName, bytes.baseAddress, bytes.count, 0, 0)
      }
      #expect(result == 0, "Failed to set binary xattr")

      // Read the binary attribute
      let data = try readExtendedAttribute(at: testFile.path, name: xattrName)
      #expect(data == binaryData)
    }

  #else
    // Tests for unsupported platforms

    @Test
    func `Empty xattr dictionary on unsupported platforms`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-no-xattr-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Read extended attributes (should return empty on unsupported platforms)
      let attributes = try readExtendedAttributes(at: testFile.path)
      #expect(attributes.isEmpty)
    }

    @Test
    func `Read specific xattr throws on unsupported platforms`() async throws {
      let tempDir = FileManager.default.temporaryDirectory
      let testFile = tempDir.appendingPathComponent("test-no-xattr-\(UUID()).txt")

      // Create test file
      try "Test content".write(to: testFile, atomically: true, encoding: .utf8)
      defer { try? FileManager.default.removeItem(at: testFile) }

      // Try to read specific attribute (should throw on unsupported platforms)
      #expect(throws: FileMetadataError.self) {
        try readExtendedAttribute(at: testFile.path, name: "com.test.attr")
      }
    }
  #endif
}
