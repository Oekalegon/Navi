//
//  TelescopeSelectionSheet.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// The toolbar's "selection button" modal (§4.1): pick an Observatory and a Rig, confirming
/// updates `TelescopeSessionManager`'s *armed* selection — it never connects anything itself.
///
/// Both lists are always populated from the local equipment library (`RigProfile`/
/// `ObservatoryProfile`) so the picker has something to show even before ever connecting.
///
/// **Rigs are selectable offline; Observatories aren't.** Arming a Rig is a purely local act — a
/// `RigProfile` is Navi's own record (§4.3) and arming only notes which one you intend to use, so
/// requiring a connection first was a chicken-and-egg: the natural step after creating your first
/// rig is to connect *to that rig*, but the rig couldn't be armed until you were already
/// connected, and Connect needs an armed rig. An `Observatory` is genuinely server-side (fetched
/// via `listObservatories`), so picking a different one still needs a live session; those rows
/// stay dimmed while disconnected rather than disappearing.
struct TelescopeSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared

    @Query(sort: \RigProfile.name) private var rigs: [RigProfile]
    @Query(sort: \ObservatoryProfile.name) private var observatories: [ObservatoryProfile]

    @State private var selectedRigID: String?
    @State private var selectedObservatoryID: String?
    @State private var isRefreshingObservatories = false

    private var isConnected: Bool { telescope.state == .connected }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                column(
                    title: "Observatory",
                    isEmpty: observatories.isEmpty && !CurrentLocationFetcher.isAvailable,
                    isRefreshing: isRefreshingObservatories,
                    emptyMessage: isConnected ? "No observatories yet." : "Connect to load observatories."
                ) {
                    if CurrentLocationFetcher.isAvailable {
                        CurrentLocationQuickCreateRow(
                            isConnected: isConnected,
                            observatories: observatories,
                            onObservatorySelected: { selectedObservatoryID = $0 }
                        )
                    }
                    ForEach(observatories) { observatory in
                        row(
                            title: observatory.name,
                            isSelected: selectedObservatoryID == observatory.serverObservatoryID,
                            isEnabled: isConnected
                        ) {
                            selectedObservatoryID = observatory.serverObservatoryID
                        }
                    }
                }

                Divider()

                column(
                    title: "Rig",
                    isEmpty: rigs.isEmpty,
                    isRefreshing: false,
                    emptyMessage: "No rigs in the equipment library yet.",
                    requiresConnection: false
                ) {
                    ForEach(rigs) { rig in
                        row(title: rig.name, isSelected: selectedRigID == rig.serverRigID) {
                            selectedRigID = rig.serverRigID
                            // A Rig with a default Observatory pre-arms it too, matching §4.1's
                            // "your current setup" pairing — still overridable before confirming.
                            if let defaultObservatoryID = rig.defaultObservatoryID {
                                selectedObservatoryID = defaultObservatoryID
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 380)
        .onAppear {
            selectedRigID = telescope.armedRigID
            selectedObservatoryID = telescope.armedObservatoryID
            if isConnected {
                Task { await refreshObservatories() }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Select Observatory & Rig")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("Confirm") {
                telescope.armedObservatoryID = selectedObservatoryID
                telescope.armedRigID = selectedRigID
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func column(
        title: String,
        isEmpty: Bool,
        isRefreshing: Bool,
        emptyMessage: String,
        requiresConnection: Bool = true,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        rows()
                    }
                    .padding(6)
                }
            }

            if requiresConnection && !isConnected {
                Text("Connect to change this selection.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(
        title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        select: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.callout)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.5)
        .allowsHitTesting(isEnabled)
        .onTapGesture { select() }
    }

    private func refreshObservatories() async {
        isRefreshingObservatories = true
        defer { isRefreshingObservatories = false }
        do {
            let summaries = try await telescope.listObservatories()
            for summary in summaries {
                if let existing = observatories.first(where: { $0.serverObservatoryID == summary.id }) {
                    existing.name = summary.name
                    existing.cachedAt = .now
                } else {
                    modelContext.insert(ObservatoryProfile(serverObservatoryID: summary.id, name: summary.name))
                }
            }
            try modelContext.save()
        } catch {
            // I-4: funnel into TelescopeSessionManager's one error-surfacing property rather than
            // dropping this silently — a failed background refresh should still be visible.
            telescope.errorMessage = "Couldn't refresh the observatory list: \(TelescopeSessionManager.describe(error))"
        }
    }
}
