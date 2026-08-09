import Foundation

/// Errors produced while preparing a black-box CLI test process.
enum CLIProcessTestHelperError: Error, CustomStringConvertible, Sendable {
  /// The built `md-utils` executable was not found at the expected location.
  case executableNotFound(URL)

  /// A diagnostic describing why the test process could not be prepared.
  var description: String {
    switch self {
    case .executableNotFound(let url):
      return "Built md-utils executable not found at \(url.path)"
    }
  }
}

/// The observable result of running the built `md-utils` executable.
struct CLIProcessResult: Sendable {
  /// The process termination status.
  let status: Int32

  /// All bytes written to standard output, decoded as UTF-8.
  let standardOutput: String

  /// All bytes written to standard error, decoded as UTF-8.
  let standardError: String
}

/// Runs black-box CLI tests that need the executable process boundary.
///
/// Prefer `parseAsRoot` for ordinary argument parsing and in-process command
/// execution tests. Use this helper when a test must observe process exit status,
/// stdin interaction, or the executable's stdout/stderr routing.
enum CLIProcessTestHelper {
  /// Runs the built `md-utils` executable with controlled input and environment.
  ///
  /// - Parameters:
  ///   - arguments: Arguments passed after the executable name.
  ///   - standardInput: UTF-8 text supplied to the process on standard input.
  ///   - environment: Environment values added to the current process environment.
  /// - Returns: The termination status and captured output streams.
  static func run(
    _ arguments: [String],
    standardInput: String = "",
    environment: [String: String] = [:],
    workingDirectory: URL? = nil
  ) throws -> CLIProcessResult {
    let captureDirectoryURL = URL(
      filePath: FileManager.default.currentDirectoryPath,
      directoryHint: .isDirectory
    ).appending(
      path: "tmp/cli-process-\(UUID().uuidString)/",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
      at: captureDirectoryURL,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: captureDirectoryURL) }

    let inputURL = captureDirectoryURL.appending(path: "stdin.txt")
    let outputURL = captureDirectoryURL.appending(path: "stdout.txt")
    let errorURL = captureDirectoryURL.appending(path: "stderr.txt")
    try Data(standardInput.utf8).write(to: inputURL)
    try Data().write(to: outputURL)
    try Data().write(to: errorURL)

    let inputHandle = try FileHandle(forReadingFrom: inputURL)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer {
      try? inputHandle.close()
      try? outputHandle.close()
      try? errorHandle.close()
    }

    let process = Process()
    process.executableURL = try executableURL()
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory

    var processEnvironment = ProcessInfo.processInfo.environment
    processEnvironment["NO_COLOR"] = "1"
    processEnvironment["TERM"] = "dumb"
    processEnvironment.merge(environment) { _, supplied in supplied }
    process.environment = processEnvironment
    process.standardInput = inputHandle
    process.standardOutput = outputHandle
    process.standardError = errorHandle

    try process.run()
    process.waitUntilExit()
    try outputHandle.synchronize()
    try errorHandle.synchronize()

    return CLIProcessResult(
      status: process.terminationStatus,
      standardOutput: String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
      standardError: String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
    )
  }

  /// Locates the executable built beside the test bundle.
  private static func executableURL() throws -> URL {
    let candidate = Bundle.module.bundleURL
      .deletingLastPathComponent()
      .appending(path: "md-utils")
    guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
      throw CLIProcessTestHelperError.executableNotFound(candidate)
    }
    return candidate
  }
}
