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

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: paneManager.archiveContent?.iconName ?? "archivebox")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            Text(paneManager.archiveContent?.title ?? "Archive Browser")
                .font(.headline)

            Spacer()

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
                ArchiveTableView(content: content)
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
}

struct ArchiveTableView: View {
    let content: ArchiveViewerContent

    var body: some View {
        VStack(spacing: 0) {
            ArchiveNSTableView(content: content)

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

        addColumns(to: tableView, columns: content.columns)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let currentColumns = tableView.tableColumns.map { $0.identifier.rawValue }
        if currentColumns != content.columns {
            for col in tableView.tableColumns { tableView.removeTableColumn(col) }
            addColumns(to: tableView, columns: content.columns)
        }
        context.coordinator.update(content: content, tableView: tableView)
    }

    private func addColumns(to tableView: NSTableView, columns: [String]) {
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

        init(content: ArchiveViewerContent) {
            self.content = content
            self.sortedRows = content.rows
        }

        func update(content: ArchiveViewerContent, tableView: NSTableView) {
            self.content = content
            self.sortedRows = content.rows
            tableView.reloadData()
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
            let columnKey = tableColumn?.identifier.rawValue ?? ""
            cell.stringValue = sortedRows[row].values[columnKey] ?? ""
            return cell
        }
    }
}
