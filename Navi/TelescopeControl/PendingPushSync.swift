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

            // See `TelescopeSessionManager.pushesInFlight`'s doc comment: skips a rig some other
            // push (e.g. its own editor closing at the same moment) is already mid-flight for,
            // rather than racing it to write `lastPushedDigest` from a different snapshot.
            guard telescope.beginPush(recordID: rig.serverRigID) else { continue }
            defer { telescope.endPush(recordID: rig.serverRigID) }

            var serverDigest: String?
            if rig.lastPushedDigest != nil, let serverCopy = try? await telescope.getRig(id: rig.serverRigID) {
                serverDigest = PayloadDigest.of(serverCopy)
            }

            switch recordPushDecision(
                currentDigest: digest, lastPushedDigest: rig.lastPushedDigest, serverDigest: serverDigest
            ) {
            case .nothingToSend:
                continue
            case .conflict:
                telescope.pendingConflict = PendingConflict.forRig(
                    profile: rig, payload: payload, digest: digest,
                    telescope: telescope, modelContext: modelContext
                )
                continue
            case .push:
                break
            }

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

            // See `TelescopeSessionManager.pushesInFlight`'s doc comment.
            guard telescope.beginPush(recordID: observatory.serverObservatoryID) else { continue }
            defer { telescope.endPush(recordID: observatory.serverObservatoryID) }

            // Fetched for two reasons at once, as in `ObservatoryEditForm.save()`: the drift check,
            // and recovering `horizonProfile`, which the local record doesn't store — pushing
            // without it would wipe the server's horizon data.
            let serverCopy = try? await telescope.getObservatory(id: observatory.serverObservatoryID)
            let serverDigest = serverCopy.flatMap {
                PayloadDigest.ofObservatoryFields(
                    id: $0.id, name: $0.name, latitudeDeg: $0.latitudeDeg,
                    longitudeDeg: $0.longitudeDeg, elevationMeters: $0.elevationMeters
                )
            }

            switch recordPushDecision(
                currentDigest: digest, lastPushedDigest: observatory.lastPushedDigest, serverDigest: serverDigest
            ) {
            case .nothingToSend:
                continue
            case .conflict:
                telescope.pendingConflict = PendingConflict.forObservatory(
                    profile: observatory, latitudeDeg: observatory.latitudeDeg,
                    longitudeDeg: observatory.longitudeDeg, elevationMeters: observatory.elevationMeters,
                    horizonProfile: serverCopy?.horizonProfile, digest: digest,
                    telescope: telescope, modelContext: modelContext
                )
                continue
            case .push:
                break
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

}
