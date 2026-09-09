import Foundation
import Testing
@testable import MarkdownUtilitiesCore

@Suite("official fm-var fixtures")
struct FMVarFixtureContractTests {
  @Test("every official fixture has parseable before and after documents")
  func officialFixturesAreParseable() throws {
    let root = try #require(Bundle.module.url(forResource: "FMVar", withExtension: nil))
      .appendingPathComponent("official-fixtures")
    let directories = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
    ).filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    #expect(directories.count == 23)
    for directory in directories {
      let context = Comment(rawValue: directory.lastPathComponent)
      let before = try String(contentsOf: directory.appendingPathComponent("before.md"), encoding: .utf8)
      let after = try String(contentsOf: directory.appendingPathComponent("after.md"), encoding: .utf8)
      let beforeResult = try FMVarParser().parse(before)
      let afterResult = try FMVarParser().parse(after)

      #expect(beforeResult.elements.map(\.kind) == afterResult.elements.map(\.kind), context)
      #expect(beforeResult.elements.count == afterResult.elements.count, context)

      var synchronized = before
      for (beforeElement, afterElement) in zip(
        beforeResult.elements.reversed(), afterResult.elements.reversed()
      ) {
        #expect(try beforeResult.text(in: beforeElement.openingTagRange) ==
          afterResult.text(in: afterElement.openingTagRange), context)
        guard beforeElement.kind == .variable || beforeElement.kind == .list else { continue }
        guard let beforeCache = beforeElement.cacheRange,
          let afterCache = afterElement.cacheRange else {
          #expect(beforeElement.cacheRange == nil && afterElement.cacheRange == nil, context)
          continue
        }
        let replacement = try afterResult.text(in: afterCache)
        let snapshot = try FMVarParser().parse(synchronized)
        synchronized = try snapshot.replacingCache(
          ofElementOrdinal: beforeElement.ordinal, with: replacement
        )
      }
      #expect(synchronized == after, context)
    }
  }
}
