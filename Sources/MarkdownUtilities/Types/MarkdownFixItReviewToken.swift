import Crypto
import MarkdownUtilitiesCore

/// Native hashing of portable review data. No files, index, or draft state are
/// created. A token binds numbered proposals to evidence; it is not authorization.
public enum MarkdownFixItReviewToken {
  public static func token(for review: MarkdownFixItReview) throws -> String {
    let digest = SHA256.hash(data: try review.canonicalData())
    let hexadecimal = digest.map { byte in
      let value = String(byte, radix: 16)
      return value.count == 1 ? "0" + value : value
    }.joined()
    return "fix-review-v1-" + hexadecimal
  }

  /// Call with a freshly rebuilt review before interpreting numbered selections.
  /// Native application must still recheck revisions at each coordinated write.
  public static func verify(_ token: String, against current: MarkdownFixItReview) throws {
    guard token == (try self.token(for: current)) else {
      throw MarkdownFixItReviewError.staleReview
    }
  }

  /// Verify the reviewed context before resolving short numbers. This remains a
  /// read-only operation; selection alone never authorizes persistent changes.
  public static func select(
    _ token: String,
    from current: MarkdownFixItReview,
    numbers: [Int],
    automatic: Bool = false,
    includeRecommendations: Bool = false,
  ) throws -> [Int] {
    try verify(token, against: current)
    return try current.select(numbers: numbers, automatic: automatic,
      includeRecommendations: includeRecommendations,
    )
  }
}
