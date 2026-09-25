import Foundation
import MarkdownUtilitiesCore
import MarkdownUtilitiesIndex
import MarkdownUtilitiesServer
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Same-directory atomic persistence, isolated because Foundation does not provide
/// portable atomic replacement plus no-clobber creation and directory fsync.
enum NativeMutationFiles {
  static func url(root: URL, path: MarkdownRecordPath) throws -> URL {
    let file = root.appendingPathComponent(path.rawValue).standardizedFileURL
    guard file.path.hasPrefix(root.path + "/"),
      !path.rawValue.split(separator: "/").contains(".md-utils"),
      file.resolvingSymlinksInPath().path == file.path else {
      throw MarkdownMutationError(422, "path.unsafe", "Mutation paths must stay inside the collection without symlinks.")
    }
    return file
  }

  static func read(_ url: URL) throws -> Data? {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    if fd < 0 {
      if errno == ENOENT { return nil }
      throw MarkdownMutationError(503, "source.unavailable", "Cannot read authoritative source.")
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
      throw MarkdownMutationError(422, "source.unsupported", "Expected a regular Markdown file.")
    }
    let data = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 8 * 1024 * 1024 else { throw MarkdownMutationError(413, "source.too-large", "Mutation source exceeds 8 MiB.") }
    return data
  }

  static func persist(url: URL, content: Data?, expected: MarkdownRecordRevision?, modificationDate: Date? = nil) throws {
    let current = try read(url)
    if let expected {
      guard let current, IndexFingerprint.hash(current) == expected.rawValue else {
        throw MarkdownMutationError(412, "revision.stale", "Source changed before commit.")
      }
    } else if current != nil { throw MarkdownMutationError(409, "path.exists", "Creation path already exists.") }
    if let content {
      let directory = url.deletingLastPathComponent()
      let temporary = directory.appendingPathComponent(".md-utils-write-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: temporary) }
      try content.write(to: temporary, options: .withoutOverwriting)
      if let mode = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temporary.path)
      }
      if let modificationDate { try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: temporary.path) }
      let handle = try FileHandle(forWritingTo: temporary)
      try handle.synchronize(); try handle.close()
      // Recheck after staging. External editors may still race this final check.
      let latest = try read(url)
      if let expected {
        guard latest.map(IndexFingerprint.hash) == expected.rawValue else {
          throw MarkdownMutationError(412, "revision.stale", "Source changed while staging.")
        }
        guard rename(temporary.path, url.path) == 0 else { throw failure() }
      } else {
        // link is atomic and fails if any directory entry already owns this name.
        guard link(temporary.path, url.path) == 0 else {
          if errno == EEXIST { throw MarkdownMutationError(409, "path.exists", "Creation path already exists.") }
          throw failure()
        }
      }
    } else {
      guard unlink(url.path) == 0 else { throw failure() }
    }
    try syncDirectory(url.deletingLastPathComponent())
  }

  static func syncDirectory(_ directory: URL) throws {
    let fd = open(directory.path, O_RDONLY | O_CLOEXEC)
    guard fd >= 0 else { throw failure() }
    defer { _ = close(fd) }
    guard fsync(fd) == 0 else { throw failure() }
  }
  private static func failure() -> MarkdownMutationError {
    MarkdownMutationError(503, "persistence.failed", "Filesystem persistence or durability failed; inspect operation status.")
  }
}
