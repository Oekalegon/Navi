//
//  CurrentLocationQuickCreateRow.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1.
//

import SwiftUI
import SwiftData
import INDIMCPKit
import CoreLocation

/// The "Current Location" quick-create row in `TelescopeSelectionSheet`'s Observatory column
/// (§4.1) — extracted into its own view since it's a self-contained sub-feature (fetch location,
/// prompt for a name, save) rather than just another picker row. Visible only when Location
/// Services access is available (checked by the caller via `CurrentLocationFetcher.isAvailable`);
/// interactive only while connected, since saving is a live `saveObservatory` call.
struct CurrentLocationQuickCreateRow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    let isConnected: Bool
    let observatories: [ObservatoryProfile]
    let onObservatorySelected: (String) -> Void

    @State private var locationFetcher = CurrentLocationFetcher()
    @State private var isFetchingLocation = false
    @State private var pendingLocation: CLLocation?
    @State private var newObservatoryName = ""
    @State private var isPresentingLocationNamePrompt = false
    @State private var locationErrorMessage: String?

    var body: some View {
        row
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

    private var row: some View {
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
            id: IDSlug.make(from: trimmedName),
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
            onObservatorySelected(saved.id)
        } catch {
            telescope.errorMessage = "Couldn't save the new observatory: \(TelescopeSessionManager.describe(error))"
        }
    }
}
