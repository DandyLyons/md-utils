import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex

/// Encodes the existing Codable wire shapes one evidence item at a time. Stop at the
/// cache budget instead of first allocating an arbitrarily large collection JSON blob.
/// Evaluation remains useful when its evidence is too large to persist.
enum RelationshipCacheEncoding {
  private struct Capacity: Error {}

  static func encode<Value>(_ value: Value) throws -> Data? {
    let writer = Writer()
    do {
      if let value = value as? MarkdownRelationshipEvaluation { try writer.evaluation(value) }
      else if let value = value as? MarkdownRuleCollectionAssessment { try writer.policies(value) }
      else { return nil }
      return writer.data
    } catch is Capacity { return nil }
  }

  private final class Writer {
    var data = Data()
    let encoder: JSONEncoder = {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return encoder
    }()
    var fields: [Int] = []

    func append(_ bytes: Data) throws {
      try Task.checkCancellation()
      guard bytes.count <= SQLiteIndexDatabase.relationshipCacheBytes - data.count else { throw Capacity() }
      data.append(bytes)
    }
    func raw(_ text: String) throws { try append(Data(text.utf8)) }
    func value<T: Encodable>(_ value: T) throws { try append(encoder.encode(value)) }
    func object(_ body: () throws -> Void) throws {
      try raw("{")
      fields.append(0)
      try body()
      fields.removeLast()
      try raw("}")
    }
    func key(_ name: String) throws {
      guard let count = fields.last else { return }
      if count > 0 { try raw(",") }
      fields[fields.count - 1] += 1
      try value(name)
      try raw(":")
    }
    func field<T: Encodable>(_ name: String, _ item: T) throws {
      try key(name)
      try value(item)
    }
    func array<T>(_ name: String, _ items: [T], write: (T) throws -> Void) throws {
      try key(name)
      try raw("[")
      for (index, item) in items.enumerated() {
        if index > 0 { try raw(",") }
        try write(item)
      }
      try raw("]")
    }
    func evaluation(_ item: MarkdownRelationshipEvaluation) throws {
      try object {
        try field("evaluatorProfile", item.evaluatorProfile)
        if let collection = item.collection { try field("collection", collection) }
        if let generation = item.generation { try field("generation", generation) }
        try field("sourcesComplete", item.sourcesComplete)
        try field("candidatesComplete", item.candidatesComplete)
        try field("limitations", item.limitations)
        try field("diagnosticsTruncated", item.diagnosticsTruncated)
        try array("occurrences", item.occurrences, write: value)
        try array("assessments", item.assessments, write: value)
      }
    }
    func policies(_ item: MarkdownRuleCollectionAssessment) throws {
      try object {
        try field("evaluatorProfile", item.evaluatorProfile)
        try field("collection", item.collection)
        try field("generation", item.generation)
        try field("diagnosticsTruncated", item.diagnosticsTruncated)
        try field("limitations", item.limitations)
        try field("outcome", item.outcome)
        try key("extraction")
        try evaluation(item.extraction)
        try key("typeEvidence")
        try evaluation(item.typeEvidence)
        try array("conflicts", item.conflicts, write: value)
        try array("rules", item.rules) { rule in
          try object {
            try field("rule", rule.rule)
            try field("outcome", rule.outcome)
            try field("sourcesComplete", rule.sourcesComplete)
            try array("records", rule.records, write: value)
            try array("policies", rule.policies, write: value)
          }
        }
      }
    }
  }
}
