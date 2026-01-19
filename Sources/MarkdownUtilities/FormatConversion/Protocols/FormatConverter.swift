import Foundation
import MarkdownSyntax

/// A protocol for converting Markdown AST to other formats.
///
/// Types conforming to this protocol can transform a Markdown document's
/// Abstract Syntax Tree (AST) into different output formats such as plain text,
/// HTML, RTF, or other structured formats.
///
/// Example usage:
/// ```swift
/// struct PlainTextConverter: MarkdownConverter {
///     typealias Output = String
///     typealias Options = PlainTextOptions
///
///     func convert(from root: Root, options: Options) async throws -> String {
///         // Implementation here
///     }
/// }
/// ```
public protocol MarkdownConverter: Sendable {
    /// The output type produced by this converter
    associatedtype Output

    /// The options type used to configure conversion
    associatedtype Options: ConversionOptions

    /// Converts a Markdown AST root node to the target format
    ///
    /// - Parameters:
    ///   - root: The root node of the Markdown AST
    ///   - options: Configuration options for the conversion
    /// - Returns: The converted output in the target format
    /// - Throws: Conversion errors if the operation fails
    func convert(from root: Root, options: Options) async throws -> Output
}

/// A protocol for generating Markdown from other formats.
///
/// Types conforming to this protocol can transform content from various formats
/// back into Markdown format. This is the inverse operation of `MarkdownConverter`.
///
/// Example usage:
/// ```swift
/// struct HTMLToMarkdownGenerator: MarkdownGenerator {
///     typealias Input = String
///     typealias Options = HTMLConversionOptions
///
///     func generate(from input: String, options: Options) async throws -> String {
///         // Implementation here
///     }
/// }
/// ```
public protocol MarkdownGenerator: Sendable {
    /// The input type this generator accepts
    associatedtype Input

    /// The options type used to configure generation
    associatedtype Options: ConversionOptions

    /// Generates Markdown content from the input format
    ///
    /// - Parameters:
    ///   - input: The content to convert to Markdown
    ///   - options: Configuration options for the generation
    /// - Returns: The generated Markdown content
    /// - Throws: Generation errors if the operation fails
    func generate(from input: Input, options: Options) async throws -> String
}
