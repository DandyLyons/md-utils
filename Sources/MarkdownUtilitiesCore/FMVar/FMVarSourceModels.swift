import Foundation

/// Absolute, fragment-free identifier for an fm-var source resource.
///
/// ``FMVarURIResolver`` validates identifiers before they are used for resolution. The raw
/// initializer remains available so hosts can construct immutable resource snapshots before
/// asking the resolver to validate them.
public struct FMVarResourceIdentifier: RawRepresentable, Codable, Equatable, Hashable, Sendable {
  /// The RFC 3986 URI spelling used to identify the resource.
  public let rawValue: String

  /// Creates a resource identifier from its URI spelling.
  public init(rawValue: String) { self.rawValue = rawValue }

  /// A bounded identifier spelling suitable for diagnostics and logs.
  ///
  /// URI credentials and query contents can contain secrets. This representation removes user
  /// information and replaces any query with a fixed marker while retaining enough location
  /// context to explain a source-policy decision.
  public var diagnosticDescription: String {
    guard var components = URLComponents(string: rawValue) else {
      return "<unprintable-source>"
    }
    components.user = nil
    components.password = nil
    if components.query != nil {
      components.query = "redacted"
    }
    return components.string ?? "<unprintable-source>"
  }
}

/// Immutable bytes and representation metadata supplied by an fm-var host.
public struct FMVarResource: Codable, Equatable, Sendable {
  /// Identifier of the returned resource snapshot.
  public let identifier: FMVarResourceIdentifier
  /// Exact representation bytes.
  public let bytes: Data
  /// Optional media type, including optional parameters such as `charset=utf-8`.
  public let contentType: String?

  /// Creates one immutable resource snapshot.
  public init(
    identifier: FMVarResourceIdentifier,
    bytes: Data,
    contentType: String? = nil
  ) {
    self.identifier = identifier
    self.bytes = bytes
    self.contentType = contentType
  }
}

/// One already-resolved request passed to an fm-var resource provider.
public struct FMVarResourceRequest: Codable, Equatable, Sendable {
  /// Authored URI reference that produced the request.
  public let reference: String
  /// Absolute identifier obtained through RFC 3986 resolution.
  public let identifier: FMVarResourceIdentifier

  /// Creates a provider request.
  public init(reference: String, identifier: FMVarResourceIdentifier) {
    self.reference = reference
    self.identifier = identifier
  }
}

/// Stable host-level reason that a resource could not be supplied.
public enum FMVarResourceAccessFailureReason: String, Codable, Equatable, Sendable, CaseIterable {
  /// Host access policy denied the request.
  case denied
  /// The decoded, normalized path was outside the configured allowed root.
  case outsideAllowedRoot = "outside-allowed-root"
  /// A lexically in-root path resolved through a symlink to a target outside the allowed root.
  case symlinkEscape = "symlink-escape"
  /// The host does not implement the requested scheme, origin, or resource capability.
  case unsupported
  /// The authorized local source does not exist.
  case notFound = "not-found"
  /// An authorized resource could not be read.
  case unreadable
  /// The source representation exceeded the configured byte limit.
  case excessiveSize = "excessive-size"
}

/// Host-provided details for a resource access failure.
public struct FMVarResourceAccessFailure: Codable, Equatable, Sendable {
  /// Stable failure category.
  public let reason: FMVarResourceAccessFailureReason
  /// Human-readable explanation whose wording is not stable API.
  public let message: String

  /// Creates a resource access failure.
  public init(reason: FMVarResourceAccessFailureReason, message: String) {
    self.reason = reason
    self.message = message
  }
}

/// Result returned by an fm-var resource provider.
public enum FMVarResourceProviderResult: Equatable, Sendable {
  /// The requested immutable representation was obtained.
  case resource(FMVarResource)
  /// The host refused or failed to obtain the representation.
  case failure(FMVarResourceAccessFailure)
}

/// Supplies source bytes without prescribing filesystem, network, or authorization behavior.
public protocol FMVarResourceProvider: Sendable {
  /// Obtains one already-resolved source resource.
  ///
  /// Providers must not recursively resolve fm-var elements. Redirect and access policy belong to
  /// the host and are represented through ``FMVarResourceProviderResult``.
  func resource(for request: FMVarResourceRequest) async -> FMVarResourceProviderResult
}

/// Representation selected for fm-var resource decoding.
public enum FMVarResourceKind: String, Codable, Equatable, Sendable, CaseIterable {
  /// Markdown whose YAML frontmatter is authoritative.
  case markdown
  /// A standalone YAML document.
  case yaml
}

/// Stable failure reason while resolving or decoding an fm-var source.
public enum FMVarSourceFailureReason: String, Codable, Equatable, Sendable, CaseIterable {
  /// The containing document did not have a valid absolute base URI.
  case invalidBaseURI = "invalid-base-uri"
  /// The authored source was not a fragment-free RFC 3986 URI reference.
  case invalidReference = "invalid-reference"
  /// Host access policy denied the resolved resource.
  case accessDenied = "access-denied"
  /// The decoded, normalized local path was outside the host's allowed root.
  case outsideAllowedRoot = "outside-allowed-root"
  /// A local path escaped the allowed root after symlink resolution.
  case symlinkEscape = "symlink-escape"
  /// The host or decoder does not support the resource.
  case unsupportedSource = "unsupported-source"
  /// The authorized local source does not exist.
  case sourceNotFound = "source-not-found"
  /// The source representation could not be read or decoded.
  case unreadableSource = "unreadable-source"
  /// The source representation exceeded the host's byte limit.
  case excessiveSourceSize = "excessive-source-size"
  /// Resource metadata and URI path did not identify Markdown or YAML.
  case unsupportedResourceKind = "unsupported-resource-kind"
  /// Markdown did not contain YAML frontmatter.
  case missingFrontmatter = "missing-frontmatter"
  /// Markdown contained a frontmatter format other than YAML.
  case unsupportedFrontmatterFormat = "unsupported-frontmatter-format"
  /// Markdown began YAML frontmatter but did not contain a complete closing delimiter.
  case malformedFrontmatter = "malformed-frontmatter"
  /// YAML parsing or projection did not produce a portable query argument.
  case invalidQueryArgument = "invalid-query-argument"
}

/// Structured source-resolution failure shared by hosts and later fm-var evaluation stages.
public struct FMVarSourceFailure: Codable, Equatable, Sendable {
  /// Stable failure category.
  public let reason: FMVarSourceFailureReason
  /// Diagnostic code corresponding to ``reason`` or the nested projection failure.
  public let code: FMVarDiagnosticCode
  /// Resolved resource identifier when resolution succeeded before the failure.
  public let identifier: FMVarResourceIdentifier?
  /// YAML projection details when ``reason`` is ``FMVarSourceFailureReason/invalidQueryArgument``.
  public let queryArgumentFailure: FMVarQueryArgumentFailure?
  /// Human-readable explanation whose wording is not stable API.
  public let message: String

  /// Creates a structured source failure.
  public init(
    reason: FMVarSourceFailureReason,
    code: FMVarDiagnosticCode,
    identifier: FMVarResourceIdentifier? = nil,
    queryArgumentFailure: FMVarQueryArgumentFailure? = nil,
    message: String
  ) {
    self.reason = reason
    self.code = code
    self.identifier = identifier
    self.queryArgumentFailure = queryArgumentFailure
    self.message = message
  }
}

/// Outcome category for one source-resolution attempt.
public enum FMVarSourceResolutionStatus: String, Codable, Equatable, Sendable, CaseIterable {
  /// Resolution and YAML projection succeeded.
  case resolved
  /// URI resolution, resource access, decoding, or projection failed.
  case failed
}

/// Immutable result of resolving one source and constructing its JSONPath query argument.
public struct FMVarSourceResolution: Codable, Equatable, Sendable {
  /// Overall resolution outcome.
  public let status: FMVarSourceResolutionStatus
  /// Authored `src`, or `nil` when the containing document was requested implicitly.
  public let reference: String?
  /// Absolute resource identifier when URI resolution succeeded.
  public let identifier: FMVarResourceIdentifier?
  /// Selected resource representation when it could be determined.
  public let resourceKind: FMVarResourceKind?
  /// Validated projection supplied to ``FMVarJSONPathEvaluator``.
  public let queryArgument: FMVarQueryArgument?
  /// Structured failure when ``status`` is ``FMVarSourceResolutionStatus/failed``.
  public let failure: FMVarSourceFailure?

  /// Creates a source-resolution result.
  public init(
    status: FMVarSourceResolutionStatus,
    reference: String?,
    identifier: FMVarResourceIdentifier? = nil,
    resourceKind: FMVarResourceKind? = nil,
    queryArgument: FMVarQueryArgument? = nil,
    failure: FMVarSourceFailure? = nil
  ) {
    self.status = status
    self.reference = reference
    self.identifier = identifier
    self.resourceKind = resourceKind
    self.queryArgument = queryArgument
    self.failure = failure
  }

  private enum CodingKeys: String, CodingKey {
    case status
    case reference
    case identifier
    case resourceKind = "resource-kind"
    case queryArgument = "query-argument"
    case failure
  }
}
