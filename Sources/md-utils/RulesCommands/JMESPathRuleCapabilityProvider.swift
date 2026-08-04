import Foundation
import ArgumentParser
import JMESPath
import MarkdownUtilitiesCore

/// CLI-only JMESPath bridge used by the shared Core rule compiler and checker.
final class JMESPathRuleCapabilityProvider: MarkdownRuleQueryCapabilityProvider, @unchecked Sendable {
  let capabilities: Set<MarkdownRuleRuntimeCapability> = [.frontmatterJMESPath]
  private let lock = NSLock()

  func validateJMESPath(_ expression: String) throws {
    lock.lock()
    defer { lock.unlock() }
    do {
      _ = try JMESExpression.compile(expression)
    } catch {
      throw ValidationError("Invalid JMESPath expression: \(error.localizedDescription)")
    }
  }

  func evaluateJMESPath(_ expression: String, frontmatter: JSONValue) throws -> JSONValue? {
    lock.lock()
    defer { lock.unlock() }
    let compiled = try JMESExpression.compile(expression)
    guard let result = try compiled.search(object: frontmatter.foundationValue) else { return nil }
    return try JSONValue(any: result)
  }
}
