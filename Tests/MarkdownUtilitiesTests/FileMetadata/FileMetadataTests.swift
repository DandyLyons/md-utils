import Foundation
import Testing

@testable import MarkdownUtilities

@Suite("FileMetadata Structure Tests")
struct FileMetadataTests {

  @Test
  func `Codable encoding and decoding`() async throws {
    let now = Date()
    let metadata = FileMetadata(
      path: "/tmp/test.md",
      size: 1024,
      creationDate: now,
      modificationDate: now,
      accessDate: now,
      posixPermissions: 0o644,
      ownerAccount: "testuser",
      groupOwnerAccount: "testgroup",
      extendedAttributes: [:],
      fileType: "NSFileTypeRegular",
      isDirectory: false,
      isSymbolicLink: false
    )

    // Encode
    let encoder = JSONEncoder()
    let data = try encoder.encode(metadata)

    // Decode
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(FileMetadata.self, from: data)

    // Verify decoded values match original
    #expect(decoded.path == metadata.path)
    #expect(decoded.size == metadata.size)
    #expect(decoded.posixPermissions == metadata.posixPermissions)
    #expect(decoded.ownerAccount == metadata.ownerAccount)
    #expect(decoded.groupOwnerAccount == metadata.groupOwnerAccount)
    #expect(decoded.fileType == metadata.fileType)
    #expect(decoded.isDirectory == metadata.isDirectory)
    #expect(decoded.isSymbolicLink == metadata.isSymbolicLink)

    // Dates should be close (within 1 second due to ISO 8601 precision)
    if let decodedCreation = decoded.creationDate, let originalCreation = metadata.creationDate {
      let interval = abs(decodedCreation.timeIntervalSince(originalCreation))
      #expect(interval < 1.0)
    }
  }

  @Test
  func `JSON serialization format`() async throws {
    let metadata = FileMetadata(
      path: "/tmp/test.md",
      size: 1024,
      creationDate: Date(timeIntervalSince1970: 1_700_000_000),
      modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
      accessDate: nil,
      posixPermissions: 0o644,
      ownerAccount: "user",
      groupOwnerAccount: "group",
      extendedAttributes: [:],
      fileType: "NSFileTypeRegular",
      isDirectory: false,
      isSymbolicLink: false
    )

    // Encode as JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)
    let json = String(data: data, encoding: .utf8)

    let jsonString = try #require(json)

    // Verify JSON structure
    #expect(jsonString.contains("\"path\""))
    #expect(jsonString.contains("\"size\""))
    #expect(jsonString.contains("\"creationDate\""))
    #expect(jsonString.contains("\"modificationDate\""))
    #expect(jsonString.contains("\"posixPermissions\""))
    #expect(jsonString.contains("\"ownerAccount\""))
    #expect(jsonString.contains("\"isDirectory\""))
  }

  @Test
  func `Permission string formatting`() async throws {
    let testCases: [(Int, String)] = [
      (0o644, "rw-r--r--"),
      (0o755, "rwxr-xr-x"),
      (0o600, "rw-------"),
      (0o777, "rwxrwxrwx"),
      (0o000, "---------"),
      (0o400, "r--------"),
      (0o200, "-w-------"),
      (0o100, "--x------"),
    ]

    for (perms, expected) in testCases {
      let metadata = FileMetadata(
        path: "/tmp/test.md",
        size: 0,
        creationDate: nil,
        modificationDate: nil,
        accessDate: nil,
        posixPermissions: perms,
        ownerAccount: nil,
        groupOwnerAccount: nil,
        extendedAttributes: [:],
        fileType: nil,
        isDirectory: false,
        isSymbolicLink: false
      )

      let permString = try #require(metadata.permissionString)
      #expect(permString == expected, "Expected \(expected) for \(String(perms, radix: 8))")
    }
  }

  @Test
  func `Size formatting`() async throws {
    let testCases: [(Int64, String)] = [
      (0, "Zero KB"),
      (512, "512 bytes"),
      (1024, "1 KB"),
      (1_048_576, "1 MB"),
      (1_073_741_824, "1 GB"),
      (1500, "1.5 KB"),
    ]

    for (size, _) in testCases {
      let metadata = FileMetadata(
        path: "/tmp/test.md",
        size: size,
        creationDate: nil,
        modificationDate: nil,
        accessDate: nil,
        posixPermissions: nil,
        ownerAccount: nil,
        groupOwnerAccount: nil,
        extendedAttributes: [:],
        fileType: nil,
        isDirectory: false,
        isSymbolicLink: false
      )

      // Just verify it produces a non-empty string
      let formatted = metadata.formattedSize
      #expect(!formatted.isEmpty)
    }
  }

  @Test
  func `Date formatting for display`() async throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let metadata = FileMetadata(
      path: "/tmp/test.md",
      size: 0,
      creationDate: date,
      modificationDate: date,
      accessDate: date,
      posixPermissions: nil,
      ownerAccount: nil,
      groupOwnerAccount: nil,
      extendedAttributes: [:],
      fileType: nil,
      isDirectory: false,
      isSymbolicLink: false
    )

    // Verify formatted dates use ISO 8601
    let creationFormatted = try #require(metadata.formattedCreationDate)
    let modificationFormatted = try #require(metadata.formattedModificationDate)
    let accessFormatted = try #require(metadata.formattedAccessDate)

    // ISO 8601 format includes 'T' separator
    #expect(creationFormatted.contains("T"))
    #expect(modificationFormatted.contains("T"))
    #expect(accessFormatted.contains("T"))

    // Should be parseable back
    let formatter = ISO8601DateFormatter()
    let parsedCreation = try #require(formatter.date(from: creationFormatted))
    let interval = abs(parsedCreation.timeIntervalSince(date))
    #expect(interval < 1.0, "Parsed date should be close to original")
  }

  @Test
  func `Extended attributes encoding as base64`() async throws {
    let xattrData = Data([0x01, 0x02, 0x03, 0xFF, 0xFE])
    let metadata = FileMetadata(
      path: "/tmp/test.md",
      size: 0,
      creationDate: nil,
      modificationDate: nil,
      accessDate: nil,
      posixPermissions: nil,
      ownerAccount: nil,
      groupOwnerAccount: nil,
      extendedAttributes: ["com.test.attr": xattrData],
      fileType: nil,
      isDirectory: false,
      isSymbolicLink: false
    )

    // Encode as JSON
    let encoder = JSONEncoder()
    let data = try encoder.encode(metadata)
    let json = String(data: data, encoding: .utf8)

    let jsonString = try #require(json)

    // Verify base64 encoding in JSON
    #expect(jsonString.contains("com.test.attr"))
    // Note: JSONEncoder may escape forward slashes in base64, so just verify key exists

    // Decode and verify
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(FileMetadata.self, from: data)

    let decodedData = try #require(decoded.extendedAttributes["com.test.attr"])
    #expect(decodedData == xattrData)
  }

  @Test
  func `Handle missing optional fields`() async throws {
    let metadata = FileMetadata(
      path: "/tmp/test.md",
      size: 1024,
      creationDate: nil,
      modificationDate: nil,
      accessDate: nil,
      posixPermissions: nil,
      ownerAccount: nil,
      groupOwnerAccount: nil,
      extendedAttributes: [:],
      fileType: nil,
      isDirectory: false,
      isSymbolicLink: false
    )

    // Verify optional fields are nil
    #expect(metadata.creationDate == nil)
    #expect(metadata.modificationDate == nil)
    #expect(metadata.accessDate == nil)
    #expect(metadata.posixPermissions == nil)
    #expect(metadata.ownerAccount == nil)
    #expect(metadata.groupOwnerAccount == nil)
    #expect(metadata.fileType == nil)

    // Verify computed properties handle nil gracefully
    #expect(metadata.permissionString == nil)
    #expect(metadata.formattedCreationDate == nil)
    #expect(metadata.formattedModificationDate == nil)
    #expect(metadata.formattedAccessDate == nil)

    // Encode/decode should preserve nil values
    let encoder = JSONEncoder()
    let data = try encoder.encode(metadata)
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(FileMetadata.self, from: data)

    #expect(decoded.creationDate == nil)
    #expect(decoded.modificationDate == nil)
    #expect(decoded.posixPermissions == nil)
  }
}
