//
//  TelescopeCommands.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1. NAVI-64: a "Telescope" menu-bar menu mirroring
//  TelescopeToolbarButton's Connect/Disconnect — reachable without hunting for the toolbar
//  button, and with a keyboard shortcut. Shares ArmedRigConnector.connect(...) with the toolbar
//  button so the two entry points can't drift.
//

import SwiftUI
import SwiftData

struct TelescopeCommands: Commands {
    @State private var telescope = TelescopeSessionManager.shared
    @Environment(\.modelContext) private var modelContext
    // The focused window's PaneManager (ContentView.focusedSceneValue) — nil if no Navi window is
    // key (e.g. only the Settings window is focused), in which case Connect still works but won't
    // auto-open a Dashboard anywhere.
    @FocusedValue(\.paneManager) private var paneManager

    var body: some Commands {
        CommandMenu("Telescope") {
            connectMenuItem
        }
    }

    @ViewBuilder
    private var connectMenuItem: some View {
        switch telescope.state {
        case .disconnected:
            Button("Connect") { connect() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(telescope.armedRigID == nil)
        case .connecting:
            Text("Connecting…")
        case .connected:
            Button("Disconnect") { Task { await telescope.disconnect() } }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }

    private func connect() {
        Task {
            await ArmedRigConnector.connect(telescope: telescope, modelContext: modelContext, paneManager: paneManager)
        }
    }
}
