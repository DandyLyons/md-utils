/// Selects source escaping and compatibility rules, independently of discovery
/// versus whole-value parsing. Callers must retain the context when reparsing.
public enum WikilinkParsingContext: Sendable, Equatable, CaseIterable {
  /// Decoded metadata or ordinary link text. An escaped pipe is a literal target pipe.
  case standard
  /// A host-selected Markdown table cell. An escaped pipe separates the alias.
  /// This does not detect tables or select which Markdown regions contain links.
  case markdownTable
  /// Historical permissive discovery, including empty anchors and multiline links.
  /// Escaped pipes retain their historical literal-target interpretation.
  case legacy
}
