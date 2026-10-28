/// Shared source/snapshot limits for collection discovery, survey, and query.
package enum DocumentReadBudgets {
  package static let files = 100_000
  package static let sourceBytes = 64 * 1024 * 1024
  package static let aggregateBytes = 256 * 1024 * 1024
  package static func traversal(files: Int) -> Int {
    let scaled = files.multipliedReportingOverflow(by: 4)
    return max(Self.files, scaled.overflow ? Int.max : scaled.partialValue)
  }
}
