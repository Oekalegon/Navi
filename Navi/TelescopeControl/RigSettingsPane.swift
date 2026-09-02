//
//  RigSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Rig pane" (§4.2): lists the local `RigProfile` library and shows `RigEditForm`
/// inline as detail content — a master-detail layout (NAVI-77), not a modal sheet. See
/// `ServerSettingsPane`'s doc comment for why this is a plain `HStack`, not `NavigationSplitView`
/// — the same window-toolbar-chrome conflict with the enclosing `TabView`.
/// Unlike `ObservatorySettingsPane`, `RigProfile` *is* a local SwiftData model (it tracks which
/// library entities compose the rig, §4.3) — so this list itself needs no connection; only saving
/// a rig (which pushes it via `saveRig`) does, enforced by `RigEditForm`.
struct RigSettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RigProfile.name) private var rigs: [RigProfile]

    // `.new` shows a blank RigEditForm without inserting a draft RigProfile into the library —
    // it only gets inserted once the user actually saves (RigEditForm.upsertLocalRig).
    private enum Selection: Hashable {
        case existing(PersistentIdentifier)
        case new
    }
    @State private var selection: Selection?
    @State private var rigPendingDeletion: RigProfile?

    private var selectedRigID: PersistentIdentifier? {
        if case .existing(let id) = selection { return id }
        return nil
    }
    private var selectedRig: RigProfile? {
        selectedRigID.flatMap { id in rigs.first { $0.persistentModelID == id } }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Delete “\(rigPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { rigPendingDeletion != nil },
                set: { if !$0 { rigPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let rig = rigPendingDeletion { delete(rig) }
                rigPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { rigPendingDeletion = nil }
        } message: {
            Text("This only removes the rig from Navi's local library — it stays saved on the server.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Rigs",
                addHelp: "Add Rig",
                onAdd: { selection = .new },
                isRemoveDisabled: selectedRigID == nil,
                removeHelp: "Remove the selected rig",
                onRemove: { if let rig = selectedRig { rigPendingDeletion = rig } }
            )
            Divider()
            if rigs.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(rigs) { rig in
                        row(for: rig)
                            .tag(Selection.existing(rig.persistentModelID))
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
            if let rig = rigs.first(where: { $0.persistentModelID == id }) {
                RigEditForm(rig: rig, onSaved: { selection = .existing($0.persistentModelID) }, onFinished: { selection = nil })
                    .id(id)
            } else {
                placeholder
            }
        case .new:
            RigEditForm(rig: nil, onSaved: { selection = .existing($0.persistentModelID) }, onFinished: { selection = nil })
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("Select a rig, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No rigs yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add your first rig from the equipment library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for rig: RigProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rig.name)
                        .font(.body)
                    if rig.hasStaleLibraryReferences {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                            .help("A referenced library entity changed since this rig was last saved to the server.")
                    }
                }
                Text(componentSummary(for: rig))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func componentSummary(for rig: RigProfile) -> String {
        var parts: [String] = []
        if rig.mount != nil { parts.append("Mount") }
        if rig.opticalAssembly != nil { parts.append("OTA") }
        if rig.guideOpticalAssembly != nil { parts.append("Guide OTA") }
        if rig.imagingTrain != nil { parts.append("Imaging Train") }
        if rig.guideCamera != nil { parts.append("Guide Camera") }
        let standaloneCount = [rig.powerHub, rig.flatScreen, rig.dewHeater, rig.observatoryControl].compactMap { $0 }.count
        if standaloneCount > 0 { parts.append("\(standaloneCount) other") }
        return parts.isEmpty ? "No components yet" : parts.joined(separator: " · ")
    }

    private func delete(_ rig: RigProfile) {
        // Local-library-only removal, matching `ObservatorySettingsPane.remove(_:)` — there's no
        // delete-rig call in INDIMCPKit, so the server-side `Rig` file is untouched.
        if selection == .existing(rig.persistentModelID) {
            selection = nil
        }
        modelContext.delete(rig)
        try? modelContext.save()
    }
}
