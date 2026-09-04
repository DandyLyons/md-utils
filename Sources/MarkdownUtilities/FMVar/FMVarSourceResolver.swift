import Foundation
import MarkdownUtilitiesCore

/// Resolves one fm-var source through an injected provider and projects its YAML authority.
///
/// This adapter performs no filesystem or network access itself. Hosts supply already-authorized
/// bytes through `FMVarResourceProvider`. See `ResolvingFMVarSources` in
/// MarkdownUtilitiesCore documentation for the portable source contract.
public struct FMVarSourceResolver: Sendable {
  private let uriResolver: FMVarURIResolver
  private let projector: FMVarYAMLProjector

  /// Creates a source resolver with the portable RFC 3986 and YAML projection components.
  public init(
    uriResolver: FMVarURIResolver = FMVarURIResolver(),
    projector: FMVarYAMLProjector = FMVarYAMLProjector()
  ) {
    self.uriResolver = uriResolver
    self.projector = projector
  }

  /// Resolves and projects one source without recursively evaluating fm-var markup.
  ///
  /// - Parameters:
  ///   - reference: Authored `src`, or `nil` for the containing Markdown document.
  ///   - containingResource: Immutable authoritative containing-document snapshot.
  ///   - provider: Host boundary used only when the resolved identifier differs from the
  ///     containing resource identifier.
  /// - Returns: A valid query argument or a structured resolution failure.
  public func resolve(
    reference: String?,
    containingResource: FMVarResource,
    provider: any FMVarResourceProvider
  ) async -> FMVarSourceResolution {
    let identifier: FMVarResourceIdentifier
    do {
      identifier = try uriResolver.resolve(
        reference: reference,
        relativeTo: containingResource.identifier
      )
    } catch let error as FMVarURIResolutionError {
      return uriFailure(error, reference: reference)
    } catch {
      return failed(
        reference: reference,
        failure: FMVarSourceFailure(
          reason: .invalidReference,
          code: .invalidSourceReference,
          message: "Source URI resolution failed: \(error)"
        )
      )
    }

    let resource: FMVarResource
    if identifier == containingResource.identifier {
      resource = containingResource
    } else {
      let authoredReference = reference ?? ""
      switch await provider.resource(for: FMVarResourceRequest(
        reference: authoredReference,
        identifier: identifier
      )) {
      case .resource(let provided):
        guard provided.identifier == identifier else {
          return failed(
            reference: reference,
            identifier: identifier,
            failure: FMVarSourceFailure(
              reason: .unsupportedSource,
              code: .unsupportedSource,
              identifier: identifier,
              message: "Redirected or substituted fm-var resources are not supported by this resolver."
            )
          )
        }
        resource = provided
      case .failure(let accessFailure):
        return accessFailureResult(
          accessFailure,
          reference: reference,
          identifier: identifier
        )
      }
    }

    guard let kind = resourceKind(for: resource) else {
      return failed(
        reference: reference,
        identifier: identifier,
        failure: FMVarSourceFailure(
          reason: .unsupportedResourceKind,
          code: .unsupportedResourceKind,
          identifier: identifier,
          message: "The resource content type and URI extension do not identify Markdown or YAML."
        )
      )
    }
    let bom = Data([0xEF, 0xBB, 0xBF])
    let sourceBytes: Data
    if resource.bytes.starts(with: bom) {
      sourceBytes = Data(resource.bytes.dropFirst(bom.count))
      guard sourceBytes.starts(with: bom) == false else {
        return failed(
          reference: reference,
          identifier: identifier,
          resourceKind: kind,
          failure: FMVarSourceFailure(
            reason: .unreadableSource,
            code: .unreadableSource,
            identifier: identifier,
            message: "The fm-var source contains more than one leading UTF-8 BOM."
          )
        )
      }
    } else {
      sourceBytes = resource.bytes
    }
    guard let source = String(data: sourceBytes, encoding: .utf8) else {
      return failed(
        reference: reference,
        identifier: identifier,
        resourceKind: kind,
        failure: FMVarSourceFailure(
          reason: .unreadableSource,
          code: .unreadableSource,
          identifier: identifier,
          message: "The fm-var source is not valid UTF-8."
        )
      )
    }
    let yaml: String
    let rootRequirement: FMVarYAMLRootRequirement
    switch kind {
    case .yaml:
      yaml = source
      rootRequirement = .any
    case .markdown:
      var markdown = source[...]
      switch FMVarMarkdownYAMLExtractor().parse(&markdown) {
      case .yaml(let extracted):
        yaml = extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "{}"
          : extracted
        rootRequirement = .mapping
      case .missing:
        return failed(
          reference: reference,
          identifier: identifier,
          resourceKind: kind,
          failure: FMVarSourceFailure(
            reason: .missingFrontmatter,
            code: .missingYAMLFrontmatter,
            identifier: identifier,
            message: "The Markdown source does not contain YAML frontmatter."
          )
        )
      case .unsupportedTOML:
        return failed(
          reference: reference,
          identifier: identifier,
          resourceKind: kind,
          failure: FMVarSourceFailure(
            reason: .unsupportedFrontmatterFormat,
            code: .unsupportedFrontmatterFormat,
            identifier: identifier,
            message: "TOML frontmatter is not an RFC 001 fm-var source."
          )
        )
      case .malformed:
        return failed(
          reference: reference,
          identifier: identifier,
          resourceKind: kind,
          failure: FMVarSourceFailure(
            reason: .malformedFrontmatter,
            code: .malformedYAMLFrontmatter,
            identifier: identifier,
            message: "The Markdown source has an incomplete YAML frontmatter envelope."
          )
        )
      }
    }

    let projection = projector.project(yaml: yaml, rootRequirement: rootRequirement)
    guard let argument = projection.argument else {
      let projectionFailure = projection.failure
      return failed(
        reference: reference,
        identifier: identifier,
        resourceKind: kind,
        failure: FMVarSourceFailure(
          reason: .invalidQueryArgument,
          code: projectionFailure?.diagnosticCode ?? .invalidQueryArgument,
          identifier: identifier,
          queryArgumentFailure: projectionFailure,
          message: projectionFailure?.message ?? "YAML projection did not produce a query argument."
        )
      )
    }

    return FMVarSourceResolution(
      status: .resolved,
      reference: reference,
      identifier: identifier,
      resourceKind: kind,
      queryArgument: argument
    )
  }

  private func resourceKind(for resource: FMVarResource) -> FMVarResourceKind? {
    let mediaType = resource.contentType?
      .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
      .first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch mediaType {
    case "text/markdown":
      return .markdown
    case "application/yaml", "text/yaml", "application/x-yaml", "text/x-yaml":
      return .yaml
    case nil, "", "application/octet-stream", "text/plain":
      return resourceKind(fromPathIn: resource.identifier.rawValue)
    default:
      return nil
    }
  }

  private func resourceKind(fromPathIn identifier: String) -> FMVarResourceKind? {
    let withoutQuery = identifier.split(separator: "?", maxSplits: 1).first.map(String.init) ?? identifier
    let finalSegment = withoutQuery.split(separator: "/", omittingEmptySubsequences: false).last
      .map(String.init) ?? ""
    guard let period = finalSegment.lastIndex(of: ".") else { return nil }
    let fileExtension = finalSegment[finalSegment.index(after: period)...].lowercased()
    switch fileExtension {
    case "md", "markdown": return .markdown
    case "yaml", "yml": return .yaml
    default: return nil
    }
  }

  private func uriFailure(
    _ error: FMVarURIResolutionError,
    reference: String?
  ) -> FMVarSourceResolution {
    let reason: FMVarSourceFailureReason
    let code: FMVarDiagnosticCode
    switch error {
    case .invalidBaseURI:
      reason = .invalidBaseURI
      code = .invalidBaseURI
    case .invalidReference, .fragmentNotAllowed:
      reason = .invalidReference
      code = .invalidSourceReference
    }
    return failed(
      reference: reference,
      failure: FMVarSourceFailure(
        reason: reason,
        code: code,
        message: error.localizedDescription
      )
    )
  }

  private func accessFailureResult(
    _ accessFailure: FMVarResourceAccessFailure,
    reference: String?,
    identifier: FMVarResourceIdentifier
  ) -> FMVarSourceResolution {
    let reason: FMVarSourceFailureReason
    let code: FMVarDiagnosticCode
    switch accessFailure.reason {
    case .denied:
      reason = .accessDenied
      code = .sourceAccessDenied
    case .outsideAllowedRoot:
      reason = .outsideAllowedRoot
      code = .sourceOutsideAllowedRoot
    case .symlinkEscape:
      reason = .symlinkEscape
      code = .sourceSymlinkEscape
    case .unsupported:
      reason = .unsupportedSource
      code = .unsupportedSource
    case .notFound:
      reason = .sourceNotFound
      code = .sourceNotFound
    case .unreadable:
      reason = .unreadableSource
      code = .unreadableSource
    case .excessiveSize:
      reason = .excessiveSourceSize
      code = .excessiveSourceSize
    }
    return failed(
      reference: reference,
      identifier: identifier,
      failure: FMVarSourceFailure(
        reason: reason,
        code: code,
        identifier: identifier,
        message: accessFailure.message
      )
    )
  }

  private func failed(
    reference: String?,
    identifier: FMVarResourceIdentifier? = nil,
    resourceKind: FMVarResourceKind? = nil,
    failure: FMVarSourceFailure
  ) -> FMVarSourceResolution {
    FMVarSourceResolution(
      status: .failed,
      reference: reference,
      identifier: identifier,
      resourceKind: resourceKind,
      failure: failure
    )
  }
}
