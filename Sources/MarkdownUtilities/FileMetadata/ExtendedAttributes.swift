import Foundation

#if canImport(Darwin)
  import Darwin

  /// Read all extended attributes from a file
  /// - Parameter path: The file path
  /// - Returns: Dictionary of attribute names to their data values
  /// - Throws: FileMetadataError if reading fails
  public func readExtendedAttributes(at path: String) throws -> [String: Data] {
    // Get the size needed for the attribute list
    let listSize = listxattr(path, nil, 0, 0)
    guard listSize >= 0 else {
      if errno == ENOENT {
        throw FileMetadataError.fileNotFound(path: path)
      } else if errno == EACCES {
        throw FileMetadataError.permissionDenied(path: path)
      }
      throw FileMetadataError.xattrReadFailed(
        path: path, attributeName: nil, reason: String(cString: strerror(errno)))
    }

    // No extended attributes
    if listSize == 0 {
      return [:]
    }

    // Allocate buffer and get attribute list
    var nameBuffer = [CChar](repeating: 0, count: listSize)
    let actualSize = listxattr(path, &nameBuffer, listSize, 0)
    guard actualSize >= 0 else {
      throw FileMetadataError.xattrReadFailed(
        path: path, attributeName: nil, reason: String(cString: strerror(errno)))
    }

    // Parse attribute names (null-terminated strings)
    var attributes: [String: Data] = [:]
    var index = 0
    while index < actualSize {
      let nameStart = index
      while index < actualSize && nameBuffer[index] != 0 {
        index += 1
      }

      if index > nameStart {
        let nameData = Data(bytes: &nameBuffer[nameStart], count: index - nameStart)
        if let name = String(data: nameData, encoding: .utf8) {
          // Read the attribute value
          do {
            let value = try readExtendedAttribute(at: path, name: name)
            attributes[name] = value
          } catch {
            // Skip attributes that can't be read
            continue
          }
        }
      }

      index += 1  // Skip null terminator
    }

    return attributes
  }

  /// Read a specific extended attribute from a file
  /// - Parameters:
  ///   - path: The file path
  ///   - name: The attribute name
  /// - Returns: The attribute data
  /// - Throws: FileMetadataError if reading fails
  public func readExtendedAttribute(at path: String, name: String) throws -> Data {
    // Get the size needed for the attribute value
    let valueSize = getxattr(path, name, nil, 0, 0, 0)
    guard valueSize >= 0 else {
      if errno == ENOENT {
        throw FileMetadataError.fileNotFound(path: path)
      } else if errno == EACCES {
        throw FileMetadataError.permissionDenied(path: path)
      } else if errno == ENOATTR {
        throw FileMetadataError.xattrReadFailed(
          path: path, attributeName: name, reason: "Attribute does not exist")
      }
      throw FileMetadataError.xattrReadFailed(
        path: path, attributeName: name, reason: String(cString: strerror(errno)))
    }

    // Allocate buffer and get attribute value
    var valueBuffer = [UInt8](repeating: 0, count: valueSize)
    let actualSize = getxattr(path, name, &valueBuffer, valueSize, 0, 0)
    guard actualSize >= 0 else {
      throw FileMetadataError.xattrReadFailed(
        path: path, attributeName: name, reason: String(cString: strerror(errno)))
    }

    return Data(bytes: valueBuffer, count: actualSize)
  }

#else
  // Stub implementation for unsupported platforms
  /// Read all extended attributes from a file (stub for unsupported platforms)
  /// - Parameter path: The file path
  /// - Returns: Empty dictionary (xattr not supported)
  public func readExtendedAttributes(at path: String) throws -> [String: Data] {
    return [:]
  }

  /// Read a specific extended attribute from a file (stub for unsupported platforms)
  /// - Parameters:
  ///   - path: The file path
  ///   - name: The attribute name
  /// - Returns: Empty data (xattr not supported)
  /// - Throws: FileMetadataError.xattrUnsupported
  public func readExtendedAttribute(at path: String, name: String) throws -> Data {
    throw FileMetadataError.xattrUnsupported
  }
#endif
