//
//  ImagingTrainSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// The Settings "Imaging Train pane": lists the local `ImagingTrainProfile` library and shows
/// `ImagingTrainEditForm` inline as detail content — same master-detail shape as `RigSettingsPane`
/// (plain `HStack`, not `NavigationSplitView`, for the same window-toolbar-chrome reason). A third
/// top-level tab alongside Equipment and Rigs: an imaging train is a *composition* of equipment
/// (Camera/Filter Wheel/Rotator, each independently managed in the Equipment pane), the same way a
/// Rig composes Mount/Optical Assembly/etc. — it isn't itself a piece of equipment, so it doesn't
/// belong in `EquipmentSettingsPane`'s list.
struct ImagingTrainSettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImagingTrainProfile.name) private var imagingTrains: [ImagingTrainProfile]

    /// No `.new` case: "+" inserts a blank train and selects it (the macOS Settings convention),
    /// so there's no unsaved draft state to model.
    private enum Selection: Hashable {
        case existing(PersistentIdentifier)
    }
    @State private var selection: Selection?
    @State private var pendingDeletion: (name: String, action: () -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                pendingDeletion?.action()
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Any rig using this imaging train will have that role cleared, not deleted.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Imaging Trains",
                addHelp: "Add Imaging Train",
                onAdd: { insert() },
                isRemoveDisabled: selection == nil,
                removeHelp: "Remove the selected imaging train",
                onRemove: { if case .existing(let id) = selection { confirmDelete(id) } }
            )
            Divider()
            if imagingTrains.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(imagingTrains) { train in
                        row(for: train)
                            .tag(Selection.existing(train.persistentModelID))
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
            if let train = imagingTrains.first(where: { $0.persistentModelID == id }) {
                ImagingTrainEditForm(imagingTrain: train)
                    .id(id)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("Select an imaging train, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No imaging trains yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Combine a Camera, Filter Wheel, and Rotator from the Equipment pane.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for train: ImagingTrainProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(train.displayName)
                    .font(.body)
                Text(componentSummary(for: train))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func componentSummary(for train: ImagingTrainProfile) -> String {
        var parts: [String] = []
        if train.camera != nil { parts.append("Camera") }
        if train.filterWheel != nil { parts.append("Filter Wheel") }
        if train.rotator != nil { parts.append("Rotator") }
        return parts.isEmpty ? "No components yet" : parts.joined(separator: " · ")
    }

    /// Inserts a blank train and selects it — edits commit as they're made, so there's no
    /// separate "new, unsaved" state.
    private func insert() {
        let new = ImagingTrainProfile(name: "")
        modelContext.insert(new)
        try? modelContext.save()
        selection = .existing(new.persistentModelID)
    }

    private func confirmDelete(_ id: PersistentIdentifier) {
        guard let train = imagingTrains.first(where: { $0.persistentModelID == id }) else { return }
        pendingDeletion = (train.displayName, {
            if selection == .existing(id) { selection = nil }
            modelContext.delete(train)
            try? modelContext.save()
        })
    }
}
