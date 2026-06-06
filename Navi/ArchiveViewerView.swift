//
//  ArchiveViewerView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AppKit

struct ArchiveViewerView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager
    @State private var showRaw = false
    @State private var isLoadingRecent = false
    @State private var selectedRow: ArchiveRow? = nil
    @State private var isRejecting = false

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
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: paneManager.archiveContent?.iconName ?? "archivebox")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            Text(paneManager.archiveContent?.title ?? "Archive Browser")
                .font(.headline)

            Spacer()

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

            if let content = paneManager.archiveContent {
                Text(content.toolName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                if content.isTable {
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
        if let content = paneManager.archiveContent {
            if showRaw || !content.isTable {
                rawView(content: content)
            } else if content.rows.isEmpty {
                emptyState("No results returned by \(content.toolName)")
            } else {
                ArchiveTableView(
                    content: content,
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
        guard let row = selectedRow, let id = row.values["id"], !id.isEmpty,
              let uuid = UUID(uuidString: id) else { return }
        let target = row.values["rejected"] != "true"
        isRejecting = true
        defer { isRejecting = false }
        do {
            try await ArchiveManager.shared.setRejected(target, id: uuid)
            let value = target ? "true" : "false"
            if let idx = paneManager.archiveContent?.rows.firstIndex(where: { $0.values["id"] == id }) {
                paneManager.archiveContent?.rows[idx].values["rejected"] = value
            }
            selectedRow?.values["rejected"] = value
        } catch {
            // Silently fail — archive may be disconnected
        }
    }
}

struct ArchiveTableView: View {
    let content: ArchiveViewerContent
    var onRowSelected: ((ArchiveRow?) -> Void)? = nil
    var onRowDoubleClicked: ((ArchiveRow) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ArchiveNSTableView(content: content, onRowSelected: onRowSelected, onRowDoubleClicked: onRowDoubleClicked)

            Divider()

            HStack {
                Text("\(content.rows.count) \(content.rows.count == 1 ? "row" : "rows")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct ArchiveNSTableView: NSViewRepresentable {
    let content: ArchiveViewerContent
    var onRowSelected: ((ArchiveRow?) -> Void)? = nil
    var onRowDoubleClicked: ((ArchiveRow) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
        tableView.rowHeight = 20
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.rowDoubleClicked(_:))

        addColumns(to: tableView, columns: content.columns)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    private static let iconColumnID = NSUserInterfaceItemIdentifier("__type_icon__")

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let currentColumns = tableView.tableColumns.map { $0.identifier.rawValue }
        let expectedColumns = [Self.iconColumnID.rawValue] + content.columns
        if currentColumns != expectedColumns {
            for col in tableView.tableColumns { tableView.removeTableColumn(col) }
            addColumns(to: tableView, columns: content.columns)
        }
        context.coordinator.update(content: content, tableView: tableView)
        context.coordinator.onRowSelected = onRowSelected
        context.coordinator.onRowDoubleClicked = onRowDoubleClicked
    }

    private func addColumns(to tableView: NSTableView, columns: [String]) {
        let iconCol = NSTableColumn(identifier: Self.iconColumnID)
        iconCol.title = ""
        iconCol.width = 24
        iconCol.minWidth = 24
        iconCol.maxWidth = 24
        iconCol.resizingMask = []
        tableView.addTableColumn(iconCol)

        for column in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column))
            col.title = column
            col.width = 140
            col.minWidth = 60
            col.maxWidth = 400
            col.sortDescriptorPrototype = NSSortDescriptor(key: column, ascending: true,
                selector: #selector(NSString.localizedStandardCompare(_:)))
            tableView.addTableColumn(col)
        }
    }

    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private var content: ArchiveViewerContent
        private var sortedRows: [ArchiveRow]
        var onRowSelected: ((ArchiveRow?) -> Void)?
        var onRowDoubleClicked: ((ArchiveRow) -> Void)?

        init(content: ArchiveViewerContent) {
            self.content = content
            self.sortedRows = content.rows
        }

        func update(content: ArchiveViewerContent, tableView: NSTableView) {
            self.content = content
            self.sortedRows = content.rows
            tableView.reloadData()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            onRowSelected?(row >= 0 && row < sortedRows.count ? sortedRows[row] : nil)
        }

        @objc func rowDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < sortedRows.count else { return }
            onRowDoubleClicked?(sortedRows[row])
        }

        func numberOfRows(in tableView: NSTableView) -> Int { sortedRows.count }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else {
                sortedRows = content.rows; tableView.reloadData(); return
            }
            sortedRows = content.rows.sorted { a, b in
                let lv = a.values[key] ?? ""
                let rv = b.values[key] ?? ""
                let cmp: Bool
                if let ln = Double(lv), let rn = Double(rv) { cmp = ln < rn }
                else { cmp = lv.localizedStandardCompare(rv) == .orderedAscending }
                return descriptor.ascending ? cmp : !cmp
            }
            tableView.reloadData()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let columnID = tableColumn?.identifier else { return nil }

            if columnID == ArchiveNSTableView.iconColumnID {
                return makeIconCell(for: sortedRows[row])
            }

            let id = NSUserInterfaceItemIdentifier("cell")
            let cell: NSTextField
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
                cell = reused
            } else {
                cell = NSTextField()
                cell.identifier = id
                cell.isBordered = false
                cell.isEditable = false
                cell.backgroundColor = .clear
                cell.lineBreakMode = .byTruncatingTail
                cell.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
            }
            cell.stringValue = sortedRows[row].values[columnID.rawValue] ?? ""
            return cell
        }

        private func makeIconCell(for row: ArchiveRow) -> NSView {
            let imageView = NSImageView(image: typeIcon(for: row))
            imageView.imageAlignment = .alignCenter
            return imageView
        }

        // A frameset of light frames also has type="light", but uniquely has a numeric
        // "frames" count field. Individual frames don't have that field.
        // Framesets have a numeric "frames" count; individual frames and masters do not.
        private func isFrameset(_ row: ArchiveRow) -> Bool {
            row.values["frames"].flatMap(Int.init) != nil
        }

        private func typeIcon(for row: ArchiveRow) -> NSImage {
            if row.values["rejected"] == "true" {
                return icon("xmark.diamond.fill", colors: [.white, .systemRed])
            }
            if row.values["excluded"] == "true" {
                return icon("xmark.diamond.fill", colors: [.black, .systemYellow])
            }

            let type  = row.values["type"]?.lowercased()  ?? ""
            let level = row.values["level"]?.lowercased() ?? "raw"
            let symbol = frameTypeSymbolName(type: type, level: level, isFrameset: isFrameset(row))

            let isLight = type == "light"
            let colors: [NSColor] = isLight
                ? [.textBackgroundColor, .labelColor]
                : [.secondaryLabelColor]
            return icon(symbol, colors: colors)
        }

        private func icon(_ symbolName: String, colors: [NSColor]) -> NSImage {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: colors))
            return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) ?? NSImage()
        }

        private func compositeIcon(base: String, badge: String) -> NSImage {
            NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                let color = NSColor.secondaryLabelColor
                let baseConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
                NSImage(systemSymbolName: base, accessibilityDescription: nil)?
                    .withSymbolConfiguration(baseConfig)?
                    .draw(in: rect)

                let badgeSize = CGFloat(6)
                let badgeConfig = NSImage.SymbolConfiguration(pointSize: 5, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
                NSImage(systemSymbolName: badge, accessibilityDescription: nil)?
                    .withSymbolConfiguration(badgeConfig)?
                    .draw(in: NSRect(x: (rect.width - badgeSize) / 2,
                                    y: (rect.height - badgeSize) / 2,
                                    width: badgeSize, height: badgeSize))
                return true
            }
        }
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
            Label {
                Text("Reject")
            } icon: {
                Image(systemName: "xmark.diamond.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(isRejected ? Color.white : Color.primary,
                                     isRejected ? Color.red   : Color.primary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isRejected ? Color(nsColor: .controlColor) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(isRejected ? "Click to unreject" : "Reject frame")
    }
}
