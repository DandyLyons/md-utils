import Foundation

/// Errors that can occur when reading file metadata
public enum FileMetadataError: Error, Sendable {
  /// The file was not found at the specified path
  case fileNotFound(path: String)

  /// Permission denied when attempting to read the file
  case permissionDenied(path: String)

  /// The provided path is invalid
  case invalidPath(path: String)

  /// Extended attributes are not supported on this platform
  case xattrUnsupported

  /// Failed to read extended attributes
  case xattrReadFailed(path: String, attributeName: String?, reason: String)

  /// An underlying system error occurred
  case systemError(path: String, underlyingError: Error)
}

extension FileMetadataError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .fileNotFound(let path):
      return "File not found: \(path)"
    case .permissionDenied(let path):
      return "Permission denied: \(path)"
    case .invalidPath(let path):
      return "Invalid path: \(path)"
    case .xattrUnsupported:
      return "Extended attributes are not supported on this platform"
    case .xattrReadFailed(let path, let attributeName, let reason):
      if let name = attributeName {
        return "Failed to read extended attribute '\(name)' from \(path): \(reason)"
      } else {
        return "Failed to read extended attributes from \(path): \(reason)"
      }
    case .systemError(let path, let underlyingError):
      return "System error reading \(path): \(underlyingError.localizedDescription)"
    }
  }
}
