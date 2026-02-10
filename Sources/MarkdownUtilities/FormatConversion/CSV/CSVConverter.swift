import Foundation
import PathKit
import Yams

/// Converts Markdown documents with YAML frontmatter to CSV format.
///
/// This converter takes a collection of Markdown documents and their file paths,
/// extracts their frontmatter keys, and generates a CSV with one row per document.
/// Each frontmatter key becomes a column, and metadata columns can be included.
public struct CSVConverter {

    /// Initialize a new CSV converter
    public init() {}


    /// Convert multiple Markdown documents to CSV format.
    ///
    /// The resulting CSV will have:
    /// 1. Metadata columns (if specified in options) - e.g., $fileName, $relPath
    /// 2. Body column (if includeBody is true) - $body
    /// 3. Frontmatter columns (alphabetically sorted) - all keys found across all documents
    ///
    /// - Parameters:
    ///   - documents: Array of tuples containing file paths and their parsed documents
    ///   - options: Configuration options for the conversion
    /// - Returns: A CSV string with header and data rows
    /// - Throws: If CSV generation fails
    public func convert(
        documents: [(path: String, document: MarkdownDocument)],
        options: CSVOptions
    ) throws -> String {
        guard !documents.isEmpty else {
            // Return just headers for empty input
            let schema = buildColumnSchema([], options: options)
            return generateHeaderRow(schema)
        }

        // Collect all frontmatter keys across all documents
        let allKeys = collectAllKeys(documents)

        // Build ordered column schema
        let schema = buildColumnSchema(allKeys, options: options)

        // Generate CSV
        var lines: [String] = []

        // Header row
        lines.append(generateHeaderRow(schema))

        // Data rows
        for (path, document) in documents {
            let row = try generateDataRow(
                document: document,
                path: path,
                schema: schema,
                options: options
            )
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Column Schema Building

    /// Column definition for CSV generation
    struct CSVColumn {
        let name: String
        let type: ColumnType

        enum ColumnType {
            case metadata(CSVOptions.MetadataColumn)
            case body
            case frontmatter(key: String)
        }
    }

    /// Collect all unique frontmatter keys from all documents
    func collectAllKeys(_ documents: [(path: String, document: MarkdownDocument)]) -> [String] {
        var keySet = Set<String>()

        for (_, document) in documents {
            for (key, _) in document.frontMatter {
                if case .scalar(let scalar) = key {
                    keySet.insert(scalar.string)
                }
            }
        }

        return Array(keySet).sorted()
    }

    /// Build the ordered column schema for CSV generation
    ///
    /// Column order:
    /// 1. Metadata columns (in user-specified order via Set iteration, but deterministic)
    /// 2. Body column (if enabled)
    /// 3. Frontmatter columns (alphabetically sorted)
    func buildColumnSchema(_ frontmatterKeys: [String], options: CSVOptions) -> [CSVColumn] {
        var columns: [CSVColumn] = []

        // 1. Metadata columns (sorted for deterministic ordering)
        let sortedMetadataColumns = options.metadataColumns.sorted { $0.rawValue < $1.rawValue }
        for metaCol in sortedMetadataColumns {
            columns.append(CSVColumn(name: metaCol.rawValue, type: .metadata(metaCol)))
        }

        // 2. Body column
        if options.includeBody {
            columns.append(CSVColumn(name: "$body", type: .body))
        }

        // 3. Frontmatter columns (already sorted)
        for key in frontmatterKeys {
            columns.append(CSVColumn(name: key, type: .frontmatter(key: key)))
        }

        return columns
    }

    // MARK: - CSV Generation

    /// Generate the CSV header row
    func generateHeaderRow(_ schema: [CSVColumn]) -> String {
        let headers = schema.map { escapeCSVField($0.name) }
        return headers.joined(separator: ",")
    }

    /// Generate a CSV data row for a document
    func generateDataRow(
        document: MarkdownDocument,
        path: String,
        schema: [CSVColumn],
        options: CSVOptions
    ) throws -> String {
        var fields: [String] = []

        for column in schema {
            let value: String

            switch column.type {
            case .metadata(let metaCol):
                value = generateMetadataValue(metaCol, path: path, options: options)

            case .body:
                value = document.body

            case .frontmatter(let key):
                value = try getFrontmatterValue(document: document, key: key)
            }

            fields.append(escapeCSVField(value))
        }

        return fields.joined(separator: ",")
    }

    /// Generate a metadata column value
    func generateMetadataValue(
        _ column: CSVOptions.MetadataColumn,
        path: String,
        options: CSVOptions
    ) -> String {
        let pathObj = Path(path)

        switch column {
        case .fileName:
            return pathObj.lastComponent

        case .relPath:
            if let baseDir = options.baseDirectory {
                let basePath = Path(baseDir).absolute().string
                let absolutePath = pathObj.absolute().string

                // If path starts with base directory, strip the prefix
                if absolutePath.hasPrefix(basePath) {
                    var relative = String(absolutePath.dropFirst(basePath.count))
                    // Remove leading slash if present
                    if relative.hasPrefix("/") {
                        relative = String(relative.dropFirst())
                    }
                    return relative.isEmpty ? path : relative
                }
            }
            // Fallback to path as-is if no base directory or path not under base
            return path

        case .absPath:
            return pathObj.absolute().string
        }
    }

    /// Get a frontmatter value for a specific key
    func getFrontmatterValue(document: MarkdownDocument, key: String) throws -> String {
        // Look up the key in frontmatter
        let keyNode = Yams.Node.scalar(.init(key))

        guard let valueNode = document.frontMatter[keyNode] else {
            // Key not present in this document
            return ""
        }

        // Convert the value to a string
        return try frontmatterValueToString(valueNode)
    }

    /// Convert a Yams.Node to a string representation
    ///
    /// - Scalars: Return as-is
    /// - Complex types (arrays, objects): Serialize to JSON
    func frontmatterValueToString(_ node: Yams.Node) throws -> String {
        switch node {
        case .scalar(let scalar):
            return scalar.string

        case .sequence, .mapping:
            // Serialize complex types as JSON (compact, no pretty printing)
            return try YAMLConversion.nodeToJSON(node, options: [])

        case .alias:
            // YAML aliases should be resolved by the parser, but if we encounter one,
            // serialize it as JSON for safety
            return try YAMLConversion.nodeToJSON(node, options: [])
        }
    }

    // MARK: - CSV Escaping

    /// Escape a CSV field according to RFC 4180
    ///
    /// Fields containing commas, quotes, or newlines must be wrapped in double quotes.
    /// Double quotes are escaped by doubling them.
    func escapeCSVField(_ field: String) -> String {
        // If field contains comma, quote, or newline, wrap in quotes
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            // Escape quotes by doubling them
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
