//
//  RigSettingsSheet.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Rig pane" (§4.2): lists the local `RigProfile` library and opens `RigEditForm`
/// to add/edit. Unlike `ObservatorySettingsSheet`, `RigProfile` *is* a local SwiftData model (it
/// tracks which library entities compose the rig, §4.3) — so this list itself needs no
/// connection; only saving a rig (which pushes it via `saveRig`) does, enforced by `RigEditForm`.
struct RigSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RigProfile.name) private var rigs: [RigProfile]

    @State private var editingRig: RigProfile?
    @State private var isPresentingNewRig = false
    @State private var rigPendingDeletion: RigProfile?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rigs.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(rigs) { rig in
                        row(for: rig)
                    }
                }
            }
        }
        .frame(width: 460, height: 400)
        .sheet(item: $editingRig) { rig in
            RigEditForm(rig: rig)
        }
        .sheet(isPresented: $isPresentingNewRig) {
            RigEditForm(rig: nil)
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

    private var header: some View {
        HStack {
            Text("Rigs")
                .font(.headline)
            Spacer()
            Button(action: { isPresentingNewRig = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Add Rig")
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
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
            Button(action: { rigPendingDeletion = rig }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete Rig")
        }
        .contentShape(Rectangle())
        .onTapGesture { editingRig = rig }
    }

    private func componentSummary(for rig: RigProfile) -> String {
        var parts: [String] = []
        if rig.mount != nil { parts.append("Mount") }
        if rig.opticalAssembly != nil { parts.append("OTA") }
        if rig.guideOpticalAssembly != nil { parts.append("Guide OTA") }
        if rig.imagingTrain != nil { parts.append("Imaging Train") }
        if rig.guideCamera != nil { parts.append("Guide Camera") }
        if !rig.standaloneComponents.isEmpty { parts.append("\(rig.standaloneComponents.count) other") }
        return parts.isEmpty ? "No components yet" : parts.joined(separator: " · ")
    }

    private func delete(_ rig: RigProfile) {
        // Local-library-only removal, matching `ObservatorySettingsSheet.remove(_:)` — there's no
        // delete-rig call in INDIMCPKit, so the server-side `Rig` file is untouched.
        modelContext.delete(rig)
        try? modelContext.save()
    }
}
