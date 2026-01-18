/// Errors that can occur during heading adjustment operations.
public enum HeadingAdjusterError: Error, Equatable, Sendable {
  /// The target index is out of bounds for the document's heading array.
  ///
  /// - Parameters:
  ///   - index: The invalid index that was requested
  ///   - totalHeadings: The total number of headings in the document
  case invalidTargetIndex(Int, totalHeadings: Int)

  /// The document contains no headings to adjust.
  case noHeadingsInDocument
}

extension HeadingAdjusterError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .invalidTargetIndex(let index, let totalHeadings):
      return "Invalid heading index \(index). Document has \(totalHeadings) heading(s)."
    case .noHeadingsInDocument:
      return "Cannot adjust headings: document contains no headings."
    }
  }
}
