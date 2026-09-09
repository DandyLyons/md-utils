import ArgumentParser
import Foundation
import MarkdownUtilitiesCore
import Noora
import PathKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Small injectable boundary around Noora; scripted tests exercise the real authoring flow.
struct InteractivePrompts {
  var choose: (String, [String]) throws -> String
  var text: (String, String?, Bool) throws -> String
  var confirm: (String) throws -> Bool
  var output: (String) -> Void

  static func terminal() throws -> Self {
    guard isatty(STDIN_FILENO) == 1 else {
      throw ValidationError("Interactive authoring requires a terminal on standard input.")
    }
    let noora = Noora()
    return Self(
      choose: { question, options in
        let answer = noora.singleChoicePrompt(question: "\(question)",
          options: options.map(InteractiveChoice.value) + [.cancel], filterMode: .enabled)
        switch answer {
        case .cancel: throw InteractiveCancellation.cancelled
        case .value(let value): return value
        }
      },
      text: { prompt, value, required in
        let answer = noora.textPrompt(prompt: "\(prompt)", description: "Enter :cancel to discard this session.", defaultValue: value,
          validationRules: required ? [NonEmptyValidationRule(error: "A value is required.")] : [])
        if answer == ":cancel" { throw InteractiveCancellation.cancelled }
        return answer
      },
      confirm: { question in
        noora.yesOrNoChoicePrompt(question: "\(question)", defaultAnswer: false, collapseOnSelection: true)
      },
      output: { print($0) }
    )
  }

  func required(_ prompt: String, default value: String? = nil) throws -> String {
    while true {
      let result = try text(prompt, value, true)
      if result.isEmpty == false && result == result.trimmingCharacters(in: .whitespacesAndNewlines) { return result }
      output(CLIStyle.error("Enter a nonempty value without surrounding whitespace."))
    }
  }

  func json(_ prompt: String, default value: JSONValue? = nil) throws -> JSONValue {
    while true {
      let input = try text(prompt, try value.map { try InteractiveDraftSession.json($0.foundationValue).trimmingCharacters(in: .newlines) }, false)
      do {
        return try JSONValue(any: JSONSerialization.jsonObject(with: Data(input.utf8), options: .fragmentsAllowed))
      } catch { output(CLIStyle.error("Invalid JSON: \(error.localizedDescription)")) }
    }
  }

  func number(_ prompt: String) throws -> Int {
    while true {
      let value = try json(prompt + " (nonnegative integer)")
      if case .integer(let number) = value, number >= 0 { return number }
      if case .number(let number) = value, number >= 0, number < Double(Int.max), number.rounded() == number {
        return Int(number)
      }
      output(CLIStyle.error("Enter a nonnegative integer."))
    }
  }
}

enum InteractiveCancellation: Error { case cancelled }

/// Cancellation remains distinct even when a resource is named "Cancel".
private enum InteractiveChoice: Equatable, CustomStringConvertible {
  case value(String)
  case cancel

  var description: String {
    switch self {
    case .value(let value): return value
    case .cancel: return "Cancel"
    }
  }
}

struct InteractiveAuthoring {
  let prompts: InteractivePrompts

  func run(types: Bool, selectedName: String?, root: Path) throws {
    do {
      var session = InteractiveDraftSession(root: root)
      let action = try prompts.choose(types ? "Types" : "Rules", ["Create", "Edit", "Remove"])
      if types {
        let definitions = try session.typeDefinitions()
        let original: MarkdownTypeDefinition?
        if action == "Create" { original = nil }
        else {
          guard definitions.isEmpty == false else { throw ValidationError("No types configured") }
          let name = try selectedName ?? prompts.choose("Select type by declared name", definitions.map { $0.name.rawValue })
          guard let found = definitions.first(where: { $0.name.rawValue == name }) else { throw ValidationError("Type not found: \(name)") }
          original = found
        }
        if action == "Remove", let source = original?.source {
          try session.stage(path: Path(source), content: nil)
        } else {
          _ = try authorType(original: original, session: &session)
        }
      } else {
        let rules = try session.ruleFiles()
        let original: MarkdownRuleFile?
        if action == "Create" { original = nil }
        else {
          guard rules.isEmpty == false else { throw ValidationError("No rules configured") }
          let name = try selectedName ?? prompts.choose("Select rule", rules.map(\.name))
          guard let found = rules.first(where: { $0.name == name }) else { throw ValidationError("Rule not found: \(name)") }
          original = found
        }
        if action == "Remove", let original {
          try session.stage(path: Path(original.source), content: nil)
        } else {
          try authorRule(original: original, session: &session)
        }
      }
      try finish(session)
    } catch InteractiveCancellation.cancelled {
      prompts.output(CLIStyle.muted("Cancelled. No files changed."))
    }
  }

  @discardableResult
  func finish(_ session: InteractiveDraftSession) throws -> Bool {
    try session.validate()
    prompts.output(session.preview())
    guard try prompts.confirm("Apply these validated changes?") else {
      prompts.output(CLIStyle.muted("Cancelled. No files changed."))
      return false
    }
    try session.commit()
    prompts.output(CLIStyle.success("Saved changes."))
    return true
  }
}
