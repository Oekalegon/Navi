//
//  ArchiveViewerContent.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import AstrophotoArchiveKit

/// Returns the SF Symbol name for a frame or frameset based on its type and processing level.
func frameTypeSymbolName(type: String, level: String, isFrameset: Bool = false) -> String {
    let stacked = level.lowercased() == "stacked"
    if isFrameset {
        return "rectangle.grid.2x2"
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

struct ArchiveRow: Identifiable, Equatable {
    let id: UUID
    var values: [String: String]
    var children: [ArchiveRow]?

    init(id: UUID = UUID(), values: [String: String], children: [ArchiveRow]? = nil) {
        self.id = id
        self.values = values
        self.children = children
    }

    static func == (lhs: ArchiveRow, rhs: ArchiveRow) -> Bool {
        lhs.id == rhs.id && lhs.values == rhs.values
    }

    var isRejected: Bool { values["rejected"] == "true" }
    var isExcluded: Bool { values["excluded"] == "true" }
    var frameType: String { values["type"]?.lowercased() ?? "" }
    var processingLevel: ProcessingLevel? { ProcessingLevel(rawValue: values["level"]?.lowercased() ?? "") }
    var isSession: Bool { values["_kind"] == "session" }
    var isFrameset: Bool { !isSession && values["frames"].flatMap(Int.init) != nil }
}

struct ArchiveViewerContent: Equatable {
    var title: String
    var toolName: String
    var rawContent: String
    var columns: [String]
    var rows: [ArchiveRow]
    var isTable: Bool

    var iconName: String {
        if toolName.hasPrefix("archive_frameset") { return "rectangle.grid.2x2" }
        if toolName.hasPrefix("archive_") { return "rectangle" }
        return "archivebox"
    }

    // MARK: - Public entry point

    // "rejected" stays in the row values (the icon and reject toggle read it)
    // but is not shown as a column: the frame icon already conveys it.
    // "temp" is only used to construct display names for calibration frames.
    private static let hiddenColumns: Set<String> = ["id", "rejected", "temp", "session_id", "_kind", "matched"]

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
        copy.rows = rows.map { row in
            var row = row
            if let split = Self.splitFWHM(row.values["fwhm"]) {
                row.values["fwhm"] = split.px
                if let arcsec = split.arcsec { row.values["fwhm_arcsec"] = arcsec }
            }
            return row
        }
        return copy
    }

    // The MCP tools emit FWHM as a combined value: "3.20px/2.08\"" (or "3.20px"
    // when the pixel scale is unknown). Split it into plain numbers so the px
    // and arcsec columns sort and filter numerically. Plain numeric values
    // pass through untouched.
    private static func splitFWHM(_ value: String?) -> (px: String, arcsec: String?)? {
        guard let value, value.hasSuffix("\"") || value.hasSuffix("px") else { return nil }
        let parts = value.split(separator: "/")
        guard let pxPart = parts.first, pxPart.hasSuffix("px") else { return nil }
        let px = String(pxPart.dropLast(2))
        guard parts.count == 2, parts[1].hasSuffix("\"") else { return (px, nil) }
        return (px, String(parts[1].dropLast()))
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

    static func jsonValueString(_ val: Any) -> String {
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

    // MARK: - Session grouping

    /// Groups rows that carry a `session_id` into collapsible session-folder rows.
    /// Rows without a session ID (calibration frames, framesets) remain flat after the sessions.
    func groupedBySessions(sessionInfo: [String: SessionMeta] = [:]) -> ArchiveViewerContent {
        let withSession = rows.filter { row in
            guard let sid = row.values["session_id"] else { return false }
            guard !row.isFrameset && row.values["level"] == "raw" else { return false }
            if let meta = sessionInfo[sid], !meta.isValid { return false }
            return true
        }
        guard !withSession.isEmpty else { return self }
        let withoutSession = rows.filter { row in
            guard let sid = row.values["session_id"] else { return true }
            if row.isFrameset || row.values["level"] != "raw" { return true }
            if let meta = sessionInfo[sid], !meta.isValid { return true }
            return false
        }

        var order: [String] = []
        var grouped: [String: [ArchiveRow]] = [:]
        for row in withSession {
            let sid = row.values["session_id"]!
            if grouped[sid] == nil { order.append(sid) }
            grouped[sid, default: []].append(row)
        }

        let sessionRows: [ArchiveRow] = order.map { sid in
            let children = grouped[sid]!
            let matched = children.count
            let total = sessionInfo[sid]?.total ?? matched
            let objects = Array(
                Set(children.compactMap { $0.values["object"]?.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty })
            ).sorted().joined(separator: ", ")
            var values: [String: String] = [
                "_kind": "session",
                "session_id": sid,
                "matched": "\(matched)",
                "frames": "\(total)"
            ]
            if !objects.isEmpty { values["object"] = objects }
            if let sortDate = sessionInfo[sid]?.sortDate, !sortDate.isEmpty {
                values["date"] = sortDate
            }
            return ArchiveRow(id: UUID(uuidString: sid) ?? UUID(), values: values, children: children)
        }

        var copy = self
        copy.rows = sessionRows + withoutSession
        return copy
    }

    // MARK: - Filtering

    func filtered(by filter: ArchiveFilter) -> ArchiveViewerContent {
        guard filter.isActive else { return self }
        var copy = self
        copy.rows = filter.apply(to: rows)
        return copy
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

// MARK: - Filter categories

enum FilterCategory: String, CaseIterable, Hashable {
    case object    = "Object"
    case frameType = "Frame Type"
    case kind      = "Kind"
    case level     = "Processing Level"
    case date      = "Date"
    case quality   = "Quality"

    var icon: String {
        switch self {
        case .object:    return "star"
        case .frameType: return "square.stack"
        case .kind:      return "rectangle.on.rectangle"
        case .level:     return "slider.horizontal.3"
        case .date:      return "calendar"
        case .quality:   return "chart.bar"
        }
    }
}

// MARK: - Filter

struct ArchiveFilter: Equatable {
    var objects: Set<String>     = []
    var types: Set<String>       = []
    var kind: String?            = nil   // nil = both | "frames" | "framesets"
    var processingLevel: String? = nil   // nil = all  | "raw" | "calibrated" | "stacked" | "stretched"
    var minFWHM: String  = ""
    var maxFWHM: String  = ""
    var minSNR: String   = ""
    var maxSNR: String   = ""
    var minStars: String = ""
    var maxStars: String = ""
    var dateFrom: Date?  = nil
    var dateTo: Date?    = nil

    var isActive: Bool {
        !objects.isEmpty || !types.isEmpty ||
        kind != nil || processingLevel != nil ||
        !minFWHM.isEmpty || !maxFWHM.isEmpty ||
        !minSNR.isEmpty  || !maxSNR.isEmpty  ||
        !minStars.isEmpty || !maxStars.isEmpty ||
        dateFrom != nil || dateTo != nil
    }

    func isActive(for category: FilterCategory) -> Bool {
        switch category {
        case .object:    return !objects.isEmpty
        case .frameType: return !types.isEmpty
        case .kind:      return kind != nil
        case .level:     return processingLevel != nil
        case .date:      return dateFrom != nil || dateTo != nil
        case .quality:   return !minFWHM.isEmpty || !maxFWHM.isEmpty ||
                                !minSNR.isEmpty   || !maxSNR.isEmpty  ||
                                !minStars.isEmpty || !maxStars.isEmpty
        }
    }

    var activeCategories: [FilterCategory] {
        FilterCategory.allCases.filter { isActive(for: $0) }
    }

    func chipLabel(for category: FilterCategory) -> String {
        switch category {
        case .object:
            return objects.sorted().joined(separator: ", ")
        case .frameType:
            return types.sorted().map { $0.capitalized }.joined(separator: ", ")
        case .kind:
            switch kind {
            case "frames":    return "Frames"
            case "framesets": return "Framesets"
            default:          return ""
            }
        case .level:
            return processingLevel?.capitalized ?? ""
        case .date:
            let df = DateFormatter(); df.dateStyle = .short
            var parts: [String] = []
            if let d = dateFrom { parts.append("from \(df.string(from: d))") }
            if let d = dateTo   { parts.append("to \(df.string(from: d))") }
            return parts.joined(separator: " – ")
        case .quality:
            var parts: [String] = []
            if !minFWHM.isEmpty  { parts.append("FWHM ≥ \(minFWHM)") }
            if !maxFWHM.isEmpty  { parts.append("FWHM ≤ \(maxFWHM)") }
            if !minSNR.isEmpty   { parts.append("SNR ≥ \(minSNR)") }
            if !maxSNR.isEmpty   { parts.append("SNR ≤ \(maxSNR)") }
            if !minStars.isEmpty { parts.append("Stars ≥ \(minStars)") }
            if !maxStars.isEmpty { parts.append("Stars ≤ \(maxStars)") }
            return parts.joined(separator: ", ")
        }
    }

    mutating func clear(_ category: FilterCategory) {
        switch category {
        case .object:    objects = []
        case .frameType: types = []
        case .kind:      kind = nil
        case .level:     processingLevel = nil
        case .date:      dateFrom = nil; dateTo = nil
        case .quality:   minFWHM = ""; maxFWHM = ""; minSNR = ""; maxSNR = ""
                         minStars = ""; maxStars = ""
        }
    }

    func apply(to rows: [ArchiveRow]) -> [ArchiveRow] {
        rows.filter { row in
            if !objects.isEmpty, !objects.contains(row.values["object"] ?? "") { return false }
            if !types.isEmpty, !types.contains(row.frameType) { return false }
            if let k = kind {
                let isFrameset = row.values["frames"].flatMap(Int.init) != nil
                if k == "frames"    && isFrameset  { return false }
                if k == "framesets" && !isFrameset { return false }
            }
            if let lvl = processingLevel,
               row.processingLevel?.rawValue != lvl.lowercased() { return false }
            if let min = Double(minFWHM), let v = row.values["fwhm"].flatMap(Double.init), v < min { return false }
            if let max = Double(maxFWHM), let v = row.values["fwhm"].flatMap(Double.init), v > max { return false }
            if let min = Double(minSNR),  let v = row.values["snr"].flatMap(Double.init),  v < min { return false }
            if let max = Double(maxSNR),  let v = row.values["snr"].flatMap(Double.init),  v > max { return false }
            if let min = Int(minStars),   let v = row.values["stars"].flatMap(Int.init),   v < min { return false }
            if let max = Int(maxStars),   let v = row.values["stars"].flatMap(Int.init),   v > max { return false }
            let cal = Calendar.current
            if let from = dateFrom, let str = row.values["date"], let d = ArchiveFilter.parseDate(str),
               cal.startOfDay(for: d) < cal.startOfDay(for: from) { return false }
            if let to = dateTo, let str = row.values["date"], let d = ArchiveFilter.parseDate(str),
               cal.startOfDay(for: d) > cal.startOfDay(for: to) { return false }
            return true
        }
    }

    private static let dateFormatters: [DateFormatter] = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"].map {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = $0
        return f
    }

    static func parseDate(_ str: String) -> Date? {
        for f in dateFormatters { if let d = f.date(from: str) { return d } }
        return nil
    }

    static func from(toolName: String, arguments: [String: Any]) -> ArchiveFilter {
        var f = ArchiveFilter()
        if let obj = arguments["object_name"] as? String, !obj.isEmpty {
            f.objects = [obj]
        }
        if let types = arguments["frame_types"] as? [String], !types.isEmpty {
            f.types = Set(types.map { $0.lowercased() })
        }
        if let kind = arguments["kind"] as? String, kind == "frames" || kind == "framesets" {
            f.kind = kind
        }
        if let level = arguments["processing_level"] as? String, !level.isEmpty {
            f.processingLevel = level
        } else if let stacked = arguments["stacked"] as? Bool, stacked {
            f.processingLevel = "stacked"
        }
        return f
    }
}

// MARK: - ArchivedFrame display helpers

extension ArchivedFrame {
    /// Short display name: object · filter · capitalized processing level.
    /// Returns nil when all components are empty (e.g. unnamed calibration frames).
    var displayName: String? {
        let parts = [objectName ?? "", filter ?? "", processingLevel.rawValue.capitalized]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
