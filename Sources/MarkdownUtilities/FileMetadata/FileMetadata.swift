import Foundation

/// Represents file metadata including standard attributes and extended attributes (xattr)
public struct FileMetadata: Sendable, Codable {
  /// The file path
  public let path: String

  /// File size in bytes
  public let size: Int64

  /// Creation date of the file
  public let creationDate: Date?

  /// Last modification date of the file
  public let modificationDate: Date?

  /// Last access date of the file
  public let accessDate: Date?

  /// POSIX file permissions as octal number (e.g., 0o644)
  public let posixPermissions: Int?

  /// Owner account name
  public let ownerAccount: String?

  /// Group owner account name
  public let groupOwnerAccount: String?

  /// Extended attributes (xattr) as key-value pairs
  public let extendedAttributes: [String: Data]

  /// File type description (e.g., "NSFileTypeRegular", "NSFileTypeDirectory")
  public let fileType: String?

  /// Whether this is a directory
  public let isDirectory: Bool

  /// Whether this is a symbolic link
  public let isSymbolicLink: Bool

  /// Initialize a FileMetadata instance
  public init(
    path: String,
    size: Int64,
    creationDate: Date?,
    modificationDate: Date?,
    accessDate: Date?,
    posixPermissions: Int?,
    ownerAccount: String?,
    groupOwnerAccount: String?,
    extendedAttributes: [String: Data],
    fileType: String?,
    isDirectory: Bool,
    isSymbolicLink: Bool
  ) {
    self.path = path
    self.size = size
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.accessDate = accessDate
    self.posixPermissions = posixPermissions
    self.ownerAccount = ownerAccount
    self.groupOwnerAccount = groupOwnerAccount
    self.extendedAttributes = extendedAttributes
    self.fileType = fileType
    self.isDirectory = isDirectory
    self.isSymbolicLink = isSymbolicLink
  }
}

// MARK: - Computed Properties

extension FileMetadata {
  /// Permission string in Unix format (e.g., "rwxr-xr-x")
  public var permissionString: String? {
    guard let perms = posixPermissions else { return nil }

    let types = ["---", "--x", "-w-", "-wx", "r--", "r-x", "rw-", "rwx"]
    let owner = types[(perms >> 6) & 0o7]
    let group = types[(perms >> 3) & 0o7]
    let other = types[perms & 0o7]

    return owner + group + other
  }

  /// Human-readable file size
  public var formattedSize: String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  /// ISO 8601 formatted creation date
  public var formattedCreationDate: String? {
    creationDate.map { ISO8601DateFormatter().string(from: $0) }
  }

  /// ISO 8601 formatted modification date
  public var formattedModificationDate: String? {
    modificationDate.map { ISO8601DateFormatter().string(from: $0) }
  }

  /// ISO 8601 formatted access date
  public var formattedAccessDate: String? {
    accessDate.map { ISO8601DateFormatter().string(from: $0) }
  }
}

// MARK: - Codable

extension FileMetadata {
  private enum CodingKeys: String, CodingKey {
    case path, size, creationDate, modificationDate, accessDate
    case posixPermissions, ownerAccount, groupOwnerAccount
    case extendedAttributes, fileType, isDirectory, isSymbolicLink
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    size = try container.decode(Int64.self, forKey: .size)

    // Decode dates as ISO 8601 strings
    let dateFormatter = ISO8601DateFormatter()
    if let creationDateString = try container.decodeIfPresent(String.self, forKey: .creationDate) {
      creationDate = dateFormatter.date(from: creationDateString)
    } else {
      creationDate = nil
    }

    if let modificationDateString = try container.decodeIfPresent(String.self, forKey: .modificationDate)
    {
      modificationDate = dateFormatter.date(from: modificationDateString)
    } else {
      modificationDate = nil
    }

    if let accessDateString = try container.decodeIfPresent(String.self, forKey: .accessDate) {
      accessDate = dateFormatter.date(from: accessDateString)
    } else {
      accessDate = nil
    }

    posixPermissions = try container.decodeIfPresent(Int.self, forKey: .posixPermissions)
    ownerAccount = try container.decodeIfPresent(String.self, forKey: .ownerAccount)
    groupOwnerAccount = try container.decodeIfPresent(String.self, forKey: .groupOwnerAccount)

    // Decode extended attributes as base64-encoded strings
    if let xattrDict = try container.decodeIfPresent(
      [String: String].self, forKey: .extendedAttributes)
    {
      var decodedXattr: [String: Data] = [:]
      for (key, value) in xattrDict {
        if let data = Data(base64Encoded: value) {
          decodedXattr[key] = data
        }
      }
      extendedAttributes = decodedXattr
    } else {
      extendedAttributes = [:]
    }

    fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
    isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
    isSymbolicLink = try container.decode(Bool.self, forKey: .isSymbolicLink)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(path, forKey: .path)
    try container.encode(size, forKey: .size)

    // Encode dates as ISO 8601 strings
    let dateFormatter = ISO8601DateFormatter()
    if let creationDate = creationDate {
      try container.encode(dateFormatter.string(from: creationDate), forKey: .creationDate)
    }

    if let modificationDate = modificationDate {
      try container.encode(dateFormatter.string(from: modificationDate), forKey: .modificationDate)
    }

    if let accessDate = accessDate {
      try container.encode(dateFormatter.string(from: accessDate), forKey: .accessDate)
    }

    try container.encodeIfPresent(posixPermissions, forKey: .posixPermissions)
    try container.encodeIfPresent(ownerAccount, forKey: .ownerAccount)
    try container.encodeIfPresent(groupOwnerAccount, forKey: .groupOwnerAccount)

    // Encode extended attributes as base64-encoded strings
    if !extendedAttributes.isEmpty {
      var xattrDict: [String: String] = [:]
      for (key, value) in extendedAttributes {
        xattrDict[key] = value.base64EncodedString()
      }
      try container.encode(xattrDict, forKey: .extendedAttributes)
    } else {
      try container.encode([String: String](), forKey: .extendedAttributes)
    }

    try container.encodeIfPresent(fileType, forKey: .fileType)
    try container.encode(isDirectory, forKey: .isDirectory)
    try container.encode(isSymbolicLink, forKey: .isSymbolicLink)
  }
}
