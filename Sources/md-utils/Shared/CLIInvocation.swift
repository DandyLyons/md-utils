import Foundation

/// Reusable received-argument provenance. Display quoting cannot recover shell input.
struct CLIInvocation: Encodable {
  var argv: [String]
  var workingDirectory: String
  var displayCommand: String { argv.map(Self.quote).joined(separator: " ") }

  static func quote(_ value: String) -> String {
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-")
    if !value.isEmpty && value.unicodeScalars.allSatisfy(safe.contains) { return value }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  enum CodingKeys: String, CodingKey { case argv, workingDirectory, displayCommand }
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(argv, forKey: .argv)
    try container.encode(workingDirectory, forKey: .workingDirectory)
    try container.encode(displayCommand, forKey: .displayCommand)
  }
}
