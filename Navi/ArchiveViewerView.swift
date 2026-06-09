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
    @State private var isRejecting = false
    private let logger = Logger(subsystem: "com.navi.app", category: "ArchiveViewer")
    @State private var showingFilter = false
    @State private var showingColumnsPopover = false
    @State private var columnSettings = ArchiveColumnSettings()
    private var filterBinding: Binding<ArchiveFilter> {
        Binding(get: { paneManager.archiveFilter }, set: { paneManager.archiveFilter = $0 })
    }
    @State private var filterBase: ArchiveViewerContent? = nil
    @State private var isLoadingFilter = false
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if paneManager.archiveFilter.isActive {
                Divider()
                filterChipsBar
            }
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
        .sheet(isPresented: $showingFilter) {
            ArchiveFilterSheet(filter: filterBinding)
        }
    }

    private var filterChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paneManager.archiveFilter.activeCategories, id: \.self) { category in
                    ActiveFilterChip(
                        category: category.rawValue,
                        label: paneManager.archiveFilter.chipLabel(for: category)
                    ) { paneManager.archiveFilter.clear(category) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(maxWidth: .infinity)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            let isFilterActive = paneManager.archiveFilter.isActive
            Image(systemName: isFilterActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : (paneManager.archiveContent?.iconName ?? "archivebox"))
                .foregroundStyle(isFilterActive ? Color.accentColor : Color.secondary)
                .font(.system(size: 14))

            Text(isFilterActive ? "Filter Results"
                 : (paneManager.archiveContent?.title ?? "Archive Browser"))
                .font(.headline)

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
                Task { await loadRecentFrames() }
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingRecent)
            .help("Show recent frames")

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
                    onRowSelected: { selectedRow = $0 },
                    onRowDoubleClicked: { [paneManager] row in
                        let filePath = row.values["file"] ?? row.values["path"]
                        if let filePath, !filePath.isEmpty {
                            paneManager.showFITSViewer(url: URL(fileURLWithPath: filePath))
                        }
                    }
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
                    onRowSelected: { selectedRow = $0 },
                    onRowDoubleClicked: { [paneManager] row in
                        let filePath = row.values["file"] ?? row.values["path"]
                        if let filePath, !filePath.isEmpty {
                            paneManager.showFITSViewer(url: URL(fileURLWithPath: filePath))
                        }
                    }
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
            Button("Clear Filter") { paneManager.archiveFilter = ArchiveFilter() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
            paneManager.archiveContent = content
        } catch {
            // Archive not connected or unavailable — leave content as-is
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
    var onRowSelected: ((ArchiveRow?) -> Void)? = nil
    var onRowDoubleClicked: ((ArchiveRow) -> Void)? = nil

    @State private var selectionID: ArchiveRow.ID? = nil
    @State private var sortOrder: [ColumnComparator] = []
    @State private var lastTapRowID: ArchiveRow.ID? = nil
    @State private var lastTapTime: Date = .distantPast

    private var displayColumns: [String] { columnSettings.visibleColumns(from: content.columns) }

    private var sortedRows: [ArchiveRow] {
        sortOrder.isEmpty ? content.rows : content.rows.sorted(using: sortOrder)
    }

    private func cellTapped(_ row: ArchiveRow) {
        let now = Date()
        if lastTapRowID == row.id, now.timeIntervalSince(lastTapTime) < 0.4 {
            onRowDoubleClicked?(row)
            lastTapRowID = nil
        } else {
            selectionID = row.id
            lastTapRowID = row.id
            lastTapTime = now
        }
    }

    var body: some View {
        let total = totalRows ?? content.rows.count
        let count = content.rows.count
        VStack(spacing: 0) {
            Table(sortedRows, selection: $selectionID, sortOrder: $sortOrder) {
                TableColumn("", sortUsing: ColumnComparator(key: "")) { row in
                    FrameTypeIcon(row: row)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { cellTapped(row) }
                }
                .width(min: 22, ideal: 22, max: 22)

                TableColumnForEach(displayColumns, id: \.self) { col in
                    TableColumn(Self.columnTitle(for: col), sortUsing: ColumnComparator(key: col)) { row in
                        Text(Self.formatted(row.values[col] ?? "", column: col))
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: Self.columnAlignment(for: col))
                            .contentShape(Rectangle())
                            .onTapGesture { cellTapped(row) }
                    }
                    .width(min: Self.minWidth(for: col), ideal: Self.idealWidth(for: col))
                }
            }
            .onChange(of: selectionID) { _, newID in
                let row = newID.flatMap { id in sortedRows.first { $0.id == id } }
                onRowSelected?(row)
            }
            .onChange(of: sortedRows.first(where: { $0.id == selectionID })?.values) { _, _ in
                guard let id = selectionID, let row = sortedRows.first(where: { $0.id == id }) else { return }
                onRowSelected?(row)
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
        switch column {
        case "fwhm": return "FWHM"
        case "snr":  return "SNR"
        case "ecc":  return "Ecc"
        case "exp":  return "Exp"
        default:     return column.capitalized
        }
    }

    private static func formatted(_ value: String, column: String) -> String {
        switch column {
        case "fwhm":
            if let d = Double(value) { return String(format: "%.1f", d) }
        case "ecc":
            if let d = Double(value) { return String(format: "%.2f", d) }
        case "type", "level":
            return value.capitalized
        default: break
        }
        return value
    }

    private static func columnAlignment(for column: String) -> Alignment {
        switch column {
        case "fwhm", "ecc", "snr", "exp", "stars", "frames": return .trailing
        default: return .leading
        }
    }

    private static func idealWidth(for column: String) -> CGFloat {
        switch column {
        case "type", "level", "filter":       return 70
        case "diagnostic":                    return 140
        case "exp", "fwhm", "ecc", "frames": return 60
        case "stars":                         return 56
        case "date":                          return 130
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
        case "exp", "fwhm", "ecc", "frames": return 44
        case "stars":                         return 44
        case "date":                          return 80
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
        let type = row.values["type"]?.lowercased() ?? ""
        if type == "light" {
            return (Color(NSColor.textBackgroundColor), Color(NSColor.labelColor))
        }
        return (Color(NSColor.secondaryLabelColor), Color(NSColor.secondaryLabelColor))
    }
}

struct ColumnComparator: SortComparator {
    typealias Compared = ArchiveRow
    let key: String
    var order: SortOrder = .forward

    func compare(_ lhs: ArchiveRow, _ rhs: ArchiveRow) -> ComparisonResult {
        let lv = lhs.values[key] ?? ""
        let rv = rhs.values[key] ?? ""
        let result: ComparisonResult
        if let ln = Double(lv), let rn = Double(rv) {
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
    let label: String
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
            ColumnEntry(key: "fwhm",  label: "FWHM"),
            ColumnEntry(key: "ecc",   label: "Eccentricity"),
            ColumnEntry(key: "stars", label: "Number of Stars"),
        ]),
        ColumnGroup(id: "equipment", header: "Equipment", entries: [
            ColumnEntry(key: "camera", label: "Camera"),
        ]),
        ColumnGroup(id: "archive", header: "Archive", entries: [
            ColumnEntry(key: "added",   label: "Added Date"),
            ColumnEntry(key: "created", label: "Created Date"),
            ColumnEntry(key: "frames",  label: "Number of Frames"),
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
