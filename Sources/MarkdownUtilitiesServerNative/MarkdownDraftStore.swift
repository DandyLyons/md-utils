import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesServer

/// Atomic JSON draft persistence; all mutations require the collection writer lease.
struct MarkdownDraftStore: Sendable {
  let root: URL
  var directory: URL { root.appendingPathComponent(".md-utils/drafts/", isDirectory: true) }

  func safe(_ url: URL) throws {
    guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else {
      throw MarkdownMutationError(422, "draft.path-unsafe", "Draft and receipt paths must not contain symlinks.")
    }
  }

  func url(_ id: String) throws -> URL {
    guard UUID(uuidString: id)?.uuidString.lowercased() == id else {
      throw MarkdownMutationError(400, "draft.id-invalid", "Expected a lowercase draft UUID.")
    }
    let url = directory.appendingPathComponent("\(id).json")
    try safe(url)
    return url
  }

  func load(_ id: String) throws -> MarkdownDraft {
    let url = try url(id)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw MarkdownMutationError(404, "draft.not-found", "No draft exists with this ID.")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 64 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 64 * 1024 * 1024 else {
      throw MarkdownMutationError(413, "draft.too-large", "Draft JSON exceeds 64 MiB.")
    }
    let draft = try JSONDecoder().decode(MarkdownDraft.self, from: data)
    guard draft.version == 1, draft.id == id, draft.operation == .patch || draft.operation == .replace,
      draft.attemptID.map({ UUID(uuidString: $0)?.uuidString.lowercased() == $0 }) ?? true else {
      throw MarkdownMutationError(422, "draft.invalid", "Unsupported or inconsistent draft envelope.")
    }
    _ = try draft.request()
    if draft.attemptID != nil && draft.resolvedPath == nil {
      throw MarkdownMutationError(422, "draft.invalid", "Submitted drafts require a bound source path.")
    }
    let unsubmitted = draft.state == .pending || draft.state == .conflict
    guard unsubmitted ? (draft.attemptID == nil && draft.resolvedPath == nil) : (draft.attemptID != nil && draft.resolvedPath != nil) else {
      throw MarkdownMutationError(422, "draft.invalid", "Draft lifecycle and submission evidence disagree.")
    }
    return draft
  }

  /// Enumerates only IDs, with a fixed bound; payloads are loaded one at a time.
  func ids() throws -> [String] {
    try safe(directory)
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    var failure: (any Error)?
    guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
      options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles], errorHandler: { _, error in
        failure = error; return false
      }) else {
      throw MarkdownMutationError(503, "draft.unavailable", "Cannot enumerate pending drafts.")
    }
    var ids: [String] = []
    while true {
      try Task.checkCancellation()
      let next = entries.nextObject()
      if let failure { throw failure }
      guard let next else { break }
      guard let next = next as? URL else {
        throw MarkdownMutationError(503, "draft.unavailable", "Unexpected draft directory entry.")
      }
      guard next.pathExtension == "json" else { continue }
      guard ids.count < 10_000 else {
        throw MarkdownMutationError(413, "draft.limit", "At most 10,000 drafts can be processed; discard completed drafts first.")
      }
      let id = next.deletingPathExtension().lastPathComponent
      _ = try url(id)
      ids.append(id)
    }
    return ids.sorted()
  }

  func save(_ draft: MarkdownDraft) throws {
    let url = try url(draft.id)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(draft).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
    try handle.synchronize()
    try NativeMutationFiles.syncDirectory(directory)
    try NativeMutationFiles.syncDirectory(directory.deletingLastPathComponent())
  }

  func discard(_ draft: MarkdownDraft) throws {
    guard draft.attemptID == nil || draft.state == .completed else {
      throw MarkdownMutationError(409, "draft.recovery-required", "Resolve the submitted attempt before discarding this draft.")
    }
    try FileManager.default.removeItem(at: url(draft.id))
    try NativeMutationFiles.syncDirectory(directory)
  }

  func pin(_ id: String, retain: Bool) throws {
    guard UUID(uuidString: id)?.uuidString.lowercased() == id else {
      throw MarkdownMutationError(400, "draft.attempt-invalid", "Invalid attempt UUID.")
    }
    let directory = root.appendingPathComponent(".md-utils/mutations/pins/", isDirectory: true)
    let file = directory.appendingPathComponent(id)
    try safe(file)
    if retain {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      if !FileManager.default.fileExists(atPath: file.path) { try Data().write(to: file, options: .withoutOverwriting) }
      let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
      try handle.synchronize()
      try NativeMutationFiles.syncDirectory(directory.deletingLastPathComponent())
    } else if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    } else { return }
    try NativeMutationFiles.syncDirectory(directory)
  }
}
