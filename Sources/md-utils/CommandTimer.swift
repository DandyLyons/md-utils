//
//  CommandTimer.swift
//  md-utils
//

import Foundation
/// Represents command timer.
struct CommandTimer {
  private let clock = ContinuousClock()
  private let start: ContinuousClock.Instant
  /// Creates a configured instance.
  init() {
    start = clock.now
  }

  var elapsed: Duration {
    start.duration(to: clock.now)
  }
  /// Writes a status message with elapsed command time.
  func writeStatus(_ message: String) {
    CLIStyle.writeStderr("\(message) \(CLIStyle.metadata("in \(formattedElapsed())."))")
  }
  /// Formats the value for user-facing output.
  private func formattedElapsed() -> String {
    let components = elapsed.components
    let milliseconds =
      (Double(components.seconds) * 1_000) + (Double(components.attoseconds) / 1_000_000_000_000_000)

    if milliseconds < 1_000 {
      return String(format: "%.2fms", milliseconds)
    }

    return String(format: "%.2fs", milliseconds / 1_000)
  }
}
