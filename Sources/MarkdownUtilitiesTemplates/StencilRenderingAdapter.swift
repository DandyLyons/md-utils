import Foundation
import Stencil

/// The only engine-specific boundary. No loader means no included host resources.
enum StencilRenderingAdapter {
  static func render(_ template: String, context: [String: Any]) throws -> String {
    do {
      return try Environment(loader: nil, trimBehaviour: .nothing)
        .renderTemplate(string: template, context: context.mapValues(presentationValue))
    } catch {
      throw MarkdownTemplateError(stage: .template, message: String(describing: error))
    }
  }

  // Normalize only the engine's presentation copy. An empty string is false in
  // Stencil and prints nothing, while map preserves null array entries and keys.
  private static func presentationValue(_ value: Any) -> Any {
    if value is NSNull { return "" }
    if let object = value as? [String: Any] { return object.mapValues(presentationValue) }
    if let array = value as? [Any] { return array.map(presentationValue) }
    return value
  }
}
