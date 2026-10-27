import ArgumentParser
import Foundation

/// Shared report presentation choices; JSON layout never changes the report data.
enum ReportOutputFormat: String, CaseIterable, ExpressibleByArgument {
  case text
  case json
  case jsonPretty = "json-pretty"
}

/// Common deterministic JSON serialization for CLI reports.
enum JSONReportOutput {
  static func encode<Value: Encodable>(_ value: Value, pretty: Bool) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}
