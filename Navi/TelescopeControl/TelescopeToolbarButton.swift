//
//  TelescopeToolbarButton.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1.
//

import SwiftUI
import SwiftData

/// The toolbar's telescope controls (§4.1): a selection button showing the current armed
/// Observatory/Rig (e.g. "Home Backyard · My EQ6-R Rig"), plus a separate, explicit Connect/
/// Disconnect button. Picking a Rig/Observatory in `TelescopeSelectionSheet` only arms the
/// choice — it never connects anything; Connect is always a distinct action here.
struct TelescopeToolbarButton: View {
    let paneManager: PaneManager
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    @State private var showingSelection = false
    @Query(sort: \ServerProfile.name) private var servers: [ServerProfile]

    // Resolved once per armed-id change, not re-fetched on every body re-render (e.g. every
    // telescope.state change) the way a plain computed property reading modelContext would.
    @State private var armedObservatoryName: String?
    @State private var armedRigName: String?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { showingSelection = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(selectionLabel)
                }
                .font(.system(size: 12))
            }
            .controlSize(.small)
            .help("Select Observatory & Rig")

            connectButton
            TelescopeErrorIndicator()
            TelescopeConflictIndicator()
        }
        .sheet(isPresented: $showingSelection) {
            TelescopeSelectionSheet()
        }
        .onAppear { refreshArmedNames() }
        .onChange(of: telescope.armedObservatoryID) { refreshArmedNames() }
        .onChange(of: telescope.armedRigID) { refreshArmedNames() }
    }

    private var selectionLabel: String {
        switch (armedObservatoryName, armedRigName) {
        case let (observatory?, rig?): return "\(observatory) · \(rig)"
        case let (nil, rig?): return rig
        case let (observatory?, nil): return observatory
        case (nil, nil): return "Select Rig…"
        }
    }

    private func refreshArmedNames() {
        armedObservatoryName = telescope.armedObservatoryID.flatMap { id in
            let descriptor = FetchDescriptor<ObservatoryProfile>(
                predicate: #Predicate { $0.serverObservatoryID == id }
            )
            return try? modelContext.fetch(descriptor).first?.name
        }
        armedRigName = telescope.armedRigID.flatMap { id in
            let descriptor = FetchDescriptor<RigProfile>(predicate: #Predicate { $0.serverRigID == id })
            return try? modelContext.fetch(descriptor).first?.name
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        switch telescope.state {
        case .disconnected:
            if telescope.armedRigID != nil {
                Button("Connect") { connect() }
                    .controlSize(.small)
            } else if !servers.isEmpty {
                // NAVI-67: no Rig armed yet — connect straight to a bare Server instead of
                // forcing a detour through Settings first. Once connected, RigAutoMatcher (via
                // BareServerConnector) arms whichever local Rig matches the live devices, so a
                // subsequent Connect goes through the normal rig-bound path above.
                Menu("Connect to Server…") {
                    ForEach(servers) { server in
                        Button(server.name) { connectToServer(server) }
                    }
                }
                .controlSize(.small)
                .help("No rig selected yet — connect to a server directly, then create or match a rig")
            } else {
                Button("Connect") {}
                    .controlSize(.small)
                    .disabled(true)
                    .help("Select a rig first, or add a server in Settings")
            }
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .connected:
            Button("Disconnect") { Task { await telescope.disconnect() } }
                .controlSize(.small)
        }
    }

    private func connect() {
        Task {
            await ArmedRigConnector.connect(telescope: telescope, modelContext: modelContext, paneManager: paneManager)
        }
    }

    private func connectToServer(_ server: ServerProfile) {
        Task {
            await BareServerConnector.connect(server: server, telescope: telescope, modelContext: modelContext, paneManager: paneManager)
        }
    }
}
