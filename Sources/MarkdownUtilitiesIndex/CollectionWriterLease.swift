import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Cross-process coordination for participating refresh and mutation writers.
///
/// Isolated POSIX adapter: Swift has no advisory file-lock API. The kernel releases
/// the lease on process exit; no stale lock-file deletion or guessed expiry is used.
public final class CollectionWriterLease: @unchecked Sendable {
  public let root: URL
  private let descriptor: Int32
  private init(root: URL, descriptor: Int32) { self.root = root; self.descriptor = descriptor }
  deinit { _ = close(descriptor) }

  public static func acquire(root: URL) async throws -> CollectionWriterLease {
    let root = root.resolvingSymlinksInPath()
    let directory = root.appendingPathComponent(".md-utils/", isDirectory: true)
    guard directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else {
      throw SQLiteIndexError(message: "Writer coordination directory must not be a symlink.")
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fd = open(directory.appendingPathComponent("writer.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw SQLiteIndexError(message: "Cannot open collection writer lease.") }
    do {
      while flock(fd, LOCK_EX | LOCK_NB) != 0 {
        guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else {
          throw SQLiteIndexError(message: "Cannot acquire collection writer lease.")
        }
        try await Task.sleep(for: .milliseconds(25))
      }
      try Task.checkCancellation()
      return CollectionWriterLease(root: root, descriptor: fd)
    } catch { _ = close(fd); throw error }
  }
}
