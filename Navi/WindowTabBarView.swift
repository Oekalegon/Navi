//
//  WindowTabBarView.swift
//  Navi
//
//  NAVI-70: the in-app tab strip shown above a window's pane content. macOS tab convention (not
//  the pane-header convention) — the close "x" sits on the trailing edge of the label, shown on
//  hover, unlike a pane header's leading-edge close button (see macos-ui-conventions memory).
//

import SwiftUI

struct WindowTabBarView: View {
    let windowID: UUID
    @Binding var tabs: [TabDescriptor]
    @Binding var selectedTabID: UUID
    let onAdd: () -> Void
    let onClose: (UUID) -> Void
    let onMoveLeft: (UUID) -> Void
    let onMoveRight: (UUID) -> Void
    let onMoveToNewWindow: (UUID) -> Void
    let onMoveToWindow: (UUID, UUID) -> Void

    @State private var hoveredTabID: UUID?
    @State private var renamingTabID: UUID?
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .padding(.horizontal, 6)
            .help("New Tab")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private func tabButton(_ tab: TabDescriptor) -> some View {
        let isSelected = tab.id == selectedTabID
        let isRenaming = renamingTabID == tab.id

        HStack(spacing: 4) {
            if isRenaming {
                TextField("Tab Name", text: $renameText, onCommit: { commitRename(tab.id) })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(minWidth: 60)
                    .onExitCommand { renamingTabID = nil }
            } else {
                Text(tab.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }

            if tabs.count > 1, !isRenaming, hoveredTabID == tab.id || isSelected {
                Button(action: { onClose(tab.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .opacity(hoveredTabID == tab.id ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in hoveredTabID = hovering ? tab.id : nil }
        .onTapGesture(count: 2) { beginRename(tab) }
        .onTapGesture { selectedTabID = tab.id }
        .contextMenu {
            Button("Rename") { beginRename(tab) }
            if tabs.count > 1 {
                Button("Close Tab") { onClose(tab.id) }
            }
            Divider()
            Button("Move Left") { onMoveLeft(tab.id) }
                .disabled(tabs.first?.id == tab.id)
            Button("Move Right") { onMoveRight(tab.id) }
                .disabled(tabs.last?.id == tab.id)
            if tabs.count > 1 {
                Divider()
                Button("Move to New Window") { onMoveToNewWindow(tab.id) }
                let otherWindows = WindowRegistry.shared.otherWindows(excluding: windowID)
                if !otherWindows.isEmpty {
                    Menu("Move to Window") {
                        ForEach(otherWindows, id: \.id) { window in
                            Button(window.title) { onMoveToWindow(tab.id, window.id) }
                        }
                    }
                }
            }
        }
    }

    private func beginRename(_ tab: TabDescriptor) {
        renameText = tab.name
        renamingTabID = tab.id
    }

    private func commitRename(_ tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { tabs[index].name = trimmed }
        renamingTabID = nil
    }
}
