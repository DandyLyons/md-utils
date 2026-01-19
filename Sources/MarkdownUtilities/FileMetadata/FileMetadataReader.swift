import Foundation

/// Reads file metadata including standard attributes and extended attributes
public struct FileMetadataReader: Sendable {
  public init() {}

  /// Read metadata from a file at the specified path
  /// - Parameters:
  ///   - path: The file path to read metadata from
  ///   - includeExtendedAttributes: Whether to include extended attributes (xattr). Default is true.
  /// - Returns: FileMetadata containing all available metadata
  /// - Throws: FileMetadataError if reading fails
  public func readMetadata(
    at path: String,
    includeExtendedAttributes: Bool = true
  ) throws -> FileMetadata {
    let fileManager = FileManager.default

    // Expand tilde and standardize path
    let expandedPath = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath)

    // Check if file exists
    guard fileManager.fileExists(atPath: expandedPath) else {
      throw FileMetadataError.fileNotFound(path: path)
    }

    // Get file attributes
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try fileManager.attributesOfItem(atPath: expandedPath)
    } catch let error as NSError {
      // Map common errors to FileMetadataError
      if error.domain == NSCocoaErrorDomain {
        switch error.code {
        case NSFileReadNoPermissionError:
          throw FileMetadataError.permissionDenied(path: path)
        case NSFileNoSuchFileError:
          throw FileMetadataError.fileNotFound(path: path)
        default:
          throw FileMetadataError.systemError(path: path, underlyingError: error)
        }
      }
      throw FileMetadataError.systemError(path: path, underlyingError: error)
    }

    // Extract standard attributes
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let creationDate = attributes[.creationDate] as? Date
    let modificationDate = attributes[.modificationDate] as? Date

    // Access date requires resource values on macOS
    var accessDate: Date?
    if let resourceValues = try? url.resourceValues(forKeys: [.contentAccessDateKey]) {
      accessDate = resourceValues.contentAccessDate
    }

    let posixPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
    let ownerAccount = attributes[.ownerAccountName] as? String
    let groupOwnerAccount = attributes[.groupOwnerAccountName] as? String
    let fileType = (attributes[.type] as? FileAttributeType)?.rawValue

    // Determine if directory or symbolic link
    let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
    let isSymbolicLink = (attributes[.type] as? FileAttributeType) == .typeSymbolicLink

    // Read extended attributes if requested
    let extendedAttributes: [String: Data]
    if includeExtendedAttributes {
      // Let xattr errors propagate so callers can handle them appropriately
      // Non-Darwin platforms return empty dict without error
      extendedAttributes = try readExtendedAttributes(at: expandedPath)
    } else {
      extendedAttributes = [:]
    }

    return FileMetadata(
      path: path,
      size: size,
      creationDate: creationDate,
      modificationDate: modificationDate,
      accessDate: accessDate,
      posixPermissions: posixPermissions,
      ownerAccount: ownerAccount,
      groupOwnerAccount: groupOwnerAccount,
      extendedAttributes: extendedAttributes,
      fileType: fileType,
      isDirectory: isDirectory,
      isSymbolicLink: isSymbolicLink
    )
  }
}
