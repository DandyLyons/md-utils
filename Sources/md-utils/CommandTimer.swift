//
//  CommandTimer.swift
//  md-utils
//

import Foundation

struct CommandTimer {
  private let clock = ContinuousClock()
  private let start: ContinuousClock.Instant

  init() {
    start = clock.now
  }

  var elapsed: Duration {
    start.duration(to: clock.now)
  }

  func writeStatus(_ message: String) {
    fputs("\(message) in \(formattedElapsed()).\n", stderr)
  }

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
