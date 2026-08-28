//
//  ObservatorySettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Observatory pane" (§4.2): lists the local `ObservatoryProfile` cache and opens
/// `ObservatoryEditForm` to add/edit. Unlike `ServerSettingsPane`, add/edit require a live
/// connection (`Observatory` isn't a local model — it's fetched/saved server-side); "Remove" here
/// only clears this local cache entry, it does not delete the observatory from the server
/// (INDIMCPKit has no delete-observatory call at all).
struct ObservatorySettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    @Query(sort: \ObservatoryProfile.name) private var observatories: [ObservatoryProfile]

    // Only ever set to a real id from row(for:) below — the "add new" case is handled
    // separately by isPresentingNewObservatory, so a plain optional (nil = no sheet) is enough
    // here; ObservatoryEditForm's own `observatoryID: String?` parameter (nil = new) is a
    // different, unrelated optional belonging to a different call site.
    @State private var editingObservatoryID: String?
    @State private var isPresentingNewObservatory = false

    private var isConnected: Bool { telescope.state == .connected }

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Observatories",
                isAddDisabled: !isConnected,
                addHelp: isConnected ? "Add Observatory" : "Connect to a telescope server first",
                onAdd: { isPresentingNewObservatory = true }
            ) {
                if !isConnected {
                    Text("Connect to add or edit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            if observatories.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(observatories) { observatory in
                        row(for: observatory)
                    }
                }
            }
        }
        .sheet(isPresented: presentingEditForm) {
            if let editingObservatoryID {
                ObservatoryEditForm(observatoryID: editingObservatoryID)
            }
        }
        .sheet(isPresented: $isPresentingNewObservatory) {
            ObservatoryEditForm(observatoryID: nil)
        }
    }

    private var presentingEditForm: Binding<Bool> {
        Binding(
            get: { editingObservatoryID != nil },
            set: { if !$0 { editingObservatoryID = nil } }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe.americas")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No observatories yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(isConnected
                 ? "Add your first observatory location."
                 : "Connect to a telescope server to add one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for observatory: ObservatoryProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(observatory.name)
                    .font(.body)
                Text("\(observatory.latitudeDeg, specifier: "%.4f")°, \(observatory.longitudeDeg, specifier: "%.4f")° · \(observatory.elevationMeters, specifier: "%.0f") m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { remove(observatory) }) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove from this local list — stays saved on the server")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isConnected else { return }
            editingObservatoryID = observatory.serverObservatoryID
        }
    }

    private func remove(_ observatory: ObservatoryProfile) {
        modelContext.delete(observatory)
        try? modelContext.save()
    }
}
