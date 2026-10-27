import Foundation

/// Delayed, phase-based feedback; all state is isolated and no filesystem work
/// is performed to obtain a progress count. Callers supply counts they discovered.
actor SurveyProgress {
  private var phase = "Discovering files…"
  private var lastMessage: String?
  private var finished = false

  func update(_ phase: String) {
    guard !finished else { return }
    self.phase = phase
  }

  func finish() { finished = true }

  func nextMessage() -> String? {
    guard !finished, phase != lastMessage else { return nil }
    lastMessage = phase
    return "Please be patient. " + phase
  }

  /// Runs as a structured child task, cancelled and joined before final output.
  func watch() async {
    do {
      while !finished {
        try await Task.sleep(for: .seconds(1))
        try Task.checkCancellation()
        if let message = nextMessage() {
          FileHandle.standardError.write(Data((message + "\n").utf8))
        }
      }
    } catch is CancellationError {
      // Completion, errors, and cancellation all terminate the feedback task.
    } catch { return }
  }
}
