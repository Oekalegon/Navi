//
//  ArchiveViewerContent.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation

/// Returns the SF Symbol name for a frame or frameset based on its type and processing level.
func frameTypeSymbolName(type: String, level: String, isFrameset: Bool = false) -> String {
    let stacked = level.lowercased() == "stacked"
    if isFrameset {
        return type.lowercased() == "light" ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle"
    }
    switch type.lowercased() {
    case "light":
        return stacked ? "sparkles.rectangle.stack.fill" : "star.rectangle.fill"
    case "dark", "flat", "bias", "darkflat", "dark-flat":
        return stacked ? "rectangle.stack" : "rectangle"
    default:
        return "star.rectangle.fill"
    }
}

struct ArchiveRow: Identifiable {
    let id = UUID()
    var values: [String: String]
}

struct ArchiveViewerContent {
    var title: String
    var toolName: String
    var rawContent: String
    var columns: [String]
    var rows: [ArchiveRow]
    var isTable: Bool

    var iconName: String {
        if toolName.hasPrefix("archive_frameset") { return "rectangle.stack" }
        if toolName.hasPrefix("archive_") { return "rectangle" }
        return "archivebox"
    }

    // MARK: - Public entry point

    private static let hiddenColumns: Set<String> = ["id"]

    static func parse(toolName: String, content: String) -> ArchiveViewerContent {
        let title = Self.titleFor(toolName: toolName)

        // 1. Try JSON (future-proofing)
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let array = json as? [[String: Any]], !array.isEmpty {
                return makeJSONTable(title: title, toolName: toolName, rawContent: content, array: array).hidingColumns()
            }
            if let obj = json as? [String: Any] {
                for key in ["frames", "framesets", "results", "items", "data", "objects"] {
                    if let array = obj[key] as? [[String: Any]], !array.isEmpty {
                        return makeJSONTable(title: title, toolName: toolName, rawContent: content, array: array).hidingColumns()
                    }
                }
                return makeJSONTable(title: title, toolName: toolName, rawContent: content, array: [obj]).hidingColumns()
            }
        }

        // 2. Try fixed-width table (TextTable output: ─ separator line)
        if let parsed = parseFixedWidthTable(toolName: toolName, title: title, content: content) {
            return parsed.hidingColumns()
        }

        // 3. Try brace-line format:  { key: value, key: value }
        if let parsed = parseBraceLines(toolName: toolName, title: title, content: content) {
            return parsed.hidingColumns()
        }

        // 4. Fallback: raw text
        return ArchiveViewerContent(title: title, toolName: toolName, rawContent: content,
                                    columns: [], rows: [], isTable: false)
    }

    private func hidingColumns() -> ArchiveViewerContent {
        var copy = self
        copy.columns = columns.filter { !Self.hiddenColumns.contains($0) }
        return copy
    }

    // MARK: - Fixed-width table parser
    // Handles TextTable.render() output: header line, ─ separator, data rows.
    // Column positions are inferred from the ─ groups in the separator line.

    private static func parseFixedWidthTable(toolName: String, title: String, content: String) -> ArchiveViewerContent? {
        let lines = content.components(separatedBy: "\n")

        // Locate the ─ separator line
        guard let sepIdx = lines.firstIndex(where: { line in
            guard !line.isEmpty else { return false }
            let nonSpace = line.unicodeScalars.filter { $0 != " " }
            return !nonSpace.isEmpty && nonSpace.allSatisfy { $0 == "─".unicodeScalars.first! }
        }), sepIdx > 0 else { return nil }

        let sepLine = lines[sepIdx]
        let headerLine = lines[sepIdx - 1]

        // Derive column start positions and widths from the separator line.
        // Groups of ─ are separated by exactly two spaces.
        var columnStarts: [Int] = []
        var columnWidths: [Int] = []
        var charIdx = 0
        var idx = sepLine.startIndex

        while idx < sepLine.endIndex {
            if sepLine[idx] == "─" {
                let groupStart = charIdx
                var width = 0
                while idx < sepLine.endIndex && sepLine[idx] == "─" {
                    width += 1
                    charIdx += 1
                    idx = sepLine.index(after: idx)
                }
                columnStarts.append(groupStart)
                columnWidths.append(width)
                // Skip the two-space separator between columns
                for _ in 0..<2 where idx < sepLine.endIndex && sepLine[idx] == " " {
                    charIdx += 1
                    idx = sepLine.index(after: idx)
                }
            } else {
                charIdx += 1
                idx = sepLine.index(after: idx)
            }
        }

        guard !columnStarts.isEmpty else { return nil }

        // Extract column names from the header line using the same positions
        let columns = columnStarts.enumerated().map { (i, start) -> String in
            let end = i < columnStarts.count - 1 ? columnStarts[i + 1] - 2 : headerLine.count
            guard start < headerLine.count else { return "" }
            let s = headerLine.index(headerLine.startIndex, offsetBy: start)
            let e = headerLine.index(headerLine.startIndex, offsetBy: min(end, headerLine.count))
            return s < e ? String(headerLine[s..<e]).trimmingCharacters(in: .whitespaces) : ""
        }.filter { !$0.isEmpty }

        guard !columns.isEmpty else { return nil }

        // Parse data rows — skip summary lines by checking the first column for a UUID
        var rows: [ArchiveRow] = []
        for line in lines[(sepIdx + 1)...] {
            guard line.count > 30 else { continue }

            // Validate that the first column contains a UUID (possibly prefixed with "* ")
            let firstEnd = columnStarts.count > 1 ? columnStarts[1] - 2 : line.count
            let s0 = line.index(line.startIndex, offsetBy: columnStarts[0])
            let e0 = line.index(line.startIndex, offsetBy: min(firstEnd, line.count))
            let firstField = String(line[s0..<e0]).trimmingCharacters(in: .whitespaces)
            let uuidStr = firstField.hasPrefix("* ") ? String(firstField.dropFirst(2)) : firstField
            guard UUID(uuidString: uuidStr) != nil else { continue }

            var values: [String: String] = [:]
            for (i, col) in columns.enumerated() {
                let start = columnStarts[i]
                let end = i < columnStarts.count - 1 ? columnStarts[i + 1] - 2 : line.count
                guard start < line.count else { values[col] = ""; continue }
                let s = line.index(line.startIndex, offsetBy: start)
                let e = line.index(line.startIndex, offsetBy: min(end, line.count))
                values[col] = s < e ? String(line[s..<e]).trimmingCharacters(in: .whitespaces) : ""
            }
            rows.append(ArchiveRow(values: values))
        }

        guard !rows.isEmpty else { return nil }
        return ArchiveViewerContent(title: title, toolName: toolName, rawContent: content,
                                    columns: columns, rows: rows, isTable: true)
    }

    // MARK: - Brace-line parser
    // Handles:  { id: UUID, type: light, object: M51, filter: Hα, exp: 300s, ... }

    private static func parseBraceLines(toolName: String, title: String, content: String) -> ArchiveViewerContent? {
        let lines = content.components(separatedBy: "\n")
        let braceLines = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("{") && t.hasSuffix("}")
        }
        guard !braceLines.isEmpty else { return nil }

        let priorityKeys = ["id", "name", "object", "type", "filter", "level",
                            "frames", "exp", "stars", "fwhm", "ecc", "date", "added", "created", "file"]
        var orderedKeys: [String] = []
        var seenKeys = Set<String>()
        var rows: [ArchiveRow] = []

        for line in braceLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            let dict = parseKVString(inner)
            for key in dict.keys where seenKeys.insert(key).inserted {
                orderedKeys.append(key)
            }
            rows.append(ArchiveRow(values: dict))
        }

        var finalColumns: [String] = []
        var seenCols = Set<String>()
        for key in priorityKeys where orderedKeys.contains(key) && seenCols.insert(key).inserted {
            finalColumns.append(key)
        }
        for key in orderedKeys where seenCols.insert(key).inserted {
            finalColumns.append(key)
        }

        return ArchiveViewerContent(title: title, toolName: toolName, rawContent: content,
                                    columns: finalColumns, rows: rows, isTable: true)
    }

    // Parses "key: value, key: value" where values may contain spaces and colons (e.g. times).
    // A new key starts after ", " when followed by a word (no spaces) and ": ".
    private static func parseKVString(_ inner: String) -> [String: String] {
        var result: [String: String] = [:]
        var remaining = inner

        while !remaining.isEmpty {
            guard let sepRange = remaining.range(of: ": ") else { break }
            let key = String(remaining[..<sepRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            remaining = String(remaining[sepRange.upperBound...])

            var valueEnd = remaining.endIndex
            var searchFrom = remaining.startIndex
            while searchFrom < remaining.endIndex {
                guard let commaRange = remaining.range(of: ", ", range: searchFrom..<remaining.endIndex) else { break }
                let afterComma = remaining[commaRange.upperBound...]
                if let colonPos = afterComma.firstIndex(of: ":") {
                    let candidate = String(afterComma[..<colonPos])
                    if !candidate.contains(" ") && !candidate.isEmpty {
                        valueEnd = commaRange.lowerBound
                        break
                    }
                }
                searchFrom = commaRange.upperBound
            }

            let value = String(remaining[..<valueEnd]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
            remaining = valueEnd < remaining.endIndex
                ? String(remaining[remaining.index(valueEnd, offsetBy: 2)...])
                : ""
        }
        return result
    }

    // MARK: - JSON table builder

    private static func makeJSONTable(title: String, toolName: String, rawContent: String,
                                      array: [[String: Any]]) -> ArchiveViewerContent {
        var orderedColumns: [String] = []
        var seen = Set<String>()
        let priorityKeys = ["id", "name", "object", "target", "date", "type", "filter",
                            "quality", "fwhm", "snr", "stars", "exposure", "path", "filename"]
        for key in priorityKeys where array.contains(where: { $0[key] != nil }) && seen.insert(key).inserted {
            orderedColumns.append(key)
        }
        for row in array {
            for key in row.keys.sorted() where seen.insert(key).inserted {
                orderedColumns.append(key)
            }
        }
        let rows = array.map { rowDict -> ArchiveRow in
            ArchiveRow(values: Dictionary(uniqueKeysWithValues:
                orderedColumns.map { ($0, rowDict[$0].map { jsonValueString($0) } ?? "") }))
        }
        return ArchiveViewerContent(title: title, toolName: toolName, rawContent: rawContent,
                                    columns: orderedColumns, rows: rows, isTable: true)
    }

    private static func jsonValueString(_ val: Any) -> String {
        if let str = val as? String { return str }
        if let num = val as? NSNumber { return num.stringValue }
        if let nested = val as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: nested),
           let str = String(data: data, encoding: .utf8) { return str }
        if let arr = val as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: arr),
           let str = String(data: data, encoding: .utf8) { return str }
        return "\(val)"
    }

    // MARK: - Title

    private static func titleFor(toolName: String) -> String {
        switch toolName {
        case "archive_frameset_inspect": return "Frameset Inspection"
        case "archive_frameset_list":    return "Framesets"
        case "archive_frameset_quality": return "Quality Measurements"
        case "archive_frameset_get":     return "Frameset Members"
        case "archive_search":           return "Search Results"
        case "archive_find":             return "Search Results"
        case "archive_get":              return "Frame Details"
        case "archive_list_objects":     return "Objects"
        case "archive_recent":           return "Recent Frames"
        case "archive_stats":            return "Archive Statistics"
        case "archive_add":              return "Added Frame"
        case "archive_update_quality":   return "Quality Update"
        case "archive_reject":           return "Rejected Frame"
        case "archive_remove":           return "Removed Frame"
        default: return toolName.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
        }
    }
}
