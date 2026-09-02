//
//  ObservatoryEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import AppKit
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
    /// Set by any field edit, cleared by a successful push. Gates the flush so simply *viewing* an
    /// observatory never writes to the server.
    @State private var isDirty = false

    private var isConnected: Bool { telescope.state == .connected }

    var body: some View {
        SettingsDetailForm(title: name.isEmpty ? "Untitled Observatory" : name) {
            if !isConnected {
                Label("Connect to a telescope server to edit observatories.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            LabeledField("Name") {
                TextField("Home Backyard", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                LabeledField("Latitude (°)") {
                    TextField("0.0", value: $latitudeDeg, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Longitude (°)") {
                    TextField("0.0", value: $longitudeDeg, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            LabeledField("Elevation (m)") {
                TextField("0.0", value: $elevationMeters, format: .number)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        } actions: {
            if isLoading || isSaving {
                ProgressView().controlSize(.small)
            }
        }
        .disabled(!isConnected)
        .task { await load() }
        .onChange(of: name) { isDirty = true }
        .onChange(of: latitudeDeg) { isDirty = true }
        .onChange(of: longitudeDeg) { isDirty = true }
        .onChange(of: elevationMeters) { isDirty = true }
        // Unlike the local equipment editors, an Observatory only exists server-side, so edits
        // can't just be written as they're typed — that would be one `saveObservatory` per
        // keystroke. They're held here and pushed once, when this form goes away: selecting a
        // different observatory, switching tab, or closing Settings all tear this view down.
        //
        // A detached `Task` deliberately, not `.task`: the push has to outlive the view that
        // started it. If it never lands (connection dropped as the window closed), nothing is
        // silently corrupted — the server simply keeps its previous definition, and the local
        // cache still shows what the server last confirmed.
        .onDisappear { flush() }
        // Belt and braces. .onDisappear is dependable for a selection change or a tab switch, but
        // window close is exactly where SwiftUI is least reliable about tearing a view down — and
        // that's the case where a missed flush loses the push outright. flush() is dirty-gated and
        // idempotent, so firing from both is harmless; this notification also covers other windows
        // closing, which is simply an earlier, equally safe moment to sync.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            flush()
        }
    }

    private func flush() {
        guard isDirty, isConnected, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await save() }
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

        let id = observatoryID ?? IDSlug.make(from: trimmedName)
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
            isDirty = false
        } catch {
            // `flush()` calls this during teardown, so `errorMessage` — this view's own @State —
            // is written to a view that's already gone and never rendered. The toolbar's
            // TelescopeErrorIndicator is the only surface the user can still see, so route there
            // too. (Kept on `errorMessage` as well for a save triggered while still on screen.)
            let described = TelescopeSessionManager.describe(error)
            errorMessage = described
            telescope.errorMessage = "\(trimmedName): \(described)"
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
