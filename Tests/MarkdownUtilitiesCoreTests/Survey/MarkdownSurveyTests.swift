import Foundation
import Testing
@testable import MarkdownUtilitiesCore

struct MarkdownSurveyTests {
  private func observe(_ content: String, path: String = "note.md") async throws -> MarkdownSurveyObservation {
    try await MarkdownSurveyObservation.read(MarkdownRecord(
      content: content,
      context: MarkdownRecordContext(path: try MarkdownRecordPath(path)),
    ))
  }

  @Test func presenceAndFailuresRemainDistinct() async throws {
    let absent = try await observe("# Note")
    let empty = try await observe("---\n{}\n---\n")
    let malformed = try await observe("---\ntags: [broken\n---\n")
    let unsupported = try await observe("plain source", path: "note.unknown")
    #expect(absent.state == .absent)
    #expect(empty.state == .parsed)
    #expect(empty.frontmatter == [:])
    #expect(malformed.state == .malformed)
    #expect(malformed.diagnostics.isEmpty == false)
    #expect(unsupported.state == .unsupported)
  }

  @Test func supportedTextAndCRLFUseExistingParserContract() async throws {
    let text = try await observe("---\ntitle: Text\n---\n", path: "note.txt")
    let crlf = try await observe("---\r\ntitle: Text\r\n---\r\n")
    #expect(text.state == .parsed)
    #expect(crlf.state == .absent)
  }

  @Test func invalidTypeHintsAreNotMalformedYAML() async throws {
    let value = try await observe("---\n$md-utils:\n  typeHints: wrong\ntitle: Valid\n---\n")
    #expect(value.state == .parsed)
    #expect(value.frontmatter?["title"] == .string("Valid"))
  }

  @Test func kindsAndNativeTemporalEvidenceSurviveRoundtrip() async throws {
    let value = try await observe("---\nn: null\nb: true\ni: 2\nf: 2.5\ns: '2'\na: []\no: {}\nd: 2026-10-26\nquoted: '2026-10-26'\n---\n")
    let decoded = try JSONDecoder().decode(MarkdownSurveyObservation.self, from: JSONEncoder().encode(value))
    for (key, kind) in ["n": "null", "b": "boolean", "i": "integer", "f": "number", "s": "string", "a": "array", "o": "object", "d": "yaml-timestamp", "quoted": "string"] {
      #expect(try decoded.value(at: key)?.kind == kind)
    }
  }

  @Test func tomlNativeTemporalKindsRemainDistinct() async throws {
    let value = try await observe("+++\nd = 2026-10-26\nt = 12:30:00\ndt = 2026-10-26T12:30:00\noffset = 2026-10-26T12:30:00Z\n+++\n")
    #expect(try value.value(at: "d")?.kind == "local-date")
    #expect(try value.value(at: "t")?.kind == "local-time")
    #expect(try value.value(at: "dt")?.kind == "local-date-time")
    #expect(try value.value(at: "offset")?.kind == "offset-date-time")
  }

  @Test func literalKeysAndPointersNeverAlias() async throws {
    let value = try await observe("---\na.b: literal\na:\n  b: nested\na/b: slash\nitems: [one, two]\n---\n")
    #expect(try value.value(at: "a.b")?.value == .string("literal"))
    #expect(try value.value(at: "/a/b", pointer: true)?.value == .string("nested"))
    #expect(try value.value(at: "/a~1b", pointer: true)?.value == .string("slash"))
    #expect(try value.value(at: "/items/1", pointer: true)?.value == .string("two"))
    #expect(try value.value(at: "/items/2", pointer: true) == nil)
    #expect(throws: MarkdownSurveyError.invalidPointer) { try value.value(at: "/a~2b", pointer: true) }
    #expect(throws: MarkdownSurveyError.invalidPointer) { try value.value(at: "a/b", pointer: true) }
  }

  @Test func keysCountDocumentsWithExplicitDenominators() async throws {
    let records = try await [
      observe("---\ntags: [a, a, a]\ntitle: One\n---\n", path: "one.md"),
      observe("---\ntags: null\n---\n", path: "two.md"),
      observe("body", path: "three.md"),
      observe("---\nx: [broken\n---\n", path: "four.md"),
    ]
    let report = try MarkdownSurveyStatistics.keys(records, top: 1)
    #expect(report.total == 2)
    #expect(report.omitted == 1)
    let tags = try #require(report.rows.first)
    #expect(tags.key == "tags")
    #expect(tags.present == 2)
    #expect(tags.missing == 1)
    #expect(tags.unassessable == 1)
    #expect(tags.kinds == ["array": 1, "null": 1])
  }

  @Test func valuesPreserveTypedIdentityAndArrayCounting() async throws {
    let records = try await [
      observe("---\nx: [a, a, b]\n---\n", path: "one.md"),
      observe("---\nx: [a]\n---\n", path: "two.md"),
      observe("---\nx: 1\n---\n", path: "three.md"),
      observe("---\nx: '1'\n---\n", path: "four.md"),
    ]
    let whole = try MarkdownSurveyStatistics.values(records, key: "x", top: 0)
    #expect(whole.total == 4)
    let documents = try MarkdownSurveyStatistics.values(records, key: "x", elements: true, top: 0)
    let occurrences = try MarkdownSurveyStatistics.values(records, key: "x", elements: true, occurrences: true, top: 0)
    #expect(documents.rows.first?.count == 2)
    #expect(occurrences.rows.first?.count == 3)
    #expect(documents.nonArrays == 2)
  }

  @Test func objectsIgnoreKeyOrderAndArraysRetainOrder() async throws {
    let records = try await [
      observe("---\nx: {a: 1, b: 2}\ny: [1, 2]\n---\n", path: "one.md"),
      observe("---\nx: {b: 2, a: 1}\ny: [2, 1]\n---\n", path: "two.md"),
    ]
    #expect(try MarkdownSurveyStatistics.values(records, key: "x").total == 1)
    #expect(try MarkdownSurveyStatistics.values(records, key: "y").total == 2)
  }

  @Test func outliersRequireBothSampleAndShareThresholds() async throws {
    var records: [MarkdownSurveyObservation] = []
    for index in 0..<19 {
      records.append(try await observe("---\nx: 2\n---\n", path: "\(index).md"))
    }
    records.append(try await observe("---\nx: 'two'\n---\n", path: "exception.md"))
    records.append(try await observe("body", path: "missing.md"))
    let result = try MarkdownSurveyStatistics.key(records, key: "x", outliers: true)
    #expect(result.outlierPaths == ["exception.md"])
    #expect(result.missing == 1)
    #expect(try MarkdownSurveyStatistics.key(Array(records.dropFirst()), key: "x", outliers: true).outlierPaths.isEmpty)
    #expect(try MarkdownSurveyStatistics.key(records, key: "x", outliers: true, minShare: 0.96).outlierPaths.isEmpty)
  }

  @Test func cancellationIsNotConvertedToAnEmptyKeyTable() async throws {
    let record = try await observe("---\nx: 1\n---\n")
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try MarkdownSurveyStatistics.keys([record])
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
