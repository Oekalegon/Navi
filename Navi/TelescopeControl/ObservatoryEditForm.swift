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
    /// Carried through untouched from `load()` to `save()`. Navi has no editor for it yet (§4.2
    /// wants `.hzn` import), but `saveObservatory` replaces the whole record — so constructing the
    /// payload without it, as this form did, silently wiped any horizon obstruction data the server
    /// held for the observatory on every single save.
    @State private var horizonProfile: [HorizonPoint]?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// The field values as last loaded from (or pushed to) the server. `isDirty` is derived by
    /// comparing against it rather than being latched by per-field `.onChange` handlers, because
    /// `load()` assigns to exactly those fields — so merely *opening* an observatory latched the
    /// flag and closing pushed it straight back, defeating the "viewing never writes to the server"
    /// guarantee the flag exists for. Comparing is also order-independent (no race with when
    /// `.onChange` fires relative to `load()` finishing) and correctly goes clean again if an edit
    /// is undone by hand.
    ///
    /// `nil` until the first load completes, so nothing is considered an edit before there's
    /// anything to compare against.
    @State private var loadedSnapshot: String?

    private var currentSnapshot: String {
        var parts: [String] = []
        parts.append(name)
        parts.append("\(latitudeDeg)")
        parts.append("\(longitudeDeg)")
        parts.append("\(elevationMeters)")
        return parts.joined(separator: "\u{1F}")
    }

    private var isDirty: Bool {
        guard let loadedSnapshot else { return false }
        return currentSnapshot != loadedSnapshot
    }

    private var isConnected: Bool { telescope.state == .connected }

    var body: some View {
        SettingsDetailForm(title: name.isEmpty ? "Untitled Observatory" : name) {
            if !isConnected {
                // Three genuinely different situations, so one blanket "connect first" was wrong
                // once offline editing became possible.
                // `observatoryID == nil` is folded into the first case rather than given its own:
                // a new observatory gets its baseline synchronously, so it's always editable
                // offline — but `.task` runs after the first render, so testing `loadedSnapshot`
                // alone would flash the wrong message at it.
                if loadedSnapshot != nil || observatoryID == nil {
                    Label(
                        "Not connected — changes are saved in Navi and pushed to the server next time you edit this observatory while connected.",
                        systemImage: "icloud.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Connect once to load this observatory's coordinates before editing — Navi only has its name so far.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
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
        .task { await load() }
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

    /// Local write first, push second — the same ordering `RigEditForm` uses, and for the same
    /// reason: previously the local cache was only updated *after* a successful `saveObservatory`,
    /// so a push that failed (connection dropped as the window closed, server rejected it) lost the
    /// user's edit outright. Writing locally first means the worst case is a local record that's
    /// ahead of the server, which is recoverable, rather than an edit that's simply gone.
    ///
    /// `isDirty` is false until a baseline exists, and a baseline only exists after a successful
    /// `getObservatory` (or for a brand-new record) — which doubles as the guard against pushing a
    /// summary-only cache entry. `listObservatories` seeds the cache with id and name only, leaving
    /// coordinates at 0, so pushing an unhydrated record would replace the observatory's real
    /// location with 0/0/0.
    private func flush() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        switch recordFlushOutcome(isDirty: isDirty, trimmedName: trimmedName, isConnected: isConnected) {
        case .skip:
            return
        case .persistOnly:
            persistLocally(id: observatoryID ?? IDSlug.make(from: trimmedName), name: trimmedName)
        case .persistAndPush:
            persistLocally(id: observatoryID ?? IDSlug.make(from: trimmedName), name: trimmedName)
            Task { await save() }
        }
    }

    /// Writes the edited values straight into the local `ObservatoryProfile`, creating it if this is
    /// a new observatory. Mirrors `upsertLocalCache(with:)` but sourced from the form rather than
    /// from a server response, so it doesn't need the push to have happened.
    private func persistLocally(id: String, name: String) {
        let descriptor = FetchDescriptor<ObservatoryProfile>(
            predicate: #Predicate { $0.serverObservatoryID == id }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.name = name
            existing.latitudeDeg = latitudeDeg
            existing.longitudeDeg = longitudeDeg
            existing.elevationMeters = elevationMeters
            existing.cachedAt = .now
        } else {
            modelContext.insert(ObservatoryProfile(
                serverObservatoryID: id,
                name: name,
                latitudeDeg: latitudeDeg,
                longitudeDeg: longitudeDeg,
                elevationMeters: elevationMeters
            ))
        }
        try? modelContext.save()
    }

    private func load() async {
        guard let observatoryID else {
            // Creating a new one: nothing to fetch, but the baseline has to exist or the first
            // keystroke wouldn't register as an edit.
            loadedSnapshot = currentSnapshot
            return
        }
        guard isConnected else {
            // Offline: the local record can stand in, but only if its coordinates were actually
            // fetched at some point. `listObservatories` seeds the cache with id and name alone,
            // leaving coordinates at 0 — editing one of those and pushing it later would replace
            // the observatory's real location with 0/0/0, so a summary-only record stays
            // un-editable (no baseline means nothing registers as an edit) until it's hydrated.
            if let profile = localProfile(id: observatoryID), profile.detailsFetchedAt != nil {
                name = profile.name
                latitudeDeg = profile.latitudeDeg
                longitudeDeg = profile.longitudeDeg
                elevationMeters = profile.elevationMeters
                loadedSnapshot = currentSnapshot
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let observatory = try await telescope.getObservatory(id: observatoryID)
            name = observatory.name
            latitudeDeg = observatory.latitudeDeg
            longitudeDeg = observatory.longitudeDeg
            elevationMeters = observatory.elevationMeters
            horizonProfile = observatory.horizonProfile
            loadedSnapshot = currentSnapshot
            // Mark the cache as holding real coordinates, which is what makes offline editing of
            // this record possible next time.
            if let profile = localProfile(id: observatoryID) {
                profile.latitudeDeg = observatory.latitudeDeg
                profile.longitudeDeg = observatory.longitudeDeg
                profile.elevationMeters = observatory.elevationMeters
                profile.detailsFetchedAt = .now
                try? modelContext.save()
            }
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
        let profile = localProfile(id: id)

        // One fetch of the server's current copy serves two purposes: the drift check, and
        // recovering `horizonProfile` when this form never loaded it (an edit made offline, then
        // pushed on reconnect, would otherwise send nil and wipe it).
        let serverCopy = observatoryID == nil ? nil : try? await telescope.getObservatory(id: id)

        // Drift check. Only meaningful once we've pushed this record before — without a stored
        // digest there's nothing to compare the server's copy against, and a first push is
        // legitimately creating or adopting the record.
        if let lastPushed = profile?.lastPushedDigest,
           let serverCopy,
           let serverDigest = PayloadDigest.ofObservatoryFields(
               id: serverCopy.id, name: serverCopy.name, latitudeDeg: serverCopy.latitudeDeg,
               longitudeDeg: serverCopy.longitudeDeg, elevationMeters: serverCopy.elevationMeters
           ),
           serverDigest != lastPushed {
            telescope.errorMessage = """
                \(trimmedName) changed on the server since Navi last pushed it — \
                your local edits were kept but not sent, so the server copy is untouched.
                """
            return
        }

        let observatory = Observatory(
            id: id,
            name: trimmedName,
            latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg,
            elevationMeters: elevationMeters,
            // Prefer what this form loaded; fall back to the server's, so a record edited offline
            // doesn't lose its horizon data on the eventual push.
            horizonProfile: horizonProfile ?? serverCopy?.horizonProfile
        )
        let digest = PayloadDigest.ofObservatoryFields(
            id: id, name: trimmedName, latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg, elevationMeters: elevationMeters
        )

        // Nothing to send: the server already has exactly this.
        if let digest, digest == profile?.lastPushedDigest { return }

        do {
            let saved = try await telescope.saveObservatory(observatory, overwrite: observatoryID != nil)
            upsertLocalCache(with: saved)
            if let profile = localProfile(id: saved.id) {
                profile.lastPushedDigest = PayloadDigest.ofObservatoryFields(
                    id: saved.id, name: saved.name, latitudeDeg: saved.latitudeDeg,
                    longitudeDeg: saved.longitudeDeg, elevationMeters: saved.elevationMeters
                ) ?? digest
                profile.detailsFetchedAt = .now
                try? modelContext.save()
            }
            loadedSnapshot = currentSnapshot
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

    private func localProfile(id: String) -> ObservatoryProfile? {
        let descriptor = FetchDescriptor<ObservatoryProfile>(
            predicate: #Predicate { $0.serverObservatoryID == id }
        )
        return try? modelContext.fetch(descriptor).first
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
