import Foundation

/// Project-level named syntaxes and extension mappings for wrapped frontmatter.
public struct WrappedFrontMatterProjectConfiguration: Equatable, Sendable {
  public var useBuiltInPresets: Bool
  public var syntaxes: [String: WrappedFrontMatterSyntax]
  public var extensionMappings: [String: String]

  public init(
    useBuiltInPresets: Bool = true,
    syntaxes: [String: WrappedFrontMatterSyntax] = [:],
    extensionMappings: [String: String] = [:]
  ) throws {
    let builtInNames = Set(WrappedFrontMatterPreset.allCases.map(\.rawValue))
    for name in syntaxes.keys {
      guard name.isEmpty == false else {
        throw WrappedFrontMatterConfigurationError.emptySyntaxName
      }
      guard builtInNames.contains(name) == false else {
        throw WrappedFrontMatterConfigurationError.reservedSyntaxName(name)
      }
    }

    var normalizedMappings: [String: String] = [:]
    for (pathExtension, syntaxName) in extensionMappings {
      let normalizedExtension = Self.normalize(pathExtension)
      guard normalizedExtension.isEmpty == false else {
        throw WrappedFrontMatterConfigurationError.emptyExtension
      }
      guard syntaxName.isEmpty == false else {
        throw WrappedFrontMatterConfigurationError.emptyMappedSyntax(pathExtension)
      }
      guard syntaxes[syntaxName] != nil || builtInNames.contains(syntaxName) else {
        throw WrappedFrontMatterConfigurationError.unknownSyntax(syntaxName)
      }
      guard normalizedMappings[normalizedExtension] == nil else {
        throw WrappedFrontMatterConfigurationError.duplicateExtension(normalizedExtension)
      }
      normalizedMappings[normalizedExtension] = syntaxName
    }

    self.useBuiltInPresets = useBuiltInPresets
    self.syntaxes = syntaxes
    self.extensionMappings = normalizedMappings
  }

  /// Resolves a built-in or project-defined syntax by name.
  public func syntax(named name: String) -> WrappedFrontMatterSyntax? {
    if let custom = syntaxes[name] {
      return custom
    }
    return WrappedFrontMatterPreset(rawValue: name)?.syntax
  }

  /// Resolves the project mapping first, then a built-in extension preset when enabled.
  public func inferredSyntax(forExtension pathExtension: String) -> WrappedFrontMatterSyntax? {
    let normalizedExtension = Self.normalize(pathExtension)
    if let name = extensionMappings[normalizedExtension] {
      return syntax(named: name)
    }
    guard useBuiltInPresets,
      let preset = WrappedFrontMatterPreset.inferred(forExtension: normalizedExtension)
    else {
      return nil
    }
    return preset.syntax
  }

  private static func normalize(_ pathExtension: String) -> String {
    pathExtension
      .lowercased()
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
  }
}

/// Invalid project-level wrapped-frontmatter configuration.
public enum WrappedFrontMatterConfigurationError: Error, Equatable, LocalizedError {
  case emptySyntaxName
  case reservedSyntaxName(String)
  case emptyExtension
  case emptyMappedSyntax(String)
  case unknownSyntax(String)
  case duplicateExtension(String)

  public var errorDescription: String? {
    switch self {
    case .emptySyntaxName:
      return "A wrapped frontmatter syntax name cannot be empty"
    case .reservedSyntaxName(let name):
      return "A project syntax cannot replace the built-in syntax \"\(name)\""
    case .emptyExtension:
      return "A wrapped frontmatter extension mapping cannot use an empty extension"
    case .emptyMappedSyntax(let pathExtension):
      return "The wrapped frontmatter mapping for \"\(pathExtension)\" requires a syntax name"
    case .unknownSyntax(let name):
      return "Unknown wrapped frontmatter syntax \"\(name)\""
    case .duplicateExtension(let pathExtension):
      return "Duplicate wrapped frontmatter extension mapping for \"\(pathExtension)\""
    }
  }
}
