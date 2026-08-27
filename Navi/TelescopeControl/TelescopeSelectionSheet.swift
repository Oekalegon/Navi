//
//  TelescopeSelectionSheet.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1.
//

import SwiftUI
import SwiftData
import INDIMCPKit
import CoreLocation

/// The toolbar's "selection button" modal (§4.1): pick an Observatory and a Rig, confirming
/// updates `TelescopeSessionManager`'s *armed* selection — it never connects anything itself.
///
/// Both lists are always populated from the local equipment library (`RigProfile`/
/// `ObservatoryProfile`) so the picker has something to show even before ever connecting. Rows
/// are only selectable while `TelescopeSessionManager` is connected — picking a *different*
/// server-side Rig/Observatory needs a live session to make sense of, but the already-armed
/// choice still displays (dimmed) while disconnected rather than disappearing.
struct TelescopeSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared

    @Query(sort: \RigProfile.name) private var rigs: [RigProfile]
    @Query(sort: \ObservatoryProfile.name) private var observatories: [ObservatoryProfile]

    @State private var selectedRigID: String?
    @State private var selectedObservatoryID: String?
    @State private var isRefreshingObservatories = false

    // "Current Location" quick-create (§4.1) — visible only when Location Services access is
    // available, never an error on tap if it isn't. Saving the new observatory still needs a
    // live connection (`saveObservatory` is server-side), same gating as every other row here.
    @State private var locationFetcher = CurrentLocationFetcher()
    @State private var isFetchingLocation = false
    @State private var pendingLocation: CLLocation?
    @State private var newObservatoryName = ""
    @State private var isPresentingLocationNamePrompt = false
    @State private var locationErrorMessage: String?

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
                        currentLocationRow
                    }
                    ForEach(observatories) { observatory in
                        row(
                            title: observatory.name,
                            isSelected: selectedObservatoryID == observatory.serverObservatoryID
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
                    emptyMessage: "No rigs in the equipment library yet."
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
        .alert("New Observatory", isPresented: $isPresentingLocationNamePrompt) {
            TextField("Name", text: $newObservatoryName)
            Button("Cancel", role: .cancel) {
                pendingLocation = nil
                newObservatoryName = ""
            }
            Button("Save") { Task { await saveCurrentLocationObservatory() } }
                .disabled(newObservatoryName.trimmingCharacters(in: .whitespaces).isEmpty)
        } message: {
            Text("Everything else — coordinates and elevation — is filled in from your current location.")
        }
        .alert(
            "Couldn't Get Your Location",
            isPresented: Binding(
                get: { locationErrorMessage != nil },
                set: { if !$0 { locationErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { locationErrorMessage = nil }
        } message: {
            Text(locationErrorMessage ?? "")
        }
    }

    private var currentLocationRow: some View {
        HStack {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Text("Current Location")
                .font(.callout)
            Spacer()
            if isFetchingLocation {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .opacity(isConnected ? 1 : 0.5)
        .allowsHitTesting(isConnected && !isFetchingLocation)
        .onTapGesture { Task { await useCurrentLocation() } }
    }

    private func useCurrentLocation() async {
        isFetchingLocation = true
        defer { isFetchingLocation = false }
        do {
            pendingLocation = try await locationFetcher.requestCurrentLocation()
            newObservatoryName = ""
            isPresentingLocationNamePrompt = true
        } catch {
            locationErrorMessage = (error as? CurrentLocationFetcher.FetchError)?.description ?? error.localizedDescription
        }
    }

    private func saveCurrentLocationObservatory() async {
        guard let location = pendingLocation else { return }
        let trimmedName = newObservatoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        defer {
            pendingLocation = nil
            newObservatoryName = ""
        }

        let observatory = Observatory(
            id: ObservatoryIDSlug.make(from: trimmedName),
            name: trimmedName,
            latitudeDeg: location.coordinate.latitude,
            longitudeDeg: location.coordinate.longitude,
            elevationMeters: location.altitude
        )
        do {
            let saved = try await telescope.saveObservatory(observatory)
            if let existing = observatories.first(where: { $0.serverObservatoryID == saved.id }) {
                existing.name = saved.name
                existing.latitudeDeg = saved.latitudeDeg
                existing.longitudeDeg = saved.longitudeDeg
                existing.elevationMeters = saved.elevationMeters
                existing.cachedAt = .now
            } else {
                modelContext.insert(ObservatoryProfile(
                    serverObservatoryID: saved.id,
                    name: saved.name,
                    latitudeDeg: saved.latitudeDeg,
                    longitudeDeg: saved.longitudeDeg,
                    elevationMeters: saved.elevationMeters
                ))
            }
            try modelContext.save()
            selectedObservatoryID = saved.id
        } catch {
            telescope.errorMessage = "Couldn't save the new observatory: \(TelescopeSessionManager.describe(error))"
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

            if !isConnected {
                Text("Connect to change this selection.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(title: String, isSelected: Bool, select: @escaping () -> Void) -> some View {
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
        .opacity(isConnected ? 1 : 0.5)
        .allowsHitTesting(isConnected)
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
