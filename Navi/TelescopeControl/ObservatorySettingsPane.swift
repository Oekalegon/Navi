//
//  ObservatorySettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Observatory pane" (§4.2): lists the local `ObservatoryProfile` cache and shows
/// `ObservatoryEditForm` inline as detail content — a master-detail layout (NAVI-77), not a modal
/// sheet. See `ServerSettingsPane`'s doc comment for why this is a plain `HStack`, not
/// `NavigationSplitView` — the same window-toolbar-chrome conflict with the enclosing `TabView`.
/// Unlike `ServerSettingsPane`, add/edit require a live connection (`Observatory` isn't a local
/// model — it's fetched/saved server-side); "Remove" here only clears this local cache entry, it
/// does not delete the observatory from the server (INDIMCPKit has no delete-observatory call at
/// all).
struct ObservatorySettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    @Query(sort: \ObservatoryProfile.name) private var observatories: [ObservatoryProfile]

    // Keyed by `serverObservatoryID` (String), matching `ObservatoryEditForm.observatoryID` —
    // unrelated to `PersistentIdentifier`, since `Observatory` isn't itself a local model.
    private enum Selection: Hashable {
        case existing(String)
        case new
    }
    @State private var selection: Selection?
    @State private var isRefreshing = false

    private var selectedObservatory: ObservatoryProfile? {
        guard case .existing(let id) = selection else { return nil }
        return observatories.first { $0.serverObservatoryID == id }
    }

    private var isConnected: Bool { telescope.state == .connected }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Keyed on `telescope.state`, not a plain `.task { }` — this pane's `.id(Tab.observatories)`
        // keeps it alive across tab switches, so a one-shot `.task` would only ever refresh once and
        // never again after a later connect. Previously nothing in this pane ever called
        // `listObservatories()` at all — the cache only filled in if the toolbar's rig/observatory
        // picker happened to have been opened first, which a local store reset makes obvious is
        // wrong: Settings should be able to populate its own list.
        .task(id: telescope.state) {
            guard isConnected else { return }
            isRefreshing = true
            await ObservatoryCacheRefresher.refresh(telescope: telescope, modelContext: modelContext)
            isRefreshing = false
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Observatories",
                isAddDisabled: !isConnected,
                addHelp: isConnected ? "Add Observatory" : "Connect to a telescope server first",
                onAdd: { selection = .new },
                isRemoveDisabled: selectedObservatory == nil,
                removeHelp: "Remove from this local list",
                onRemove: { if let observatory = selectedObservatory { remove(observatory) } }
            ) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else if !isConnected {
                    Text("Connect to add or edit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            if observatories.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(observatories) { observatory in
                        row(for: observatory)
                            .tag(Selection.existing(observatory.serverObservatoryID))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .existing(let id):
            if observatories.contains(where: { $0.serverObservatoryID == id }) {
                ObservatoryEditForm(observatoryID: id)
                    .id(id)
            } else {
                placeholder
            }
        case .new:
            // Same quick-create the toolbar's rig/observatory picker offers (§4.1) — reused rather
            // than reimplemented, so there's one place that fetches a location, prompts for a name,
            // and saves it. Shown above the blank form as an alternative to authoring one by hand;
            // picking it jumps straight to the created observatory.
            if CurrentLocationFetcher.isAvailable {
                VStack(alignment: .leading, spacing: 0) {
                    CurrentLocationQuickCreateRow(
                        isConnected: isConnected,
                        observatories: observatories,
                        onObservatorySelected: { selection = .existing($0) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    Divider()
                        .padding(.top, 8)
                    ObservatoryEditForm(observatoryID: nil)
                }
            } else {
                ObservatoryEditForm(observatoryID: nil)
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("Select an observatory, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    private func remove(_ observatory: ObservatoryProfile) {
        if selection == .existing(observatory.serverObservatoryID) {
            selection = nil
        }
        modelContext.delete(observatory)
        try? modelContext.save()
    }
}
