//
//  ContentView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI

struct ContentView: View {
    let windowID: UUID
    @State private var box: TabGroupBox
    @State private var paneManagers: [UUID: PaneManager]
    @State private var settings = SettingsManager.shared
    @Environment(\.openWindow) private var openWindow

    init(group: WindowTabGroup) {
        windowID = group.id
        let box = WindowRegistry.shared.adoptWindow(group)
        _box = State(initialValue: box)
        var managers: [UUID: PaneManager] = [:]
        for tab in box.group.tabs {
            managers[tab.id] = WindowRegistry.shared.adopt(WindowToken(id: tab.id, rootType: .aiAssistant))
        }
        _paneManagers = State(initialValue: managers)
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowTabBarView(
                windowID: windowID,
                tabs: $box.group.tabs,
                selectedTabID: $box.group.selectedTabID,
                onAdd: addTab,
                onClose: closeTab,
                onMoveLeft: { moveTab($0, by: -1) },
                onMoveRight: { moveTab($0, by: 1) },
                onMoveToNewWindow: moveTabToNewWindow,
                onMoveToWindow: { moveTab($0, toWindow: $1) }
            )
            Divider()
            if let paneManager = paneManagers[box.group.selectedTabID] {
                SplitPaneView(pane: paneManager.rootPane, paneManager: paneManager)
                    .toolbar { toolbarContent(for: paneManager) }
                    .environment(paneManager)
                    .environment(settings)
                    .focusedSceneValue(\.paneManager, paneManager)
                    .id(paneManager.tabID)
            }
        }
        .onChange(of: box.group.tabs) { syncPaneManagers() }
        .onChange(of: box.group) { WindowRegistry.shared.persistAllWindows() }
        .task { openRemainingWindowsAtLaunchIfNeeded() }
        .onDisappear {
            for tab in box.group.tabs {
                paneManagers[tab.id]?.saveLayout()
                WindowRegistry.shared.release(tab.id)
            }
            WindowRegistry.shared.releaseWindow(windowID)
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

                PaneToggleButton(
                    icon: "terminal",
                    title: "Telescope Messages",
                    isVisible: paneManager.isTelescopeMessagesVisible
                ) { paneManager.toggleTelescopeMessages() }
            }
        }

        ToolbarItem(placement: .automatic) {
            TelescopeToolbarButton(paneManager: paneManager)
        }
    }

    private func addTab() {
        let tabID = box.group.addingTab()
        paneManagers[tabID] = WindowRegistry.shared.adopt(WindowToken(id: tabID, rootType: .aiAssistant))
    }

    private func closeTab(_ tabID: UUID) {
        guard box.group.closingTab(tabID) else { return }
        paneManagers[tabID] = nil
        WindowRegistry.shared.release(tabID)
    }

    private func moveTab(_ tabID: UUID, by offset: Int) {
        box.group.movingTab(tabID, by: offset)
    }

    // Pops a tab out into a brand-new window. The tab's PaneManager stays registered under the
    // same id throughout — only ownership (which window's tab list names it) changes — so the new
    // window's ContentView.init finds and reuses the exact same, already-adopted manager.
    private func moveTabToNewWindow(_ tabID: UUID) {
        guard box.group.tabs.count > 1,
              let tab = box.group.tabs.first(where: { $0.id == tabID }) else { return }
        box.group.closingTab(tabID)
        openWindow(value: WindowTabGroup.single(tabID: tab.id, name: tab.name))
    }

    private func moveTab(_ tabID: UUID, toWindow destinationID: UUID) {
        guard let tab = box.group.tabs.first(where: { $0.id == tabID }) else { return }
        WindowRegistry.shared.moveTab(tab, toWindow: destinationID)
    }

    // Reconciles the local PaneManager cache after box.group.tabs changes for ANY reason —
    // add/close/reorder here, or a tab moved in/out from another window mutating the same shared
    // TabGroupBox instance. Never releases a WindowRegistry entry itself: that decision belongs to
    // whichever action actually discards a tab (closeTab), not this passive sync.
    private func syncPaneManagers() {
        let currentIDs = Set(box.group.tabs.map(\.id))
        for tab in box.group.tabs where paneManagers[tab.id] == nil {
            paneManagers[tab.id] = WindowRegistry.shared.adopt(WindowToken(id: tab.id, rootType: .aiAssistant))
        }
        paneManagers = paneManagers.filter { currentIDs.contains($0.key) }
    }

    // One-shot, launch-only step: the very first window to appear reopens every other
    // previously-open window from the persisted list (NaviApp's defaultValue only hands the first
    // one to its own WindowGroup). WindowRegistry's gate ensures this never re-runs for windows
    // opened afterwards, including the ones this very call opens.
    private func openRemainingWindowsAtLaunchIfNeeded() {
        guard WindowRegistry.shared.beginLaunchWindowRestorationIfNeeded() else { return }
        for group in WindowTabGroup.loadAllPersisted().dropFirst() {
            openWindow(value: group)
        }
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
