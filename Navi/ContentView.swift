//
//  ContentView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI

struct ContentView: View {
    let windowID: UUID
    @State private var paneManager: PaneManager
    @State private var settings = SettingsManager.shared
    @State private var showingSettings = false

    init(windowID: UUID) {
        self.windowID = windowID
        _paneManager = State(initialValue: WindowRegistry.shared.adopt(windowID))
    }

    var body: some View {
        SplitPaneView(pane: paneManager.rootPane, paneManager: paneManager)
            .toolbar {
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
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                    }
                    .controlSize(.small)
                }
            }
            .environment(paneManager)
            .environment(settings)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(settings)
            }
            .onDisappear { WindowRegistry.shared.release(windowID) }
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
