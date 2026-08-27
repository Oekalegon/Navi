//
//  ObservatoryEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// Add/edit form for one `Observatory` (§4.2's full CRUD editor). Unlike `ServerEditForm`,
/// `Observatory` isn't a local SwiftData model — it lives server-side — so this form only works
/// while `TelescopeSessionManager` is connected: editing fetches the live definition
/// (`getObservatory(id:)`, since the local `ObservatoryProfile` cache only ever holds
/// name/lat/lon/elevation), and saving pushes it back (`saveObservatory`), then refreshes the
/// local cache to match.
///
/// `observatoryID == nil` means "creating a new one" — a stable id is slugified from the name on
/// save, since INDIMCP-server files observatories as `observatories/<id>.yaml`.
///
/// **Scope note:** §4.2 also calls for a horizon-obstruction profile authored via `.hzn` file
/// import. Deliberately left out of this form for now — it needs `Observatory.horizonProfile`/
/// `HorizonPoint`, which only exist on INDIMCPKit's unmerged `feature/IMCPKIT-67-horizon-profile`
/// branch, not the `develop` Navi's CI builds against. Add back once that merges.
struct ObservatoryEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    let observatoryID: String?

    @State private var name = ""
    @State private var latitudeDeg: Double = 0
    @State private var longitudeDeg: Double = 0
    @State private var elevationMeters: Double = 0
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isConnected: Bool { telescope.state == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(observatoryID == nil ? "Add Observatory" : "Edit Observatory")
                .font(.headline)

            if !isConnected {
                Label("Connect to a telescope server to edit observatories.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            labeledField("Name") {
                TextField("Home Backyard", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                labeledField("Latitude (°)") {
                    TextField("0.0", value: $latitudeDeg, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Longitude (°)") {
                    TextField("0.0", value: $longitudeDeg, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            labeledField("Elevation (m)") {
                TextField("0.0", value: $elevationMeters, format: .number)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                if isLoading || isSaving {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConnected || name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading || isSaving)
            }
        }
        .padding(16)
        .frame(width: 420, height: 420)
        .disabled(!isConnected)
        .task { await load() }
    }

    @ViewBuilder
    private func labeledField(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func load() async {
        guard let observatoryID, isConnected else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let observatory = try await telescope.getObservatory(id: observatoryID)
            name = observatory.name
            latitudeDeg = observatory.latitudeDeg
            longitudeDeg = observatory.longitudeDeg
            elevationMeters = observatory.elevationMeters
        } catch {
            errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let id = observatoryID ?? ObservatoryIDSlug.make(from: trimmedName)
        let observatory = Observatory(
            id: id,
            name: trimmedName,
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
            elevationMeters: elevationMeters
        )
        do {
            let saved = try await telescope.saveObservatory(observatory, overwrite: observatoryID != nil)
            upsertLocalCache(with: saved)
            dismiss()
        } catch {
            errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func upsertLocalCache(with observatory: Observatory) {
        let id = observatory.id
        let descriptor = FetchDescriptor<ObservatoryProfile>(
            predicate: #Predicate { $0.serverObservatoryID == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = observatory.name
            existing.latitudeDeg = observatory.latitudeDeg
            existing.longitudeDeg = observatory.longitudeDeg
            existing.elevationMeters = observatory.elevationMeters
            existing.cachedAt = .now
        } else {
            modelContext.insert(ObservatoryProfile(
                serverObservatoryID: observatory.id,
                name: observatory.name,
                latitudeDeg: observatory.latitudeDeg,
                longitudeDeg: observatory.longitudeDeg,
                elevationMeters: observatory.elevationMeters
            ))
        }
        try? modelContext.save()
    }
}
