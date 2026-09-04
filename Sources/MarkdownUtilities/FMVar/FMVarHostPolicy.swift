import Foundation
import MarkdownUtilitiesCore

/// Configuration errors raised before an fm-var filesystem policy can be used.
public enum FMVarHostPolicyError: Error, Equatable, Sendable, LocalizedError {
  /// The allowed root was not a local file URL.
  case allowedRootIsNotFileURL(String)
  /// The allowed root did not identify an existing directory.
  case allowedRootIsNotDirectory(String)
  /// The source-byte limit cannot be represented by Foundation's bounded read API.
  case sourceLimitTooLarge(UInt64)

  public var errorDescription: String? {
    switch self {
    case .allowedRootIsNotFileURL(let value):
      "The fm-var allowed root must be a file URL: \(value)"
    case .allowedRootIsNotDirectory(let value):
      "The fm-var allowed root must be an existing directory: \(value)"
    case .sourceLimitTooLarge(let value):
      "The fm-var source-byte limit is too large for this host: \(value)"
    }
  }
}

/// Explicit native host policy for local fm-var source access and JSONPath evaluation.
///
/// The initial policy supports only local Markdown and YAML files beneath one canonical allowed
/// root. Network access, credentials, URI queries, file authorities, and redirects are disabled.
public struct FMVarHostPolicy: Equatable, Sendable {
  /// Default maximum size of one source representation: eight mebibytes.
  public static let defaultMaximumSourceByteCount: UInt64 = 8 * 1_024 * 1_024

  /// Canonical, symlink-resolved local directory that bounds source access.
  public let allowedRoot: URL
  /// Maximum bytes read from one Markdown or YAML source.
  public let maximumSourceByteCount: UInt64
  /// Deterministic JSONPath resource limits.
  public let jsonPathLimits: FMVarJSONPathLimits
  /// RFC 9535 functions exposed by the evaluator.
  public let availableJSONPathFunctions: Set<FMVarJSONPathFunction>

  /// Creates a validated native fm-var host policy.
  ///
  /// - Parameters:
  ///   - allowedRoot: Existing local directory that contains every authorized source.
  ///   - maximumSourceByteCount: Maximum representation size, defaulting to eight mebibytes.
  ///   - jsonPathLimits: Deterministic query limits used by the portable evaluator.
  ///   - availableJSONPathFunctions: Standard RFC functions the host makes available.
  public init(
    allowedRoot: URL,
    maximumSourceByteCount: UInt64 = Self.defaultMaximumSourceByteCount,
    jsonPathLimits: FMVarJSONPathLimits = FMVarJSONPathLimits(),
    availableJSONPathFunctions: Set<FMVarJSONPathFunction> = Set(
      FMVarJSONPathFunction.allCases
    )
  ) throws {
    guard allowedRoot.isFileURL else {
      throw FMVarHostPolicyError.allowedRootIsNotFileURL(allowedRoot.absoluteString)
    }
    guard maximumSourceByteCount < UInt64(Int.max) else {
      throw FMVarHostPolicyError.sourceLimitTooLarge(maximumSourceByteCount)
    }

    let canonicalRoot = allowedRoot.absoluteURL.standardizedFileURL
      .resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: canonicalRoot.path,
      isDirectory: &isDirectory
    ), isDirectory.boolValue else {
      throw FMVarHostPolicyError.allowedRootIsNotDirectory(canonicalRoot.path)
    }

    self.allowedRoot = canonicalRoot
    self.maximumSourceByteCount = maximumSourceByteCount
    self.jsonPathLimits = jsonPathLimits
    self.availableJSONPathFunctions = availableJSONPathFunctions
  }

  /// Creates the portable evaluator configured with this host's capabilities and limits.
  public func makeJSONPathEvaluator() -> FMVarJSONPathEvaluator {
    FMVarJSONPathEvaluator(
      limits: jsonPathLimits,
      availableFunctions: availableJSONPathFunctions
    )
  }
}

/// Filesystem-backed provider that enforces an ``FMVarHostPolicy`` before reading bytes.
public struct FileFMVarResourceProvider: FMVarResourceProvider, Sendable {
  /// Policy applied to containing and external resources.
  public let policy: FMVarHostPolicy

  /// Creates a local provider for an explicit policy.
  public init(policy: FMVarHostPolicy) {
    self.policy = policy
  }

  /// Loads the immutable containing-document snapshot through the same policy as external sources.
  ///
  /// Successful snapshots use the canonical file URL as their base identifier, so relative
  /// references resolve from the physical containing-document location.
  public func containingResource(at fileURL: URL) -> FMVarResourceProviderResult {
    guard fileURL.isFileURL else {
      return failure(
        .unsupported,
        "The containing fm-var resource must be a local file."
      )
    }
    let canonical = fileURL.absoluteURL.standardizedFileURL
      .resolvingSymlinksInPath().standardizedFileURL
    return load(
      fileURL: fileURL.absoluteURL.standardizedFileURL,
      identifier: FMVarResourceIdentifier(rawValue: canonical.absoluteString)
    )
  }

  /// Authorizes and reads one already-resolved local resource request.
  public func resource(for request: FMVarResourceRequest) async -> FMVarResourceProviderResult {
    guard hasValidPercentEncoding(request.identifier.rawValue),
      let components = URLComponents(string: request.identifier.rawValue),
      components.scheme?.lowercased() == "file"
    else {
      return failure(.unsupported, "This fm-var host supports only local file sources.")
    }
    guard components.user == nil, components.password == nil else {
      return failure(.unsupported, "Credentials are not supported in fm-var source identifiers.")
    }
    guard components.host == nil || components.host?.isEmpty == true,
      components.port == nil
    else {
      return failure(.unsupported, "File URI authorities are not supported by this fm-var host.")
    }
    guard components.query == nil else {
      return failure(.unsupported, "URI queries are not supported for local fm-var sources.")
    }
    guard components.fragment == nil,
      let decodedPath = components.percentEncodedPath.removingPercentEncoding,
      decodedPath.hasPrefix("/"),
      decodedPath.unicodeScalars.contains(where: { $0.value == 0 }) == false
    else {
      return failure(.unsupported, "The fm-var file identifier cannot be mapped to a local path.")
    }

    return load(
      fileURL: URL(fileURLWithPath: decodedPath).standardizedFileURL,
      identifier: request.identifier
    )
  }

  private func load(
    fileURL lexicalURL: URL,
    identifier: FMVarResourceIdentifier
  ) -> FMVarResourceProviderResult {
    guard isContained(lexicalURL, in: policy.allowedRoot) else {
      return failure(
        .outsideAllowedRoot,
        "The fm-var source path is outside the configured allowed root."
      )
    }

    let canonicalURL = lexicalURL.resolvingSymlinksInPath().standardizedFileURL
    guard isContained(canonicalURL, in: policy.allowedRoot) else {
      return failure(
        .symlinkEscape,
        "The fm-var source resolves through a symlink outside the configured allowed root."
      )
    }
    guard let contentType = supportedContentType(for: canonicalURL) else {
      return failure(
        .unsupported,
        "The local fm-var source must be Markdown or YAML."
      )
    }

    do {
      let attributes: [FileAttributeKey: Any]
      do {
        attributes = try FileManager.default.attributesOfItem(atPath: canonicalURL.path)
      } catch let error as NSError where
        error.domain == NSCocoaErrorDomain
          && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
      {
        return failure(.notFound, "The authorized local fm-var source does not exist.")
      }
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        return failure(.unreadable, "The local fm-var source is not a regular file.")
      }
      if let fileSize = attributes[.size] as? NSNumber,
        fileSize.uint64Value > policy.maximumSourceByteCount
      {
        return failure(
          .excessiveSize,
          "The local fm-var source exceeds the configured byte limit."
        )
      }

      let handle = try FileHandle(forReadingFrom: canonicalURL)
      defer { try? handle.close() }
      let readLimit = Int(policy.maximumSourceByteCount) + 1
      let bytes = try handle.read(upToCount: readLimit) ?? Data()
      guard UInt64(bytes.count) <= policy.maximumSourceByteCount else {
        return failure(
          .excessiveSize,
          "The local fm-var source exceeds the configured byte limit."
        )
      }

      return .resource(FMVarResource(
        identifier: identifier,
        bytes: bytes,
        contentType: contentType
      ))
    } catch {
      return failure(.unreadable, "The authorized local fm-var source could not be read.")
    }
  }

  private func isContained(_ fileURL: URL, in rootURL: URL) -> Bool {
    let rootComponents = rootURL.standardizedFileURL.pathComponents
    let fileComponents = fileURL.absoluteURL.standardizedFileURL.pathComponents
    return fileComponents.starts(with: rootComponents)
  }

  private func supportedContentType(for fileURL: URL) -> String? {
    switch fileURL.pathExtension.lowercased() {
    case "md", "markdown": "text/markdown"
    case "yaml", "yml": "application/yaml"
    default: nil
    }
  }

  private func hasValidPercentEncoding(_ identifier: String) -> Bool {
    let bytes = Array(identifier.utf8)
    var index = 0
    while index < bytes.count {
      guard bytes[index] == 37 else {
        index += 1
        continue
      }
      guard index + 2 < bytes.count,
        isHexDigit(bytes[index + 1]),
        isHexDigit(bytes[index + 2])
      else {
        return false
      }
      index += 3
    }
    return true
  }

  private func isHexDigit(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
  }

  private func failure(
    _ reason: FMVarResourceAccessFailureReason,
    _ message: String
  ) -> FMVarResourceProviderResult {
    .failure(FMVarResourceAccessFailure(reason: reason, message: message))
  }
}
