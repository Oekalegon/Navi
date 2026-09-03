//
//  PendingPushSync.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-86.
//

import Foundation
import SwiftData
import INDIMCPKit

/// Pushes records edited while disconnected, once a connection exists again.
///
/// Navi owns Rig and Observatory definitions; the server holds a copy so it can keep capturing
/// while Navi is offline (§4.3). That makes pushing a *sync step* rather than part of saving —
/// but until this existed, a record edited offline only reached the server if you happened to open
/// its editor again while connected, which is not something a user should have to know.
///
/// Follows the existing connector-helper shape (`ArmedRigConnector`, `BareServerConnector`): a
/// static entry point called from the action handlers that establish a connection, rather than a
/// view observing `telescope.state`. There is no state observer anywhere in this codebase and
/// adding one for this would be the odd case out.
enum PendingPushSync {

    /// Pushes everything whose local digest differs from what the server last accepted.
    ///
    /// Never overwrites a record that changed on the server since Navi last pushed it — that's
    /// reported and skipped, exactly as the editors do, so an edit made by another client (or on
    /// the Pi directly) survives. Individual failures don't stop the rest: this runs unattended
    /// after a connect, and one unreachable record shouldn't block the others.
    @MainActor
    static func pushPending(telescope: TelescopeSessionManager, modelContext: ModelContext) async {
        guard telescope.state == .connected else { return }
        await pushPendingRigs(telescope: telescope, modelContext: modelContext)
        await pushPendingObservatories(telescope: telescope, modelContext: modelContext)
    }

    @MainActor
    private static func pushPendingRigs(telescope: TelescopeSessionManager, modelContext: ModelContext) async {
        guard let rigs = try? modelContext.fetch(FetchDescriptor<RigProfile>()) else { return }
        for rig in rigs {
            // A rig that has never been pushed from this install is skipped rather than created:
            // `lastPushedDigest == nil` also describes a record that arrived via the V6 migration,
            // and silently creating server-side rigs on first connect after an update would be a
            // surprising thing for a sync pass to do.
            guard rig.lastPushedDigest != nil else { continue }
            guard let components = try? rig.makeComponents() else { continue }
            let payload = Rig(id: rig.serverRigID, name: rig.name, components: components)
            guard let digest = PayloadDigest.of(payload), digest != rig.lastPushedDigest else { continue }

            if await serverChangedUnderneath(
                telescope: telescope,
                lastPushed: rig.lastPushedDigest,
                fetch: { try await telescope.getRig(id: rig.serverRigID) },
                digest: { PayloadDigest.of($0) },
                name: rig.name
            ) { continue }

            do {
                let saved = try await telescope.saveRig(payload, overwrite: true)
                rig.lastResyncedAt = .now
                rig.lastPushedDigest = PayloadDigest.of(saved) ?? digest
                try? modelContext.save()
            } catch {
                telescope.errorMessage = "Couldn't sync \(rig.name): \(TelescopeSessionManager.describe(error))"
            }
        }
    }

    @MainActor
    private static func pushPendingObservatories(telescope: TelescopeSessionManager, modelContext: ModelContext) async {
        guard let observatories = try? modelContext.fetch(FetchDescriptor<ObservatoryProfile>()) else { return }
        for observatory in observatories {
            guard observatory.lastPushedDigest != nil else { continue }
            // Coordinates never fetched means this is a `listObservatories` summary holding 0/0/0,
            // not a real location — pushing it would destroy the observatory's actual position.
            guard observatory.detailsFetchedAt != nil else { continue }
            guard let digest = PayloadDigest.ofObservatoryFields(
                id: observatory.serverObservatoryID,
                name: observatory.name,
                latitudeDeg: observatory.latitudeDeg,
                longitudeDeg: observatory.longitudeDeg,
                elevationMeters: observatory.elevationMeters
            ), digest != observatory.lastPushedDigest else { continue }

            // Fetched for two reasons at once, as in `ObservatoryEditForm.save()`: the drift check,
            // and recovering `horizonProfile`, which the local record doesn't store — pushing
            // without it would wipe the server's horizon data.
            let serverCopy = try? await telescope.getObservatory(id: observatory.serverObservatoryID)
            if let lastPushed = observatory.lastPushedDigest,
               let serverCopy,
               let serverDigest = PayloadDigest.ofObservatoryFields(
                   id: serverCopy.id, name: serverCopy.name, latitudeDeg: serverCopy.latitudeDeg,
                   longitudeDeg: serverCopy.longitudeDeg, elevationMeters: serverCopy.elevationMeters
               ),
               serverDigest != lastPushed {
                telescope.errorMessage = """
                    \(observatory.name) changed on the server since Navi last pushed it — \
                    your local edits were kept but not sent, so the server copy is untouched.
                    """
                continue
            }

            let payload = Observatory(
                id: observatory.serverObservatoryID,
                name: observatory.name,
                latitudeDeg: observatory.latitudeDeg,
                longitudeDeg: observatory.longitudeDeg,
                elevationMeters: observatory.elevationMeters,
                horizonProfile: serverCopy?.horizonProfile
            )
            do {
                let saved = try await telescope.saveObservatory(payload, overwrite: true)
                observatory.lastPushedDigest = PayloadDigest.ofObservatoryFields(
                    id: saved.id, name: saved.name, latitudeDeg: saved.latitudeDeg,
                    longitudeDeg: saved.longitudeDeg, elevationMeters: saved.elevationMeters
                ) ?? digest
                observatory.detailsFetchedAt = .now
                try? modelContext.save()
            } catch {
                telescope.errorMessage = "Couldn't sync \(observatory.name): \(TelescopeSessionManager.describe(error))"
            }
        }
    }

    /// Shared drift check. Returns `true` when the server's copy differs from what Navi last
    /// pushed, meaning the caller should leave it alone.
    @MainActor
    private static func serverChangedUnderneath<Payload>(
        telescope: TelescopeSessionManager,
        lastPushed: String?,
        fetch: () async throws -> Payload,
        digest: (Payload) -> String?,
        name: String
    ) async -> Bool {
        guard let lastPushed else { return false }
        guard let serverCopy = try? await fetch(), let serverDigest = digest(serverCopy) else {
            // Couldn't read the server's copy — say nothing rather than guessing. The push that
            // follows will fail on its own if the connection is genuinely gone.
            return false
        }
        guard serverDigest != lastPushed else { return false }
        telescope.errorMessage = """
            \(name) changed on the server since Navi last pushed it — \
            your local edits were kept but not sent, so the server copy is untouched.
            """
        return true
    }
}
