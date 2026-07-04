//
//  ArchiveTableView.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI
import AppKit
import AstrophotoArchiveKit
import OSLog

private let logger = Logger(subsystem: "com.navi", category: "ArchiveTableView")

struct SessionMeta: Equatable {
    var name: String
    var total: Int
    var isNight: Bool
    var sortDate: String
    var isValid: Bool
}

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
    var sessionInfo: [String: SessionMeta] = [:]
    var onSessionLoaded: ((String, SessionMeta) -> Void)? = nil
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
        var ids = Set<ArchiveRow.ID>()
        for row in sortedRows where expandedFramesets.contains(row.id) {
            if row.isSession {
                (row.children ?? []).forEach { ids.insert($0.id) }
            } else {
                (framesetChildren[row.id] ?? []).forEach { ids.insert($0.id) }
            }
        }
        return ids
    }

    private var displayedRows: [ArchiveRow] {
        var result: [ArchiveRow] = []
        for row in sortedRows {
            result.append(row)
            guard expandedFramesets.contains(row.id) else { continue }
            if row.isSession {
                let children = row.children ?? []
                result += sortOrder.isEmpty ? children : children.sorted(using: sortOrder)
            } else {
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
            if !row.isSession && framesetChildren[row.id] == nil {
                Task { await loadChildren(for: row) }
            }
        }
    }

    private func loadChildren(for row: ArchiveRow) async {
        guard let idStr = row.values["id"], let uuid = UUID(uuidString: idStr) else { return }
        loadingFramesets.insert(row.id)
        do {
            if row.values["kind"] == "session" {
                let frames = try await ArchiveManager.shared.frames(inSession: uuid)
                framesetChildren[row.id] = ArchiveViewerContent.frames(frames, toolName: "archive_session_frames").rows
            } else {
                let fetched = try await ArchiveManager.shared.members(inFrameSet: uuid)
                framesetChildren[row.id] = ArchiveViewerContent.members(fetched, toolName: "archive_frameset_get").rows
            }
        } catch {
            logger.warning("loadChildren failed for \(idStr): \(error)")
        }
        loadingFramesets.remove(row.id)
    }

    var body: some View {
        let total = totalRows ?? content.rows.count
        let count = content.rows.count
        VStack(spacing: 0) {
            Table(displayedRows, selection: $selectionID, sortOrder: $sortOrder) {
                TableColumn("Name", sortUsing: ColumnComparator(key: "name")) { row in
                    let isExpandable = row.isFrameset || row.isSession
                    let isChild = childRowIDs.contains(row.id)
                    let sid = row.values["session_id"]
                    let meta = sid.flatMap { sessionInfo[$0] }
                    let cell = ArchiveNameCell(
                        row: row,
                        isExpandable: isExpandable,
                        isChild: isChild,
                        isExpanded: expandedFramesets.contains(row.id),
                        isLoading: !row.isSession && loadingFramesets.contains(row.id),
                        sessionName: meta?.name,
                        sessionTotal: meta?.total,
                        onToggle: { toggleExpand(row) }
                    )
                    if row.isFrameset {
                        cell.simultaneousGesture(TapGesture().onEnded { cellTapped(row) })
                    } else {
                        cell
                    }
                }
                .width(min: 120, ideal: 200)

                TableColumnForEach(displayColumns.filter { $0 != "name" }, id: \.self) { col in
                    TableColumn(Self.columnTitle(for: col), sortUsing: ColumnComparator(key: col)) { row in
                        let value = row.isSession && !Self.sessionVisibleColumns.contains(col)
                            ? ""
                            : Self.formatted(row.values[col] ?? "", column: col)
                        Text(value)
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
            .onChange(of: selectedRowValues) { _, _ in
                guard let id = selectionID, let row = findRow(id: id) else { return }
                let callback = onRowSelected
                Task { @MainActor in callback?(row, false) }
            }
            .onChange(of: content.toolName) { _, _ in
                expandedFramesets.removeAll()
                framesetChildren.removeAll()
                loadingFramesets.removeAll()
            }
            .task(id: sessionIDsKey) {
                await loadMissingSessionInfo()
            }

            Divider()

            ArchiveStatusBar(rowCount: count, totalRowCount: total)
        }
    }

    private var sessionIDsKey: String {
        sortedRows.compactMap { $0.isSession ? $0.values["session_id"] : nil }.sorted().joined(separator: ",")
    }

    // Values of the currently selected row, found by searching content.rows and
    // their children directly — avoids building the full displayedRows array just
    // to detect in-place value changes (e.g. reject toggle).
    private var selectedRowValues: [String: String]? {
        guard let id = selectionID else { return nil }
        for row in content.rows {
            if row.id == id { return row.values }
            if let child = row.children?.first(where: { $0.id == id }) { return child.values }
        }
        for children in framesetChildren.values {
            if let child = children.first(where: { $0.id == id }) { return child.values }
        }
        return nil
    }

    private func findRow(id: ArchiveRow.ID) -> ArchiveRow? {
        for row in content.rows {
            if row.id == id { return row }
            if let child = row.children?.first(where: { $0.id == id }) { return child }
        }
        for children in framesetChildren.values {
            if let child = children.first(where: { $0.id == id }) { return child }
        }
        return nil
    }

    private func loadMissingSessionInfo() async {
        let missing = sortedRows.compactMap { row -> String? in
            guard row.isSession,
                  let sid = row.values["session_id"],
                  sessionInfo[sid] == nil else { return nil }
            return sid
        }
        guard !missing.isEmpty else { return }

        let invalid = SessionMeta(name: "", total: 0, isNight: true, sortDate: "", isValid: false)

        do {
            let allSessions = try await ArchiveManager.shared.sessions()
            let neededIDs = Set(missing)
            var updates: [String: SessionMeta] = [:]
            for session in allSessions where neededIDs.contains(session.id.uuidString) {
                // Must use the same shortDate() as frame rows' "date" column (see
                // ArchiveViewerContent.swift) — the "date" column comparator sorts
                // session and frame rows as plain strings, so a mismatched format
                // or time zone here would sort sessions out of order.
                let sortDate = shortDate(session.startTime ?? session.date)
                updates[session.id.uuidString] = SessionMeta(
                    name: session.name,
                    total: session.frameCount,
                    isNight: session.isNight,
                    sortDate: sortDate,
                    isValid: true
                )
            }
            for sid in missing where updates[sid] == nil {
                updates[sid] = invalid
            }
            // Single MainActor dispatch so SwiftUI batches all sessionInfo mutations
            // into one groupedBySessions() recompute instead of one per session.
            let callback = onSessionLoaded
            await MainActor.run {
                for (id, meta) in updates { callback?(id, meta) }
            }
        } catch {
            // Archive unavailable — fall back to per-session fetches
            await withTaskGroup(of: Void.self) { group in
                for sid in missing {
                    group.addTask { await self.fetchSessionInfo(id: sid) }
                }
            }
        }
    }

    private func fetchSessionInfo(id: String) async {
        let invalid = SessionMeta(name: "", total: 0, isNight: true, sortDate: "", isValid: false)
        guard let uuid = UUID(uuidString: id) else {
            await MainActor.run { onSessionLoaded?(id, invalid) }
            return
        }
        do {
            guard let session = try await ArchiveManager.shared.session(id: uuid) else {
                await MainActor.run { onSessionLoaded?(id, invalid) }
                return
            }
            let sortDate = shortDate(session.startTime ?? session.date)
            let meta = SessionMeta(
                name: session.name,
                total: session.frameCount,
                isNight: session.isNight,
                sortDate: sortDate,
                isValid: true
            )
            await MainActor.run { onSessionLoaded?(id, meta) }
        } catch {
            await MainActor.run { onSessionLoaded?(id, invalid) }
        }
    }

    private static let sessionVisibleColumns: Set<String> = ["object", "frames"]

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

    private var symbolName: String {
        if row.isSession { return "folder" }
        if row.isRejected || row.isExcluded { return "xmark.diamond.fill" }
        return frameTypeSymbolName(type: row.frameType, level: row.processingLevel?.rawValue ?? "raw", isFrameset: row.isFrameset)
    }

    private var palette: (Color, Color) {
        if row.isSession { return (Color(NSColor.secondaryLabelColor), Color(NSColor.secondaryLabelColor)) }
        if row.isRejected { return (.white, .red) }
        if row.isExcluded { return (Color(NSColor.black), .yellow) }
        if row.isFrameset { return (Color(NSColor.secondaryLabelColor), Color(NSColor.secondaryLabelColor)) }
        if row.frameType == "light" { return (Color(NSColor.textBackgroundColor), Color(NSColor.labelColor)) }
        return (Color(NSColor.secondaryLabelColor), Color(NSColor.secondaryLabelColor))
    }
}

private struct ArchiveNameCell: View {
    let row: ArchiveRow
    let isExpandable: Bool
    let isChild: Bool
    let isExpanded: Bool
    let isLoading: Bool
    var sessionName: String? = nil
    var sessionTotal: Int? = nil
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isExpandable {
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
            if row.isSession { sessionBadge }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var sessionBadge: some View {
        let matched = Int(row.values["matched"] ?? "0") ?? 0
        let total = sessionTotal ?? 0
        let label = total > matched ? "\(matched) of \(total) frames" : "\(matched) frames"
        Text(label)
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.tertiary)
    }

    private var displayName: String {
        if row.isSession {
            return sessionName ?? "Session"
        }
        let name = (row.values["name"] ?? "").trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let level = row.processingLevel?.rawValue.capitalized ?? ""
        let filter = row.values["filter"] ?? ""
        let camera = row.values["camera"] ?? ""
        let parts: [String]
        switch row.frameType {
        case "bias", "masterbias":
            parts = row.isMaster || row.frameType == "masterbias"
                ? ["Master Bias", camera]
                : [level, "Bias"]
        case "dark", "masterdark":
            parts = row.isMaster || row.frameType == "masterdark"
                ? [exposureLabel, temperatureLabel, "Master Dark", camera]
                : [exposureLabel, temperatureLabel, level, "Dark"]
        case "darkflat", "dark-flat", "dark flat", "masterdarkflat":
            parts = row.isMaster || row.frameType == "masterdarkflat"
                ? [temperatureLabel, "Master Dark Flat", camera]
                : [temperatureLabel, level, "Dark Flat"]
        case "flat", "masterflat":
            parts = row.isMaster || row.frameType == "masterflat"
                ? [filter, "Master Flat", camera]
                : [filter, level, "Flat"]
        default:
            parts = [row.values["object"] ?? "", filter, level]
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var exposureLabel: String {
        guard let v = row.values["exp"],
              let d = ColumnComparator.numericValue(v) else { return "" }
        return String(format: "%gs", d)
    }

    private var temperatureLabel: String {
        guard let v = row.values["temp"], let d = Double(v) else { return "" }
        return String(format: "%g°C", d)
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
