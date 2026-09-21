import Foundation
import JSONSchema
import MarkdownUtilitiesCore
import Parsing
import Yams

/// Explicit frontmatter and body data for a single generated document.
///
/// Omitted frontmatter produces no block; an empty object produces an empty YAML mapping.
/// The optional input schema validates this complete envelope.
public struct MarkdownTemplateInput: Codable, Equatable, Sendable {
  public var frontmatter: [String: JSONValue]?
  public var data: JSONValue

  public init(frontmatter: [String: JSONValue]? = nil, data: JSONValue) {
    self.frontmatter = frontmatter
    self.data = data
  }

  private enum CodingKeys: String, CodingKey { case frontmatter, data }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Explicit null is not an object. Only omission means no frontmatter.
    frontmatter = container.contains(.frontmatter)
      ? try container.decode([String: JSONValue].self, forKey: .frontmatter) : nil
    data = try container.decode(JSONValue.self, forKey: .data)
  }

  var context: [String: Any] {
    var result = ["data": data.foundationValue]
    if let frontmatter { result["frontmatter"] = frontmatter.mapValues(\.foundationValue) }
    return result
  }
}

/// Byte-size guardrails, not an execution sandbox or peak-memory guarantee.
public struct MarkdownTemplateLimits: Sendable {
  public var templateBytes: Int
  public var inputBytes: Int
  public var outputBytes: Int

  public init(
    templateBytes: Int = 16 * 1_024 * 1_024,
    inputBytes: Int = 64 * 1_024 * 1_024,
    outputBytes: Int = 64 * 1_024 * 1_024
  ) {
    self.templateBytes = templateBytes
    self.inputBytes = inputBytes
    self.outputBytes = outputBytes
  }
}

/// An engine-independent rendering failure suitable for CLI or server diagnostics.
public struct MarkdownTemplateError: Error, LocalizedError, Sendable {
  public enum Stage: String, Sendable {
    case input, schema, template, frontmatter, output
  }
  public let stage: Stage
  public let message: String
  public var errorDescription: String? { "Template \(stage.rawValue): \(message)" }

  public init(stage: Stage, message: String) {
    self.stage = stage
    self.message = message
  }
}

/// Validated complete source and the document parsed from those same bytes.
public struct RenderedMarkdownTemplate: Sendable {
  public let source: String
  public let document: MarkdownDocument
}

/// Renders a self-contained Stencil body and serializes explicit YAML frontmatter.
///
/// This service performs no filesystem access or persistence. Server callers must supply
/// administrator-configured templates. Resource codecs remain responsible for record
/// identity, type/rule reassessment, and persistence.
public struct MarkdownTemplateRenderer: Sendable {
  public let limits: MarkdownTemplateLimits

  public init(limits: MarkdownTemplateLimits = .init()) {
    self.limits = limits
  }

  public func render(
    template: String,
    input: MarkdownTemplateInput,
    schema: JSONValue? = nil
  ) async throws -> RenderedMarkdownTemplate {
    guard limits.templateBytes > 0, limits.inputBytes > 0, limits.outputBytes > 0 else {
      throw MarkdownTemplateError(stage: .input, message: "Byte limits must be positive.")
    }
    try checkSize(template.utf8.count, limit: limits.templateBytes, stage: .template)
    do {
      // JSONEncoder also rejects non-finite numbers supplied by library callers.
      try checkSize(JSONEncoder().encode(input).count, limit: limits.inputBytes, stage: .input)
    } catch let error as MarkdownTemplateError { throw error }
    catch { throw MarkdownTemplateError(stage: .input, message: String(describing: error)) }

    if let schema {
      do {
        let validation: ValidationResult
        switch schema {
        case .object(let object):
          validation = try JSONSchema.validate(input.context, schema: object.mapValues(\.foundationValue))
        case .boolean(let boolean):
          validation = try JSONSchema.validate(input.context, schema: boolean)
        default:
          throw MarkdownTemplateError(stage: .schema, message: "Expected an object or boolean schema.")
        }
        guard validation.valid else {
          let messages = (validation.errors ?? []).map {
            "\($0.instanceLocation.path): \($0.description)"
          }.sorted()
          throw MarkdownTemplateError(stage: .schema, message: messages.isEmpty
            ? "Input does not match the schema." : messages.joined(separator: "\n"))
        }
      } catch let error as MarkdownTemplateError { throw error }
      catch { throw MarkdownTemplateError(stage: .schema, message: String(describing: error)) }
    }

    try rejectFrontmatter(in: template)
    let body = try StencilRenderingAdapter.render(template, context: input.context)
    try checkSize(body.utf8.count, limit: limits.outputBytes, stage: .output)
    // Values and conditionals can introduce a block even when the source had none.
    try rejectFrontmatter(in: body)
    let source: String
    if let frontmatter = input.frontmatter {
      do {
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = true
        let yaml = try encoder.encode(frontmatter)
        source = "---\n" + yaml + (yaml.hasSuffix("\n") ? "" : "\n") + "---\n" + body
      } catch { throw MarkdownTemplateError(stage: .frontmatter, message: String(describing: error)) }
    } else {
      source = body
    }
    try checkSize(source.utf8.count, limit: limits.outputBytes, stage: .output)
    do {
      let document = try MarkdownDocument(content: source)
      guard document.body == body,
            document.frontMatterFormat == (input.frontmatter == nil ? nil : .yaml) else {
        throw MarkdownTemplateError(stage: .output, message: "Generated document boundaries changed during parsing.")
      }
      _ = try await document.parseAST()
      return RenderedMarkdownTemplate(source: source, document: document)
    } catch let error as MarkdownTemplateError { throw error }
    catch { throw MarkdownTemplateError(stage: .output, message: String(describing: error)) }
  }

  private func checkSize(_ size: Int, limit: Int, stage: MarkdownTemplateError.Stage) throws {
    guard size <= limit else {
      throw MarkdownTemplateError(stage: stage, message: "Size \(size) bytes exceeds the \(limit)-byte limit.")
    }
  }

  private func rejectFrontmatter(in text: String) throws {
    let opening = Parse(input: Substring.self) {
      Skip { Optionally { "\u{FEFF}" } }
      OneOf { "---"; "+++" }
      OneOf { "\r\n"; "\n"; End() }
    }
    var remaining = text[...]
    if (try? opening.parse(&remaining)) != nil {
      throw MarkdownTemplateError(stage: .frontmatter,
        message: "Body templates must not start with a YAML/TOML frontmatter delimiter. Supply the frontmatter object instead.")
    }
  }
}
