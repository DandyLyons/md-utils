import ArgumentParser
import Foundation
import MarkdownUtilitiesCore

/// Bounded, ordered preflight results shared by single and bulk creation.
enum CreationBatch {
  static let byteLimit = 64 * 1_024 * 1_024
  static let itemLimit = 10_000

  struct Item {
    var identity: String
    var input: JSONValue?
    var destination: URL?
    var content: Data?
    var failures: [String] = []
    var details: [String] = []

    var label: String { identity + (destination.map { " -> \($0.path)" } ?? "") }
  }

  struct Outcome {
    var item: Item
    var status: String
    var error: String?
  }

  static func load(options: InstanceCreationOptions, inputByteLimit: Int = byteLimit,
    maximumItems: Int = itemLimit,
  ) throws -> [Item] {
    try options.validate()
    if let path = options.values {
      let value = try JSONDecoder().decode(JSONValue.self, from: InstanceCreation.read(path, limit: inputByteLimit))
      guard case .array(let inputs) = value, !inputs.isEmpty else {
        throw ValidationError("--values \(path) must contain a nonempty JSON array of input objects.")
      }
      guard inputs.count <= maximumItems else { throw ValidationError("Batch exceeds \(maximumItems) items: \(path)") }
      return inputs.enumerated().map { Item(identity: "\(path)[\($0.offset)]", input: $0.element) }
    }
    let paths = options.value.map { [$0] } ?? options.valueFile
    guard paths.count <= maximumItems else { throw ValidationError("Batch exceeds \(maximumItems) items.") }
    var total = 0
    return try paths.enumerated().map { index, path in
      try Task.checkCancellation()
      var item = Item(identity: options.isBulk ? "\(path) (input \(index + 1))" : path)
      do {
        let data = try InstanceCreation.read(path, limit: inputByteLimit - total)
        total += data.count
        item.input = try JSONDecoder().decode(JSONValue.self, from: data)
      } catch is CancellationError { throw CancellationError() }
      catch { item.failures.append("Input (aggregate limit \(inputByteLimit) bytes): \(error)") }
      return item
    }
  }

  static func checkDestinations(_ items: inout [Item]) {
    var groups: [String: [Int]] = [:]
    for index in items.indices {
      guard let destination = items[index].destination else { continue }
      let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
      // Match the destination volume's case behavior without creating probe files.
      let caseSensitive = (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?.volumeSupportsCaseSensitiveNames ?? true
      let name = destination.lastPathComponent.precomposedStringWithCanonicalMapping
      let key = parent.path + "/" + (caseSensitive ? name : name.lowercased())
      groups[key, default: []].append(index)
      do {
        _ = try FileManager.default.attributesOfItem(atPath: destination.path)
        items[index].failures.append("Destination already exists: \(destination.path)")
      } catch {
        if (error as? CocoaError)?.code != .fileReadNoSuchFile {
          items[index].failures.append("Cannot inspect destination: \(error)")
        }
      }
    }
    for indices in groups.values where indices.count > 1 {
      // Every participant gets its own labeled diagnostic. Avoid quadratic reports
      // when many inputs select the same filename.
      let message = "Duplicate destination shared by \(indices.count) inputs."
      for index in indices { items[index].failures.append(message) }
    }
  }

  /// Stop after the first failed publication, retaining every completed file.
  /// The injected writer makes race and partial-completion tests deterministic.
  static func persist(_ items: [Item], dryRun: Bool,
    writer: (Data, URL) throws -> Void = InstanceCreation.create,
  ) -> [Outcome] {
    var stopped = false
    return items.map { item in
      guard !stopped else { return Outcome(item: item, status: "not attempted") }
      do {
        try Task.checkCancellation()
        guard item.failures.isEmpty, let content = item.content, let destination = item.destination else {
          throw ValidationError("Item has not passed preflight.")
        }
        if !dryRun { try writer(content, destination) }
        return Outcome(item: item, status: dryRun ? "Would create" : "Created")
      } catch {
        stopped = true
        return Outcome(item: item, status: "failed", error: String(describing: error))
      }
    }
  }
}
