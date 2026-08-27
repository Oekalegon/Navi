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
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    @State private var showingSelection = false

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
        }
        .sheet(isPresented: $showingSelection) {
            TelescopeSelectionSheet()
        }
    }

    private var selectionLabel: String {
        switch (armedObservatoryName, armedRigName) {
        case let (observatory?, rig?): return "\(observatory) · \(rig)"
        case let (nil, rig?): return rig
        case let (observatory?, nil): return observatory
        case (nil, nil): return "Select Rig…"
        }
    }

    private var armedObservatoryName: String? {
        guard let id = telescope.armedObservatoryID else { return nil }
        let descriptor = FetchDescriptor<ObservatoryProfile>(
            predicate: #Predicate { $0.serverObservatoryID == id }
        )
        return try? modelContext.fetch(descriptor).first?.name
    }

    private var armedRigName: String? {
        guard let id = telescope.armedRigID else { return nil }
        let descriptor = FetchDescriptor<RigProfile>(predicate: #Predicate { $0.serverRigID == id })
        return try? modelContext.fetch(descriptor).first?.name
    }

    @ViewBuilder
    private var connectButton: some View {
        switch telescope.state {
        case .disconnected:
            Button("Connect") { connect() }
                .controlSize(.small)
                .disabled(telescope.armedRigID == nil)
                .help(telescope.armedRigID == nil ? "Select a rig first" : "Connect")
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
        guard let rigID = telescope.armedRigID else { return }
        let descriptor = FetchDescriptor<RigProfile>(predicate: #Predicate { $0.serverRigID == rigID })
        guard let rig = try? modelContext.fetch(descriptor).first, let server = rig.defaultServer else {
            telescope.errorMessage = "The selected rig has no default server configured."
            return
        }
        Task { await telescope.connect(server: server, rigID: rigID) }
    }
}
