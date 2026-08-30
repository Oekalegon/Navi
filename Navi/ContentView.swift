//
//  ContentView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var group: WindowTabGroup
    @State private var paneManagers: [UUID: PaneManager]
    @State private var settings = SettingsManager.shared

    init(group: WindowTabGroup) {
        _group = State(initialValue: group)
        var managers: [UUID: PaneManager] = [:]
        for tab in group.tabs {
            managers[tab.id] = WindowRegistry.shared.adopt(WindowToken(id: tab.id, rootType: .aiAssistant))
        }
        _paneManagers = State(initialValue: managers)
    }

    private var selectedPaneManager: PaneManager? {
        paneManagers[group.selectedTabID]
    }

    // True for the window holding the very first entry WindowRegistry ever registered — the
    // same "am I the main window" test ContentView used pre-NAVI-70, just phrased in terms of
    // this window's tabs instead of a single bare token.
    private var isMainWindow: Bool {
        guard let firstEntryID = WindowRegistry.shared.entries.first?.id else { return false }
        return group.tabs.contains { $0.id == firstEntryID }
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowTabBarView(
                tabs: $group.tabs,
                selectedTabID: $group.selectedTabID,
                onAdd: addTab,
                onClose: closeTab,
                onMoveLeft: { moveTab($0, by: -1) },
                onMoveRight: { moveTab($0, by: 1) }
            )
            Divider()
            if let paneManager = selectedPaneManager {
                SplitPaneView(pane: paneManager.rootPane, paneManager: paneManager)
                    .toolbar { toolbarContent(for: paneManager) }
                    .environment(paneManager)
                    .environment(settings)
                    .focusedSceneValue(\.paneManager, paneManager)
                    .id(paneManager.tabID)
            }
        }
        .onChange(of: group.tabs) { persistGroupIfMainWindow() }
        .onChange(of: group.selectedTabID) { persistGroupIfMainWindow() }
        .onDisappear {
            for tab in group.tabs {
                paneManagers[tab.id]?.saveLayout()
                WindowRegistry.shared.release(tab.id)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(for paneManager: PaneManager) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 6) {
                Button(action: {}) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 13))
                }
                .controlSize(.small)

                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                }
                .controlSize(.small)

                PaneToggleButton(
                    icon: "sparkles",
                    title: "AI Assistant",
                    isVisible: paneManager.isAIAssistantVisible
                ) { paneManager.toggleAIAssistant() }

                PaneToggleButton(
                    icon: "archivebox",
                    title: "Archive Viewer",
                    isVisible: paneManager.isArchiveViewerVisible
                ) { paneManager.toggleArchiveViewer() }

                PaneToggleButton(
                    icon: "photo",
                    title: "FITS Viewer",
                    isVisible: paneManager.isFITSViewerVisible
                ) { paneManager.toggleFITSViewer() }
            }
        }

        ToolbarItem(placement: .automatic) {
            TelescopeToolbarButton(paneManager: paneManager)
        }
    }

    private func addTab() {
        let tabID = group.addingTab()
        paneManagers[tabID] = WindowRegistry.shared.adopt(WindowToken(id: tabID, rootType: .aiAssistant))
    }

    private func closeTab(_ tabID: UUID) {
        guard group.closingTab(tabID) else { return }
        paneManagers[tabID] = nil
        WindowRegistry.shared.release(tabID)
    }

    private func moveTab(_ tabID: UUID, by offset: Int) {
        group.movingTab(tabID, by: offset)
    }

    private func persistGroupIfMainWindow() {
        guard isMainWindow else { return }
        group.persistAsMainWindow()
    }
}

// Toolbar toggle reflecting whether a pane is currently visible.
private struct PaneToggleButton: View {
    let icon: String
    let title: String
    let isVisible: Bool
    let toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isVisible }, set: { _ in toggle() })) {
            Image(systemName: icon)
                .font(.system(size: 13))
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help(isVisible ? "Hide \(title)" : "Show \(title)")
    }
}
