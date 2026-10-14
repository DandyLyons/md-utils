import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer

/// Shared bounded receipt storage for server mutations and explicitly selected
/// CLI edits. Reading never creates a journal; writes require the caller's lease.
struct NativeMutationJournal {
  let root: URL
  var directory: URL { root.appendingPathComponent(".md-utils/mutations/", isDirectory: true) }

  func url(_ id: String) throws -> URL {
    guard UUID(uuidString: id)?.uuidString.lowercased() == id else {
      throw MarkdownMutationError(400, "receipt.invalid-id", "Expected a lowercase receipt UUID.")
    }
    let url = directory.appendingPathComponent(id + ".json")
    try MarkdownDraftStore(root: root).safe(url)
    return url
  }

  func files() throws -> [URL] {
    try MarkdownDraftStore(root: root).safe(directory)
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
    guard files.count <= 10_000 else { throw MarkdownMutationError(413, "receipt.limit", "Receipt count exceeds 10,000.") }
    return files
  }

  func read(_ url: URL) throws -> MarkdownMutationReceipt {
    try MarkdownDraftStore(root: root).safe(url)
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 64 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 64 * 1024 * 1024 else { throw MarkdownMutationError(413, "receipt.limit", "Receipt exceeds 64 MiB.") }
    let receipt = try JSONDecoder().decode(MarkdownMutationReceipt.self, from: data)
    guard try self.url(receipt.id) == url else { throw MarkdownMutationError(422, "receipt.invalid", "Receipt ID does not match its path.") }
    return receipt
  }

  func write(_ receipt: MarkdownMutationReceipt) throws {
    let file = try url(receipt.id)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try NativeMutationFiles.syncDirectory(directory.deletingLastPathComponent())
    try NativeMutationFiles.syncDirectory(root)
    try JSONEncoder().encode(receipt).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.synchronize()
    try NativeMutationFiles.syncDirectory(directory)
  }
}
