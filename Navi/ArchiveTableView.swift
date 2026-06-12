//
//  ArchiveTableView.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI
import AppKit

struct ArchiveTableView: View {
    let content: ArchiveViewerContent
    var totalRows: Int? = nil
    let columnSettings: ArchiveColumnSettings
    @Binding var selectionID: ArchiveRow.ID?
    // isNewSelection distinguishes a user selecting a row (true) from the
    // selected row's values changing in place, e.g. a reject toggle (false) —
    // callers must not re-route the frame to viewers in the latter case.
    var onRowSelected: ((ArchiveRow?, _ isNewSelection: Bool) -> Void)? = nil
    var onRowDoubleClicked: ((ArchiveRow) -> Void)? = nil
    @State private var sortOrder: [ColumnComparator] = []
    @State private var lastTapRowID: ArchiveRow.ID? = nil
    @State private var lastTapTime: Date = .distantPast
    @State private var expandedFramesets: Set<ArchiveRow.ID> = []
    @State private var framesetChildren: [ArchiveRow.ID: [ArchiveRow]] = [:]
    @State private var loadingFramesets: Set<ArchiveRow.ID> = []

    private var displayColumns: [String] { columnSettings.visibleColumns(from: content.columns) }

    private var sortedRows: [ArchiveRow] {
        sortOrder.isEmpty ? content.rows : content.rows.sorted(using: sortOrder)
    }

    private var childRowIDs: Set<ArchiveRow.ID> {
        Set(framesetChildren.values.flatMap { $0 }.map { $0.id })
    }

    private var displayedRows: [ArchiveRow] {
        var result: [ArchiveRow] = []
        for row in sortedRows {
            result.append(row)
            if expandedFramesets.contains(row.id) {
                result += framesetChildren[row.id] ?? []
            }
        }
        return result
    }

    private func cellTapped(_ row: ArchiveRow) {
        let now = Date()
        if lastTapRowID == row.id, now.timeIntervalSince(lastTapTime) < 0.4 {
            onRowDoubleClicked?(row)
            lastTapRowID = nil
        } else {
            lastTapRowID = row.id
            lastTapTime = now
        }
    }

    private func toggleExpand(_ row: ArchiveRow) {
        if expandedFramesets.contains(row.id) {
            expandedFramesets.remove(row.id)
        } else {
            expandedFramesets.insert(row.id)
            if framesetChildren[row.id] == nil {
                Task { await loadChildren(for: row) }
            }
        }
    }

    private func loadChildren(for row: ArchiveRow) async {
        guard let idStr = row.values["id"], !idStr.isEmpty else { return }
        loadingFramesets.insert(row.id)
        do {
            let result = try await ArchiveManager.shared.callTool(
                name: "archive_frameset_get",
                arguments: ["id": idStr]
            )
            let parsed = ArchiveViewerContent.parse(toolName: "archive_frameset_get", content: result)
            framesetChildren[row.id] = parsed.rows
        } catch {}
        loadingFramesets.remove(row.id)
    }

    var body: some View {
        let total = totalRows ?? content.rows.count
        let count = content.rows.count
        VStack(spacing: 0) {
            Table(displayedRows, selection: $selectionID, sortOrder: $sortOrder) {
                TableColumn("Name", sortUsing: ColumnComparator(key: "name")) { row in
                    let isFrameset = row.values["frames"].flatMap(Int.init) != nil
                    let isChild = childRowIDs.contains(row.id)
                    let cell = ArchiveNameCell(
                        row: row,
                        isFrameset: isFrameset,
                        isChild: isChild,
                        isExpanded: expandedFramesets.contains(row.id),
                        isLoading: loadingFramesets.contains(row.id),
                        onToggle: { toggleExpand(row) }
                    )
                    if isFrameset {
                        cell.simultaneousGesture(TapGesture().onEnded { cellTapped(row) })
                    } else {
                        cell
                    }
                }
                .width(min: 120, ideal: 200)

                TableColumnForEach(displayColumns.filter { $0 != "name" }, id: \.self) { col in
                    TableColumn(Self.columnTitle(for: col), sortUsing: ColumnComparator(key: col)) { row in
                        Text(Self.formatted(row.values[col] ?? "", column: col))
                            .font(Self.cellFont(for: col))
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: Self.columnAlignment(for: col))
                    }
                    .width(min: Self.minWidth(for: col), ideal: Self.idealWidth(for: col))
                }
            }
            .onChange(of: selectionID) { _, newID in
                // Defer so NSTableView finishes reconciling the new selection before
                // any parent re-render triggered by onRowSelected can interfere.
                let row = newID.flatMap { id in displayedRows.first { $0.id == id } }
                let callback = onRowSelected
                Task { @MainActor in callback?(row, true) }
            }
            .onChange(of: displayedRows.first(where: { $0.id == selectionID })?.values) { _, _ in
                guard let id = selectionID, let row = displayedRows.first(where: { $0.id == id }) else { return }
                let callback = onRowSelected
                Task { @MainActor in callback?(row, false) }
            }
            .onChange(of: content.toolName) { _, _ in
                expandedFramesets.removeAll()
                framesetChildren.removeAll()
                loadingFramesets.removeAll()
            }

            Divider()

            ArchiveStatusBar(rowCount: count, totalRowCount: total)
        }
    }

    private static func columnTitle(for column: String) -> String {
        ArchiveColumnSettings.groups
            .flatMap { $0.entries }
            .first { $0.key == column }
            .map { $0.header ?? $0.label } ?? column.capitalized
    }

    private static func formatted(_ value: String, column: String) -> String {
        switch column {
        case "fwhm":
            if let d = ColumnComparator.numericValue(value) { return String(format: "%.1f px", d) }
        case "fwhm_arcsec":
            if let d = ColumnComparator.numericValue(value) { return String(format: "%.2f\"", d) }
        case "ecc":
            if let d = Double(value) { return String(format: "%.2f", d) }
        case "exp":
            if let d = ColumnComparator.numericValue(value) { return String(format: "%g s", d) }
        case "type", "level":
            return value.capitalized
        default: break
        }
        return value
    }

    private static func columnAlignment(for column: String) -> Alignment {
        switch column {
        case "fwhm", "fwhm_arcsec", "ecc", "snr", "exp", "stars", "frames": return .trailing
        default: return .leading
        }
    }

    // Monospaced digits keep numbers and dates vertically aligned across rows.
    private static func cellFont(for column: String) -> Font {
        switch column {
        case "fwhm", "fwhm_arcsec", "ecc", "snr", "exp", "stars", "frames", "date", "added", "created":
            return .system(size: 11).monospacedDigit()
        default:
            return .system(size: 11)
        }
    }

    private static func idealWidth(for column: String) -> CGFloat {
        switch column {
        case "type", "level", "filter":       return 70
        case "diagnostic":                    return 140
        case "exp", "fwhm", "fwhm_arcsec", "ecc", "frames": return 60
        case "stars":                         return 56
        case "date":                          return 165
        case "added", "created":              return 150
        case "object", "target":              return 110
        case "name":                          return 160
        case "camera":                        return 130
        case "file", "path":                  return 260
        default:                              return 100
        }
    }

    private static func minWidth(for column: String) -> CGFloat {
        switch column {
        case "type", "level", "filter":       return 50
        case "diagnostic":                    return 70
        case "exp", "fwhm", "fwhm_arcsec", "ecc", "frames": return 44
        case "stars":                         return 44
        case "date":                          return 110
        case "added", "created":              return 90
        case "object", "target":              return 60
        case "name":                          return 80
        case "camera":                        return 70
        case "file", "path":                  return 100
        default:                              return 50
        }
    }
}

private struct FrameTypeIcon: View {
    let row: ArchiveRow

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.0, palette.1)
            .font(.system(size: 11, weight: .regular))
    }

    private var isFrameset: Bool { row.values["frames"].flatMap(Int.init) != nil }

    private var symbolName: String {
        if row.values["rejected"] == "true" || row.values["excluded"] == "true" {
            return "xmark.diamond.fill"
        }
        let type  = row.values["type"]?.lowercased()  ?? ""
        let level = row.values["level"]?.lowercased() ?? "raw"
        return frameTypeSymbolName(type: type, level: level, isFrameset: isFrameset)
    }

    private var palette: (Color, Color) {
        if row.values["rejected"] == "true" { return (.white, .red) }
        if row.values["excluded"] == "true" { return (Color(NSColor.black), .yellow) }
        if isFrameset {
            return (Color(NSColor.secondaryLabelColor), Color(NSColor.secondaryLabelColor))
        }
        let type = row.values["type"]?.lowercased() ?? ""
        if type == "light" {
            return (Color(NSColor.textBackgroundColor), Color(NSColor.labelColor))
        }
        return (Color(NSColor.secondaryLabelColor), Color(NSColor.secondaryLabelColor))
    }
}

private struct ArchiveNameCell: View {
    let row: ArchiveRow
    let isFrameset: Bool
    let isChild: Bool
    let isExpanded: Bool
    let isLoading: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isFrameset {
                Group {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded { onToggle() })
                    }
                }
            } else {
                Spacer().frame(width: isChild ? 28 : 14)
            }
            FrameTypeIcon(row: row)
            Text(displayName)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var displayName: String {
        let name = (row.values["name"] ?? "").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let level = (row.values["level"] ?? "").capitalized
        let parts = [row.values["object"] ?? "", row.values["filter"] ?? "", level]
            .filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}

struct ColumnComparator: SortComparator {
    typealias Compared = ArchiveRow
    let key: String
    var order: SortOrder = .forward

    // Numeric value of a cell, ignoring a trailing unit (e.g. "300s" → 300).
    // The suffix must be letters only, so date strings like "2026-06-11"
    // don't get truncated to their leading number.
    static func numericValue(_ value: String) -> Double? {
        if let d = Double(value) { return d }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let unitStart = trimmed.firstIndex(where: { $0.isLetter }) else { return nil }
        guard trimmed[unitStart...].allSatisfy({ $0.isLetter || $0.isWhitespace }) else { return nil }
        return Double(trimmed[..<unitStart].trimmingCharacters(in: .whitespaces))
    }

    func compare(_ lhs: ArchiveRow, _ rhs: ArchiveRow) -> ComparisonResult {
        let lv = lhs.values[key] ?? ""
        let rv = rhs.values[key] ?? ""
        let result: ComparisonResult
        if let ln = Self.numericValue(lv), let rn = Self.numericValue(rv) {
            result = ln < rn ? .orderedAscending : ln > rn ? .orderedDescending : .orderedSame
        } else {
            result = lv.localizedStandardCompare(rv)
        }
        return order == .reverse ? result.flipped : result
    }
}

private extension ComparisonResult {
    var flipped: ComparisonResult {
        switch self {
        case .orderedAscending:  return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame:       return .orderedSame
        }
    }
}
