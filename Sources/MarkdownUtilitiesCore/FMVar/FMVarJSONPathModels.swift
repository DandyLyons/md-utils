import Foundation

/// RFC 9535 function extensions available to fm-var JSONPath queries.
///
/// DynamicJSON supplies the implementations. Hosts may remove these standard functions from an
/// evaluator's capability set, in which case a query that calls one reports an unsupported
/// capability rather than a malformed query. Additional functions supplied by DynamicJSON remain
/// available so the adapter does not redefine the dependency's query language.
public enum FMVarJSONPathFunction: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  /// Returns the length of a string, array, or object.
  case length
  /// Returns the number of nodes in a nodelist.
  case count
  /// Tests whether an entire string matches a regular expression.
  case match
  /// Tests whether part of a string matches a regular expression.
  case search
  /// Converts a single-node nodelist to its value.
  case value
}

/// Deterministic resource limits applied around DynamicJSON parsing and evaluation.
///
/// The execution-work limit is a conservative estimate derived from query segments, selectors,
/// and query-argument node count. The regular-expression limit is a conservative preflight
/// estimate based on DynamicJSON's parsed expression tree and query-argument string sizes.
public struct FMVarJSONPathLimits: Codable, Equatable, Sendable {
  /// Maximum UTF-8 byte count of an authored query.
  public let maximumQueryLength: UInt
  /// Maximum query-segment count and maximum query-argument value depth.
  public let maximumNestingDepth: UInt
  /// Maximum conservative execution-work estimate.
  public let maximumExecutionWork: UInt
  /// Maximum number of nodes in the returned nodelist.
  public let maximumResultCount: UInt
  /// Maximum accumulated regular-expression work estimate.
  public let maximumRegularExpressionWork: UInt

  /// Creates a JSONPath resource policy.
  public init(
    maximumQueryLength: UInt = 4_096,
    maximumNestingDepth: UInt = 128,
    maximumExecutionWork: UInt = 1_000_000,
    maximumResultCount: UInt = 10_000,
    maximumRegularExpressionWork: UInt = 1_000_000
  ) {
    self.maximumQueryLength = maximumQueryLength
    self.maximumNestingDepth = maximumNestingDepth
    self.maximumExecutionWork = maximumExecutionWork
    self.maximumResultCount = maximumResultCount
    self.maximumRegularExpressionWork = maximumRegularExpressionWork
  }

  private enum CodingKeys: String, CodingKey {
    case maximumQueryLength = "maximum-query-length"
    case maximumNestingDepth = "maximum-nesting-depth"
    case maximumExecutionWork = "maximum-execution-work"
    case maximumResultCount = "maximum-result-count"
    case maximumRegularExpressionWork = "maximum-regular-expression-work"
  }
}

/// Stable reason for a failed fm-var JSONPath evaluation.
public enum FMVarJSONPathFailureReason: String, Codable, Equatable, Sendable, CaseIterable {
  /// The query did not begin with the required root identifier `$`.
  case invalidRoot = "invalid-root"
  /// DynamicJSON rejected the query while parsing it.
  case invalidSyntax = "invalid-syntax"
  /// DynamicJSON rejected the query while evaluating its expression semantics.
  case invalidSemantics = "invalid-semantics"
  /// The query called a function unavailable in the configured capability set.
  case unsupportedFunction = "unsupported-function"
  /// The query exceeded the configured UTF-8 length limit.
  case queryLengthLimit = "query-length-limit"
  /// The query or its argument exceeded the configured nesting limit.
  case nestingLimit = "nesting-limit"
  /// The conservative execution-work estimate exceeded its configured limit.
  case executionWorkLimit = "execution-work-limit"
  /// The evaluated nodelist exceeded the configured result-count limit.
  case resultCountLimit = "result-count-limit"
  /// Regular-expression evaluation exceeded its configured work limit.
  case regularExpressionWorkLimit = "regular-expression-work-limit"
}

/// Structured details for an invalid, unsupported, or resource-limited JSONPath query.
public struct FMVarJSONPathFailure: Codable, Equatable, Sendable {
  /// Stable machine-readable failure reason.
  public let reason: FMVarJSONPathFailureReason
  /// Range in the authored query. DynamicJSON does not expose token offsets, so dependency errors
  /// identify the complete query while locally enforced root errors identify the first character.
  public let queryRange: FMVarSourceRange
  /// Human-readable wording that is not stable API.
  public let message: String
  /// Function name for an unsupported function failure.
  public let functionName: String?
  /// Configured limit for a resource failure.
  public let limit: UInt?
  /// Measured or estimated amount that exceeded ``limit``.
  public let observed: UInt?

  /// Creates structured JSONPath failure details.
  public init(
    reason: FMVarJSONPathFailureReason,
    queryRange: FMVarSourceRange,
    message: String,
    functionName: String? = nil,
    limit: UInt? = nil,
    observed: UInt? = nil
  ) {
    self.reason = reason
    self.queryRange = queryRange
    self.message = message
    self.functionName = functionName
    self.limit = limit
    self.observed = observed
  }

  private enum CodingKeys: String, CodingKey {
    case reason
    case queryRange = "query-range"
    case message
    case functionName = "function-name"
    case limit
    case observed
  }
}

/// Result of applying one authored JSONPath query to an fm-var query argument.
public struct FMVarJSONPathEvaluation: Codable, Equatable, Sendable {
  /// Portable outcome category shared with fm-var reference metadata.
  public let status: FMVarQueryEvaluationStatus
  /// Ordered selected nodes when ``status`` is ``FMVarQueryEvaluationStatus/selected``.
  public let nodelist: FMVarNodelist?
  /// Structured failure when evaluation did not produce a nodelist.
  public let failure: FMVarJSONPathFailure?

  /// Creates a structured evaluation result.
  public init(
    status: FMVarQueryEvaluationStatus,
    nodelist: FMVarNodelist? = nil,
    failure: FMVarJSONPathFailure? = nil
  ) {
    self.status = status
    self.nodelist = nodelist
    self.failure = failure
  }
}
