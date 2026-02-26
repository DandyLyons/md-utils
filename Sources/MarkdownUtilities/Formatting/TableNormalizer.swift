import Foundation

/// Normalizes GFM (GitHub-Flavored Markdown) table formatting by padding cells
/// so that columns align vertically.
public enum TableNormalizer {

    /// Normalizes table formatting in `content`.
    ///
    /// Detects GFM tables (rows containing `|`), pads each cell to the column's maximum
    /// width, and reconstructs aligned rows. Tables inside fenced code blocks are also
    /// normalized. Column widths are capped at `maxWidth` to prevent excessively wide rows;
    /// cells whose content already exceeds `maxWidth` are never truncated.
    ///
    /// - Parameters:
    ///   - content: The Markdown body text to normalize
    ///   - maxWidth: Maximum width (in characters) to which any column is padded. Defaults to `80`.
    /// - Returns: The normalized content string with padded table columns
    public static func normalize(_ content: String, maxWidth: Int = 80) -> String {
        var lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Detect start of a table block (non-empty line containing |)
            if !line.isEmpty && isTableLine(line) {
                // Collect all consecutive table lines
                var tableRange = i..<i
                var j = i
                while j < lines.count && !lines[j].isEmpty && isTableLine(lines[j]) {
                    j += 1
                }
                tableRange = i..<j

                // Normalize the table block
                let tableLines = Array(lines[tableRange])
                let normalized = normalizeTable(tableLines, maxWidth: maxWidth)
                lines.replaceSubrange(tableRange, with: normalized)

                // Advance past the table block
                i += normalized.count
            } else {
                i += 1
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    /// Returns true if a line is part of a GFM table (contains a `|` character).
    private static func isTableLine(_ line: String) -> Bool {
        line.contains("|")
    }

    /// Attempts to normalize a group of table lines.
    ///
    /// If the block does not have a valid separator row at index 1, the lines are
    /// returned unchanged.
    private static func normalizeTable(_ tableLines: [String], maxWidth: Int) -> [String] {
        guard tableLines.count >= 2 else { return tableLines }

        // Split each row into cells
        let rows = tableLines.map { splitCells(from: $0) }

        // Validate separator row (must be at index 1)
        guard isSeparatorRow(rows[1]) else { return tableLines }

        // Determine column count from header row
        let colCount = rows[0].count
        guard colCount > 0 else { return tableLines }

        // Pad all rows to the same column count
        let paddedRows = rows.map { row -> [String] in
            if row.count >= colCount { return row }
            return row + Array(repeating: "", count: colCount - row.count)
        }

        // Compute the maximum trimmed cell width per column, capped at maxWidth
        let widths = columnWidths(for: paddedRows, maxWidth: maxWidth)

        // Reconstruct each row
        return paddedRows.enumerated().map { (rowIndex, cells) in
            let isSep = rowIndex == 1
            return reconstructRow(cells: cells, widths: widths, isSeparator: isSep)
        }
    }

    /// Returns true if all cells in a row look like separator cells (`/^:?-+:?$/`).
    private static func isSeparatorRow(_ cells: [String]) -> Bool {
        guard !cells.isEmpty else { return false }
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !stripped.isEmpty, stripped.allSatisfy({ $0 == "-" }) else { return false }
        }
        return true
    }

    /// Splits a table row into trimmed cell strings by splitting on `|`
    /// and stripping the leading/trailing `|` delimiters.
    private static func splitCells(from line: String) -> [String] {
        var stripped = line
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove leading and trailing pipes
        if trimmed.hasPrefix("|") {
            stripped = String(trimmed.dropFirst())
        } else {
            stripped = trimmed
        }
        if stripped.hasSuffix("|") {
            stripped = String(stripped.dropLast())
        }

        return stripped.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Computes the maximum trimmed cell content width per column across all rows,
    /// capped at `maxWidth`. Individual cells wider than `maxWidth` are still rendered
    /// at their natural content width (see `reconstructRow`).
    private static func columnWidths(for rows: [[String]], maxWidth: Int) -> [Int] {
        guard let colCount = rows.map(\.count).max(), colCount > 0 else { return [] }

        var widths = Array(repeating: 0, count: colCount)
        for row in rows {
            for (col, cell) in row.enumerated() where col < colCount {
                let cellWidth: Int
                // For separator rows, measure the dashes without colons
                let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                if !stripped.isEmpty && stripped.allSatisfy({ $0 == "-" }) {
                    // Separator cell: width is at least 3 (---), include colons in measurement
                    cellWidth = max(cell.count, 3)
                } else {
                    cellWidth = cell.count
                }
                widths[col] = max(widths[col], cellWidth)
            }
        }
        return widths.map { min($0, maxWidth) }
    }

    /// Reconstructs a single table row with cells padded to the given column widths.
    private static func reconstructRow(cells: [String], widths: [Int], isSeparator: Bool) -> String {
        let paddedCells = cells.enumerated().map { (col, cell) -> String in
            let width = col < widths.count ? widths[col] : cell.count
            if isSeparator {
                return paddedSeparatorCell(cell, width: width)
            } else {
                return cell.padding(toLength: max(width, cell.count), withPad: " ", startingAt: 0)
            }
        }
        return "| " + paddedCells.joined(separator: " | ") + " |"
    }

    /// Pads a separator cell to `width`, preserving leading/trailing alignment colons.
    private static func paddedSeparatorCell(_ cell: String, width: Int) -> String {
        let hasLeadingColon = cell.hasPrefix(":")
        let hasTrailingColon = cell.hasSuffix(":")

        let dashCount: Int
        if hasLeadingColon && hasTrailingColon {
            dashCount = max(width - 2, 1)
        } else if hasLeadingColon || hasTrailingColon {
            dashCount = max(width - 1, 1)
        } else {
            dashCount = max(width, 3)
        }

        let dashes = String(repeating: "-", count: dashCount)
        if hasLeadingColon && hasTrailingColon {
            return ":\(dashes):"
        } else if hasLeadingColon {
            return ":\(dashes)"
        } else if hasTrailingColon {
            return "\(dashes):"
        } else {
            return dashes
        }
    }
}
