//
//  ArchiveViewerView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AppKit
import OSLog

struct ArchiveViewerView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager
    @State private var showRaw = false
    @State private var isLoadingRecent = false
    @State private var selectedRow: ArchiveRow? = nil
    @State private var selectionID: ArchiveRow.ID? = nil
    @State private var isRejecting = false
    private let logger = Logger(subsystem: "com.navi.app", category: "ArchiveViewer")
    @State private var showingFilter = false
    @State private var showingColumnsPopover = false
    @State private var columnSettings = ArchiveColumnSettings()
    private var filterBinding: Binding<ArchiveFilter> {
        Binding(get: { paneManager.archiveFilter }, set: { paneManager.setArchiveFilter($0) })
    }
    @State private var filterBase: ArchiveViewerContent? = nil
    @State private var isLoadingFilter = false
    @State private var isImporting = false
    @State private var importSummary: String? = nil
    @State private var importSummaryTask: Task<Void, Never>? = nil
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard paneManager.archiveContent == nil else { return }
            await loadRecentFrames()
        }
        .task(id: paneManager.archiveFilter) {
            await refreshFilterBase()
        }
        .task(id: ArchiveManager.shared.importVersion) {
            guard ArchiveManager.shared.importVersion > 0 else { return }
            await loadRecentFrames()
        }
        .onChange(of: paneManager.archiveContent?.toolName) { _, _ in
            selectionID = nil
            selectedRow = nil
        }
        .sheet(isPresented: $showingFilter) {
            ArchiveFilterSheet(filter: filterBinding)
        }
        .focusedSceneValue(\.importAction, { showImportPanel() })
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paneManager.archiveFilter.activeCategories, id: \.self) { category in
                    ActiveFilterChip(
                        category: category.rawValue,
                        label: paneManager.archiveFilter.chipLabel(for: category)
                    ) {
                        var updated = paneManager.archiveFilter
                        updated.clear(category)
                        paneManager.setArchiveFilter(updated)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            let isFilterActive = paneManager.archiveFilter.isActive

            PaneCloseButton(paneType: .archiveViewer)

            Divider()
                .frame(height: 14)

            Button { paneManager.archiveBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!paneManager.canGoBack)
            .help("Back")

            Button { paneManager.archiveForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!paneManager.canGoForward)
            .help("Forward")

            Divider()
                .frame(height: 14)

            Image(systemName: isFilterActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : (paneManager.archiveContent?.iconName ?? "archivebox"))
                .foregroundStyle(isFilterActive ? Color.accentColor : Color.secondary)
                .font(.system(size: 14))

            Text(isFilterActive ? "Filter Results"
                 : (paneManager.archiveContent?.title ?? "Archive Browser"))
                .font(.headline)
                .layoutPriority(1)

            if isFilterActive {
                filterChips
            }

            Spacer()

            if !showRaw {
                Button {
                    showingFilter.toggle()
                } label: {
                    Image(systemName: isFilterActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(isFilterActive ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isFilterActive ? "Filter active — click to edit" : "Filter")
            }

            if currentContent?.isTable == true {
                Button { showingColumnsPopover.toggle() } label: {
                    Image(systemName: "tablecells")
                        .font(.system(size: 12))
                        .foregroundStyle(columnSettings.hiddenColumns.isEmpty ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Configure visible columns")
                .popover(isPresented: $showingColumnsPopover, arrowEdge: .bottom) {
                    ColumnsPopover(settings: columnSettings)
                }
            }

            let isRowRejected = selectedRow?.values["rejected"] == "true"
            let canToggleReject = selectedRow != nil
                && selectedRow?.values["frames"].flatMap(Int.init) == nil

            RejectToggleButton(
                isRejected: isRowRejected,
                isDisabled: !canToggleReject || isRejecting
            ) { Task { await toggleRejection() } }

            Button {
                paneManager.toggleInfoPanel(url: selectedFileURL)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help(paneManager.isInfoPanelVisible ? "Hide Info Panel" : "Show Info Panel")

            Button {
                Task { await loadRecentFrames() }
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingRecent)
            .help("Show recent frames")

            Button {
                showImportPanel()
            } label: {
                if isImporting {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .help("Import FITS files")

            if let summary = importSummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .lineLimit(1)
            }

            if !isFilterActive, let content = paneManager.archiveContent {
                Text(content.toolName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                if content.isTable && !showRaw {
                    Toggle(isOn: $showRaw) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.plain)
                    .help("Show raw text")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content.rawContent, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Copy raw content")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var contentArea: some View {
        if paneManager.archiveFilter.isActive {
            filterContentArea
        } else if let content = paneManager.archiveContent {
            if showRaw || !content.isTable {
                rawView(content: content)
            } else if content.rows.isEmpty {
                emptyState("No results returned by \(content.toolName)")
            } else {
                ArchiveTableView(
                    content: content,
                    columnSettings: columnSettings,
                    selectionID: $selectionID,
                    onRowSelected: { row in
                        selectedRow = row
                        if let row { showFrameIfViewerVisible(row) }
                    },
                    onRowDoubleClicked: { row in handleFramesetDoubleClick(row) }
                )
            }
        } else {
            emptyState("Use 'Browse in Archive' on a tool result to view data here")
        }
    }

    @ViewBuilder
    private var filterContentArea: some View {
        if isLoadingFilter {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching archive…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let base = filterBase {
            let filtered = base.filtered(by: paneManager.archiveFilter)
            if filtered.rows.isEmpty {
                filterEmptyState()
            } else {
                ArchiveTableView(
                    content: filtered,
                    totalRows: base.rows.count,
                    columnSettings: columnSettings,
                    selectionID: $selectionID,
                    onRowSelected: { row in
                        selectedRow = row
                        if let row { showFrameIfViewerVisible(row) }
                    },
                    onRowDoubleClicked: { row in handleFramesetDoubleClick(row) }
                )
            }
        } else {
            emptyState("Archive not connected")
        }
    }

    private func refreshFilterBase() async {
        await Task.yield()
        let f = paneManager.archiveFilter
        guard f.isActive else {
            filterBase = nil
            isLoadingFilter = false
            return
        }
        isLoadingFilter = true
        do {
            var args: [String: Any] = ["kind": f.kind ?? "both"]
            if !f.types.isEmpty { args["frame_types"] = Array(f.types) }
            if let lvl = f.processingLevel { args["processing_level"] = lvl }
            let result = try await ArchiveManager.shared.callTool(name: "archive_search", arguments: args)
            guard !Task.isCancelled else { return }
            filterBase = ArchiveViewerContent.parse(toolName: "archive_search", content: result)
        } catch {
            guard !Task.isCancelled else { return }
            filterBase = nil
        }
        if !Task.isCancelled { isLoadingFilter = false }
    }

    private func rawView(content: ArchiveViewerContent) -> some View {
        ScrollView {
            Text(content.rawContent)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var currentContent: ArchiveViewerContent? {
        paneManager.archiveFilter.isActive ? filterBase : paneManager.archiveContent
    }

    private func filterEmptyState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No rows match the current filter")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Clear Filter") { paneManager.setArchiveFilter(ArchiveFilter()) }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func handleFramesetDoubleClick(_ row: ArchiveRow) {
        guard let idStr = row.values["id"], !idStr.isEmpty else { return }
        Task { await loadFramesetView(id: idStr, title: framesetTitle(from: row)) }
    }

    // File URL of the selected row, if it is a frame (not a frameset).
    private var selectedFileURL: URL? {
        guard let row = selectedRow,
              row.values["frames"].flatMap(Int.init) == nil,
              let path = row.values["file"] ?? row.values["path"], !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func showFrameIfViewerVisible(_ row: ArchiveRow) {
        let isFrameset = row.values["frames"].flatMap(Int.init) != nil
        guard !isFrameset else { return }
        let filePath = row.values["file"] ?? row.values["path"]
        if let filePath, !filePath.isEmpty {
            let url = URL(fileURLWithPath: filePath)
            paneManager.showFITSViewerIfVisible(url: url)
            paneManager.showInfoIfVisible(url: url)
        }
    }


    private func framesetTitle(from row: ArchiveRow) -> String? {
        if let name = row.values["name"], !name.isEmpty { return name }
        var parts: [String] = []
        if let obj = row.values["object"], !obj.isEmpty { parts.append(obj) }
        if let filter = row.values["filter"], !filter.isEmpty { parts.append(filter) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " – ") + " Frames"
    }

    private func loadFramesetView(id: String, title: String? = nil) async {
        do {
            let result = try await ArchiveManager.shared.callTool(
                name: "archive_frameset_get",
                arguments: ["id": id]
            )
            var content = ArchiveViewerContent.parse(toolName: "archive_frameset_get", content: result)
            if let title { content.title = title }
            paneManager.navigateArchiveTo(content: content)
        } catch {
            logger.error("loadFramesetView failed: \(error)")
        }
    }

    private func loadRecentFrames() async {
        guard !isLoadingRecent else { return }
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        do {
            let result = try await ArchiveManager.shared.callTool(
                name: "archive_recent",
                arguments: [:]
            )
            let content = ArchiveViewerContent.parse(toolName: "archive_recent", content: result)
            paneManager.navigateArchiveTo(content: content)
        } catch {
            // Archive not connected or unavailable — leave content as-is
        }
    }

    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.title = "Import FITS Files"
        panel.prompt = "Import"
        panel.message = "Select FITS files or folders containing FITS files"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { await runImport(urls: urls) }
    }

    private func runImport(urls: [URL]) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let result = await ArchiveManager.shared.importFITS(urls: urls)
        importSummaryTask?.cancel()
        withAnimation { importSummary = result.summary }
        importSummaryTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { importSummary = nil }
        }
    }

    private func toggleRejection() async {
        guard let row = selectedRow,
              let id = row.values["id"], !id.isEmpty,
              let uuid = UUID(uuidString: id) else { return }
        let target = row.values["rejected"] != "true"
        isRejecting = true
        defer { isRejecting = false }
        do {
            try await ArchiveManager.shared.setRejected(target, id: uuid)
            let value = target ? "true" : "false"
            // Explicit copy → mutate → reassign to guarantee @Observable and @State notifications fire
            if var content = paneManager.archiveContent,
               let idx = content.rows.firstIndex(where: { $0.values["id"] == id }) {
                content.rows[idx].values["rejected"] = value
                paneManager.archiveContent = content
            }
            if var base = filterBase,
               let idx = base.rows.firstIndex(where: { $0.values["id"] == id }) {
                base.rows[idx].values["rejected"] = value
                filterBase = base
            }
            selectedRow?.values["rejected"] = value
            let rowPath = row.values["file"] ?? row.values["path"] ?? ""
            if !rowPath.isEmpty, paneManager.fitsURL?.path == rowPath {
                paneManager.fitsFrameRejected = target
            }
        } catch {
            logger.error("toggleRejection failed: \(error)")
        }
    }
}

struct ArchiveTableView: View {
    let content: ArchiveViewerContent
    var totalRows: Int? = nil
    let columnSettings: ArchiveColumnSettings
    @Binding var selectionID: ArchiveRow.ID?
    var onRowSelected: ((ArchiveRow?) -> Void)? = nil
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
                Task { @MainActor in callback?(row) }
            }
            .onChange(of: displayedRows.first(where: { $0.id == selectionID })?.values) { _, _ in
                guard let id = selectionID, let row = displayedRows.first(where: { $0.id == id }) else { return }
                let callback = onRowSelected
                Task { @MainActor in callback?(row) }
            }
            .onChange(of: content.toolName) { _, _ in
                expandedFramesets.removeAll()
                framesetChildren.removeAll()
                loadingFramesets.removeAll()
            }

            Divider()

            HStack {
                Text(count == total
                     ? "\(count) \(count == 1 ? "row" : "rows")"
                     : "\(count) of \(total) rows")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
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

struct ActiveFilterChip: View {
    let category: String
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(category): \(label)")
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.1))
        .foregroundStyle(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
    }
}

struct ArchiveFilterSheet: View {
    @Binding var filter: ArchiveFilter
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: FilterCategory = .object
    @State private var allObjects: [String] = []
    @State private var isLoadingObjects = false
    @State private var objectSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header
            HStack {
                Text("Filter Archive")
                    .font(.headline)
                Spacer()
                if filter.isActive {
                    Button("Clear All") { filter = ArchiveFilter() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Two-column layout
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(FilterCategory.allCases, id: \.self) { cat in
                        HStack(spacing: 8) {
                            Label(cat.rawValue, systemImage: cat.icon)
                                .font(.callout)
                            Spacer()
                            if filter.isActive(for: cat) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(selectedCategory == cat
                            ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCategory = cat }
                    }
                    Spacer()
                }
                .padding(8)
                .frame(width: 180)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Detail panel
                VStack(alignment: .leading, spacing: 0) {
                    // Category header
                    HStack {
                        Text(selectedCategory.rawValue)
                            .font(.title3).fontWeight(.semibold)
                        Spacer()
                        if filter.isActive(for: selectedCategory) {
                            Button("Clear") { filter.clear(selectedCategory) }
                                .buttonStyle(.plain)
                                .font(.callout)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    Divider()

                    categoryDetail
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: 560, height: 400)
        .task { await loadObjects() }
    }

    @ViewBuilder
    private var categoryDetail: some View {
        switch selectedCategory {
        case .object:    objectDetail
        case .frameType: frameTypeDetail
        case .kind:      kindDetail
        case .level:     levelDetail
        case .date:      dateDetail
        case .quality:   qualityDetail
        }
    }

    // MARK: Object
    private var objectDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search", text: $objectSearch)
                .textFieldStyle(.roundedBorder)

            let visible = objectSearch.isEmpty ? allObjects
                : allObjects.filter { $0.localizedCaseInsensitiveContains(objectSearch) }

            if isLoadingObjects {
                ProgressView("Loading objects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text(allObjects.isEmpty ? "No objects in archive" : "No objects match \"\(objectSearch)\"")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(visible, id: \.self) { obj in
                            Toggle(isOn: Binding(
                                get: { filter.objects.contains(obj) },
                                set: { checked in
                                    guard checked != filter.objects.contains(obj) else { return }
                                    if checked { filter.objects.insert(obj) } else { filter.objects.remove(obj) }
                                }
                            )) { Text(obj).font(.callout) }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Frame Type
    private var frameTypeDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select frame types to include")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(["light", "dark", "flat", "bias", "darkflat", "diagnostic"], id: \.self) { type in
                    FilterChip(label: type.capitalized, isSelected: filter.types.contains(type)) {
                        if filter.types.contains(type) { filter.types.remove(type) }
                        else { filter.types.insert(type) }
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: Kind
    private var kindDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show in results")
                .font(.callout).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { filter.kind ?? "both" },
                set: { new in
                    let resolved: String? = new == "both" ? nil : new
                    if filter.kind != resolved { filter.kind = resolved }
                }
            )) {
                Text("Frames and framesets").tag("both")
                Text("Frames only").tag("frames")
                Text("Framesets only").tag("framesets")
            }
            .pickerStyle(.radioGroup)
            Spacer()
        }
    }

    // MARK: Processing Level
    private var levelDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processing level")
                .font(.callout).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { filter.processingLevel ?? "all" },
                set: { new in
                    let resolved: String? = new == "all" ? nil : new
                    if filter.processingLevel != resolved { filter.processingLevel = resolved }
                }
            )) {
                Text("All levels").tag("all")
                Text("Raw").tag("raw")
                Text("Stacked").tag("stacked")
                Text("Stretched").tag("stretched")
            }
            .pickerStyle(.radioGroup)
            Spacer()
        }
    }

    // MARK: Date
    private var dateDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("From", isOn: Binding(
                    get: { filter.dateFrom != nil },
                    set: { enabled in
                        guard enabled != (filter.dateFrom != nil) else { return }
                        filter.dateFrom = enabled ? Calendar.current.date(byAdding: .month, value: -3, to: Date()) : nil
                    }
                ))
                .toggleStyle(.checkbox).frame(width: 50, alignment: .leading)
                if filter.dateFrom != nil {
                    DatePicker("", selection: Binding(get: { filter.dateFrom! }, set: { filter.dateFrom = $0 }),
                               displayedComponents: .date).labelsHidden()
                }
            }
            HStack {
                Toggle("To", isOn: Binding(
                    get: { filter.dateTo != nil },
                    set: { enabled in
                        guard enabled != (filter.dateTo != nil) else { return }
                        filter.dateTo = enabled ? Date() : nil
                    }
                ))
                .toggleStyle(.checkbox).frame(width: 50, alignment: .leading)
                if filter.dateTo != nil {
                    DatePicker("", selection: Binding(get: { filter.dateTo! }, set: { filter.dateTo = $0 }),
                               displayedComponents: .date).labelsHidden()
                }
            }
            Spacer()
        }
    }

    // MARK: Quality
    private var qualityDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Empty fields are ignored")
                .font(.caption).foregroundStyle(.secondary)
            QualityRangeRow(label: "FWHM",  min: $filter.minFWHM,  max: $filter.maxFWHM)
            QualityRangeRow(label: "SNR",   min: $filter.minSNR,   max: $filter.maxSNR)
            QualityRangeRow(label: "Stars", min: $filter.minStars, max: $filter.maxStars)
            Spacer()
        }
    }

    private func loadObjects() async {
        isLoadingObjects = true
        defer { isLoadingObjects = false }
        do {
            let result = try await ArchiveManager.shared.callTool(name: "archive_list_objects", arguments: [:])
            let parsed = ArchiveViewerContent.parse(toolName: "archive_list_objects", content: result)
            let names = parsed.rows.compactMap { row -> String? in
                let n = row.values["name"] ?? row.values["object"] ?? ""
                return n.isEmpty ? nil : n
            }
            let sorted = Array(Set(names)).sorted()
            if !sorted.isEmpty { allObjects = sorted }
        } catch {}
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct QualityRangeRow: View {
    let label: String
    @Binding var min: String
    @Binding var max: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .frame(width: 44, alignment: .leading)
            Text("≥")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $min)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .font(.callout)
            Text("≤")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $max)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .font(.callout)
        }
    }
}

struct ColumnEntry {
    let key: String
    let label: String       // shown in the column chooser
    var header: String? = nil  // table column header; defaults to label
}

struct ColumnGroup: Identifiable {
    let id: String
    let header: String
    let entries: [ColumnEntry]
}

@Observable
final class ArchiveColumnSettings {
    var hiddenColumns: Set<String> = []

    static let groups: [ColumnGroup] = [
        ColumnGroup(id: "observation", header: "Observation", entries: [
            ColumnEntry(key: "name",   label: "Name"),
            ColumnEntry(key: "object", label: "Object"),
            ColumnEntry(key: "date",   label: "Observation Date"),
        ]),
        ColumnGroup(id: "properties", header: "Properties", entries: [
            ColumnEntry(key: "type",   label: "Type"),
            ColumnEntry(key: "filter", label: "Filter"),
            ColumnEntry(key: "level",  label: "Level"),
            ColumnEntry(key: "exp",    label: "Exposure"),
        ]),
        ColumnGroup(id: "quality", header: "Quality", entries: [
            ColumnEntry(key: "fwhm",        label: "Mean FWHM [px]", header: "FWHM (Mean)"),
            ColumnEntry(key: "fwhm_arcsec", label: "Mean FWHM [\"]", header: "FWHM (Mean)"),
            ColumnEntry(key: "ecc",   label: "Eccentricity"),
            ColumnEntry(key: "stars", label: "Number of Stars"),
        ]),
        ColumnGroup(id: "equipment", header: "Equipment", entries: [
            ColumnEntry(key: "camera", label: "Camera"),
        ]),
        ColumnGroup(id: "archive", header: "Archive", entries: [
            ColumnEntry(key: "added",  label: "Added"),
            ColumnEntry(key: "frames", label: "Number of Frames"),
        ]),
        ColumnGroup(id: "file", header: "File", entries: [
            ColumnEntry(key: "file", label: "File"),
        ]),
    ]

    static var standardColumns: [String] {
        groups.flatMap { $0.entries.map { $0.key } }
    }

    private static let key = "archiveViewer.columnSettings"

    init() { load() }

    func visibleColumns(from available: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        // Standard columns always appear in group order (unless hidden)
        for col in Self.standardColumns where !hiddenColumns.contains(col) {
            result.append(col); seen.insert(col)
        }
        // Any extra columns from data that aren't in the standard set
        for col in available where !seen.contains(col) && !hiddenColumns.contains(col) {
            result.append(col)
        }
        return result
    }

    func save() {
        UserDefaults.standard.set(Array(hiddenColumns), forKey: Self.key)
    }

    private func load() {
        if let arr = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            hiddenColumns = Set(arr)
        } else if let dict = UserDefaults.standard.dictionary(forKey: Self.key),
                  let arr = dict["hiddenColumns"] as? [String] {
            hiddenColumns = Set(arr)
        }
    }
}

struct ColumnsPopover: View {
    let settings: ArchiveColumnSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Columns").font(.headline)
                Spacer()
                if !settings.hiddenColumns.isEmpty {
                    Button("Show All") { settings.hiddenColumns.removeAll(); settings.save() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ArchiveColumnSettings.groups) { group in
                        Text(group.header.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 3)
                        ForEach(group.entries, id: \.key) { entry in
                            Toggle(isOn: Binding(
                                get: { !settings.hiddenColumns.contains(entry.key) },
                                set: { show in
                                    let visible = !settings.hiddenColumns.contains(entry.key)
                                    guard show != visible else { return }
                                    if show { settings.hiddenColumns.remove(entry.key) }
                                    else    { settings.hiddenColumns.insert(entry.key) }
                                    settings.save()
                                }
                            )) { Text(entry.label).font(.callout) }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 210)
    }
}

/// Bordered toggle button used in both the Archive viewer and FITS viewer toolbars.
/// Clear background + border when not rejected; grey fill + border when rejected.
struct RejectToggleButton: View {
    let isRejected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.diamond.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, isRejected ? Color.red : Color.primary)
                Text("Reject")
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(isRejected ? Color.gray.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5))
        .disabled(isDisabled)
        .help(isRejected ? "Click to unreject" : "Reject frame")
    }
}
