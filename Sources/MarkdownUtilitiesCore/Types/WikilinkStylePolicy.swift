import Foundation
import Parsing

/// Pure lexical assertions over an already parsed link; never resolves or rewrites it.
struct WikilinkStylePolicy {
  let styles: Set<String>?
  let markdownExtension: String

  init(_ value: JSONValue, path: String) throws {
    func invalid(_ message: String) -> MarkdownTypeDefinitionError {
      .invalidField("type.format.declaration at \(path): \(message)")
    }
    guard let object = value.objectValue,
      Set(object.keys).isSubset(of: ["styles", "markdownExtension"]) else {
      throw invalid("Expected wikilink policy with only styles and markdownExtension")
    }
    if let value = object["styles"] {
      guard case .array(let entries) = value, entries.isEmpty == false else {
        throw invalid("styles must be a nonempty array")
      }
      let names = entries.compactMap(\.stringValue)
      guard names.count == entries.count, Set(names).count == names.count,
        Set(names).isSubset(of: ["name", "vault-path", "relative-path", "self-anchor"]) else {
        throw invalid("styles must contain distinct supported style names")
      }
      styles = Set(names)
    } else { styles = nil }
    if let value = object["markdownExtension"] {
      guard let name = value.stringValue, ["require", "omit", "either"].contains(name) else {
        throw invalid("markdownExtension must be require, omit, or either")
      }
      markdownExtension = name
    } else { markdownExtension = "either" }
    if styles == ["self-anchor"], markdownExtension == "require" {
      throw invalid("self-anchor cannot require a Markdown extension")
    }
  }

  /// Returns every independent failed assertion, preserving syntax diagnostics separately.
  func failures(_ link: Wikilink) -> [(field: String, reason: String, message: String)] {
    var input = link.target[...]
    let relative = (try? OneOf { "./"; "../" }.parse(&input)) != nil
    // Recognize host-independent absolute spellings without interpreting them as
    // supported styles or asking Foundation/the filesystem to normalize a path.
    var absoluteInput = link.target[...]
    let rooted = (try? OneOf { "/"; "\\\\" }.parse(&absoluteInput)) != nil
    absoluteInput = link.target[...]
    let drive = Parse {
      Prefix<Substring>(1) { $0.isASCII && $0.isLetter }
      ":"
      OneOf { "/"; "\\" }
    }
    let driveAbsolute = (try? drive.parse(&absoluteInput)) != nil
    let components = link.target.split(separator: "/", omittingEmptySubsequences: false)
    let style: String
    if link.target.isEmpty { style = "self-anchor" }
    else if rooted || driveAbsolute { style = "unsupported-path" }
    else if relative { style = "relative-path" }
    else if components.count == 1 { style = "name" }
    else if components.first?.isEmpty == false, components.last?.isEmpty == false {
      style = "vault-path"
    } else { style = "unsupported-path" }
    let last = components.last.map(String.init)?.lowercased() ?? ""
    let hasExtension = last.hasSuffix(".md") || last.hasSuffix(".markdown")
    var result: [(String, String, String)] = []
    if let styles, styles.contains(style) == false {
      result.append(("styles", "wikilink-style", "Expected style \(styles.sorted().joined(separator: ", ")); found \(style)"))
    }
    if (markdownExtension == "require" && hasExtension == false)
      || (markdownExtension == "omit" && hasExtension) {
      result.append(("markdownExtension", "wikilink-extension", "Markdown extension policy \(markdownExtension) is not satisfied"))
    }
    return result
  }
}
