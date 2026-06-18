//
//  ArchiveViewerView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AppKit
import AstrophotoArchiveKit
import OSLog

struct ArchiveViewerView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager
    @State private var showRaw = false
    @State private var isLoadingRecent = false
    @State private var selectedRow: ArchiveRow? = nil
    @State private var selectionID: ArchiveRow.ID? = nil
    @State private var isRejecting = false
    @State private var sessionInfo: [String: SessionMeta] = [:]
    @State private var groupedContent: ArchiveViewerContent? = nil
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
    @State private var pendingFrameChoice: PendingFrameChoice? = nil
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
                // Anchored to the whole table, not the clicked row: SwiftUI's
                // Table does not expose row rects, so a row-anchored popover
                // is not possible without dropping to NSTableView.
                .popover(item: $pendingFrameChoice, arrowEdge: .bottom) { choice in
                    FrameDestinationPopover(destinations: choice.destinations) { destination in
                        destination.paneManager.showFITSViewerIfVisible(url: choice.url)
                        pendingFrameChoice = nil
                    }
                }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard paneManager.archiveContent == nil else { return }
            await loadAllFrames()
        }
        .task(id: paneManager.archiveFilter) {
            await refreshFilterBase()
        }
        .task(id: ArchiveManager.shared.isConnected) {
            await ArchiveManager.shared.refreshDiskUsage()
        }
        .task(id: ArchiveManager.shared.importVersion) {
            guard ArchiveManager.shared.importVersion > 0 else { return }
            await loadAllFrames()
            await ArchiveManager.shared.refreshDiskUsage()
        }
        .onChange(of: paneManager.archiveContent) { _, new in
            groupedContent = new?.groupedBySessions(sessionInfo: sessionInfo)
        }
        .onChange(of: sessionInfo) { _, new in
            groupedContent = paneManager.archiveContent?.groupedBySessions(sessionInfo: new)
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
            PaneMoveButton(pane: pane)

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

            let isRowRejected = selectedRow?.isRejected == true
            let canToggleReject = selectedRow != nil
                && selectedRow?.isFrameset != true
                && selectedRow?.isSession != true

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
                Task { await loadAllFrames() }
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingRecent)
            .help("Show all frames")

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
                    content: groupedContent ?? content.groupedBySessions(sessionInfo: sessionInfo),
                    columnSettings: columnSettings,
                    selectionID: $selectionID,
                    onRowSelected: { row, isNewSelection in
                        selectedRow = row
                        if let row, isNewSelection { showFrameIfViewerVisible(row) }
                    },
                    onRowDoubleClicked: { row in handleFramesetDoubleClick(row) },
                    sessionInfo: sessionInfo,
                    onSessionLoaded: { id, meta in sessionInfo[id] = meta }
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
                    content: filtered.groupedBySessions(),
                    totalRows: base.rows.count,
                    columnSettings: columnSettings,
                    selectionID: $selectionID,
                    onRowSelected: { row, isNewSelection in
                        selectedRow = row
                        if let row, isNewSelection { showFrameIfViewerVisible(row) }
                    },
                    onRowDoubleClicked: { row in handleFramesetDoubleClick(row) },
                    sessionInfo: sessionInfo,
                    onSessionLoaded: { id, meta in sessionInfo[id] = meta }
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
            var query = FrameQuery()
            if !f.types.isEmpty { query.frameTypes = Array(f.types) }
            if let lvl = f.processingLevel { query.processingLevel = ProcessingLevel(rawValue: lvl) }
            let frames = try await ArchiveManager.shared.frames(matching: query)
            guard !Task.isCancelled else { return }
            filterBase = ArchiveViewerContent.frames(frames, toolName: "archive_search")
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
              !row.isFrameset && !row.isSession,
              let path = row.values["file"] ?? row.values["path"], !path.isEmpty
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    // Routes the selected frame to the FITS viewers and info panels that
    // follow this archive pane, across windows (NAVI-10). When several FITS
    // viewers could show the frame, a popover asks which one should.
    private func showFrameIfViewerVisible(_ row: ArchiveRow) {
        guard !row.isFrameset && !row.isSession else { return }
        let filePath = row.values["file"] ?? row.values["path"]
        if let filePath, !filePath.isEmpty {
            let url = URL(fileURLWithPath: filePath)
            let candidates = WindowRegistry.shared.showFrame(url: url, from: paneManager)
            if !candidates.isEmpty {
                pendingFrameChoice = PendingFrameChoice(url: url, destinations: candidates)
            }
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
        guard let uuid = UUID(uuidString: id) else { return }
        do {
            let fetched = try await ArchiveManager.shared.members(inFrameSet: uuid)
            var content = ArchiveViewerContent.members(fetched, toolName: "archive_frameset_get")
            if let title { content.title = title }
            paneManager.navigateArchiveTo(content: content)
        } catch {
            logger.error("loadFramesetView failed: \(error)")
        }
    }

    // Loads all light frames so groupedBySessions can build proper session folders.
    // Calibration frame types (dark, flat, bias, darkflat) are excluded for now.
    private func loadAllFrames() async {
        guard !isLoadingRecent else { return }
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        do {
            var query = FrameQuery()
            query.frameTypes = ["light"]
            let frames = try await ArchiveManager.shared.frames(matching: query)
            var content = ArchiveViewerContent.frames(frames, toolName: "archive_recent")
            content.title = "All Frames"
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
        let target = !row.isRejected
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
            if !rowPath.isEmpty {
                // The frame may be on display in another window's FITS viewer.
                WindowRegistry.shared.frameRejectionChanged(path: rowPath, rejected: target)
            }
        } catch {
            logger.error("toggleRejection failed: \(error)")
        }
    }
}

// A frame selection that several FITS viewers could show (NAVI-10); the
// popover asks the user which window's viewer should take it.
private struct PendingFrameChoice: Identifiable {
    let id = UUID()
    let url: URL
    let destinations: [FrameDestination]
}

private struct FrameDestinationPopover: View {
    let destinations: [FrameDestination]
    let onSelect: (FrameDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show Frame In")
                .font(.headline)
            ForEach(destinations) { destination in
                Button {
                    onSelect(destination)
                } label: {
                    Label(destination.title, systemImage: "photo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(minWidth: 180)
    }
}
