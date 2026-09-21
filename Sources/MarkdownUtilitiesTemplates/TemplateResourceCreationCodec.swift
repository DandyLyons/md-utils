import MarkdownUtilitiesCore

/// Uses the shared renderer to create proposals without filesystem or server access.
public struct TemplateResourceCreationCodec: Sendable {
  public let codec: MarkdownResourceCodec
  public let template: ResourceCreationTemplate
  public let renderer: MarkdownTemplateRenderer

  public init(codec: MarkdownResourceCodec, template: ResourceCreationTemplate,
              renderer: MarkdownTemplateRenderer = .init()) {
    self.codec = codec
    self.template = template
    self.renderer = renderer
  }

  /// Identity/context and protected metadata are host supplied, not request fields.
  public func plan(
    input: MarkdownTemplateInput,
    identity: MarkdownRecordIdentity,
    context: MarkdownRecordContext = .init(),
    protectedFrontmatter: [String: JSONValue] = [:]
  ) async throws -> ResourceMutationProposal {
    try MarkdownResourceCodec.validatePath(context.path)
    try codec.validateFields((input.frontmatter ?? [:]).keys)
    var values = input.frontmatter ?? [:]
    for (key, value) in protectedFrontmatter {
      guard key == "$md-utils" || codec.configuration.protectedFields.contains(key) else {
        throw ResourceCodecError("creation", "Host metadata must be explicitly protected: \(key)")
      }
      values[key] = value
    }
    let rendered = try await renderer.render(template: template.template,
      input: MarkdownTemplateInput(frontmatter: input.frontmatter == nil && values.isEmpty ? nil : values,
        data: input.data), schema: template.inputSchema)
    return try ResourceMutationProposal(created: MarkdownRecord(identity: identity,
      content: rendered.source, context: context))
  }
}
