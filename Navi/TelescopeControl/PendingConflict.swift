//
//  PendingConflict.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-86.
//

import Foundation
import SwiftData
import INDIMCPKit

/// A Rig or Observatory that changed on the server since Navi last pushed it — surfaced instead of
/// silently overwritten, per the drift-detection half of NAVI-86's source-of-truth inversion.
///
/// The two resolutions are asymmetric, because Rig and Observatory are not: an `Observatory`
/// payload is every field there is, so "use the server's version" can genuinely replace the local
/// record. A `Rig`'s local composition — *which library entity* fills each role — has no server
/// counterpart at all (the server only ever sees the flattened `Component` list), so there is no
/// server copy to adopt. For a rig, `acceptServer` instead stops treating the local edit as pending
/// without touching it: the conflict clears, but the composition and the server's copy are left to
/// differ until the rig is edited again. `acceptServerDescription` exists so the indicator can say
/// which of these two it actually is, rather than using one label that's dishonest for one of them.
struct PendingConflict: Identifiable {
    let id = UUID()
    let recordName: String
    /// Overwrites the server with Navi's local version. Throwing, not swallowed internally — see
    /// `TelescopeConflictIndicator.resolve(_:)`'s doc comment for why a failure here must reach the
    /// caller rather than be treated as done.
    let pushMine: () async throws -> Void
    /// Observatory: replaces the local record with the server's. Rig: adopts the server's digest
    /// as the new baseline without changing the local composition — see the type's doc comment.
    let acceptServer: () async throws -> Void
    let acceptServerDescription: String
}

extension PendingConflict {
    /// Shared by `RigEditForm.push` and `PendingPushSync`, so the two push paths can't describe or
    /// resolve the same conflict differently.
    @MainActor
    static func forRig(
        profile: RigProfile,
        payload: Rig,
        digest: String?,
        telescope: TelescopeSessionManager,
        modelContext: ModelContext
    ) -> PendingConflict {
        PendingConflict(
            recordName: profile.name,
            pushMine: {
                // Deliberately not caught here — `TelescopeConflictIndicator.resolve(_:)` needs to
                // know whether this actually succeeded before it clears `pendingConflict`, since
                // clearing it on a failed push would tell the user their edit was sent when it
                // wasn't. It's still mirrored onto `telescope.errorMessage` (I-4's convention) so a
                // background `PendingPushSync` resolution failure is visible even with no view
                // watching the thrown error.
                do {
                    let saved = try await telescope.saveRig(payload, overwrite: true)
                    profile.lastResyncedAt = .now
                    profile.lastPushedDigest = PayloadDigest.of(saved) ?? digest
                    try? modelContext.save()
                } catch {
                    telescope.errorMessage = "\(profile.name): \(TelescopeSessionManager.describe(error))"
                    throw error
                }
            },
            acceptServer: {
                // No server payload to adopt into the local composition — see the type's doc
                // comment. This only stops treating the edit as pending; the composition and the
                // server's copy are left to differ until the rig is edited again.
                let serverCopy = try await telescope.getRig(id: profile.serverRigID)
                profile.lastPushedDigest = PayloadDigest.of(serverCopy)
                try? modelContext.save()
            },
            acceptServerDescription: "Stops asking about this change, without sending your edit — "
                + "Navi's copy and the server's will keep differing until you edit this rig again."
        )
    }

    /// Shared by `ObservatoryEditForm.save` and `PendingPushSync`.
    @MainActor
    static func forObservatory(
        profile: ObservatoryProfile,
        latitudeDeg: Double,
        longitudeDeg: Double,
        elevationMeters: Double,
        horizonProfile: [HorizonPoint]?,
        digest: String?,
        telescope: TelescopeSessionManager,
        modelContext: ModelContext
    ) -> PendingConflict {
        let id = profile.serverObservatoryID
        let name = profile.name
        return PendingConflict(
            recordName: name,
            pushMine: {
                let payload = Observatory(
                    id: id, name: name, latitudeDeg: latitudeDeg, longitudeDeg: longitudeDeg,
                    elevationMeters: elevationMeters, horizonProfile: horizonProfile
                )
                do {
                    let saved = try await telescope.saveObservatory(payload, overwrite: true)
                    profile.latitudeDeg = saved.latitudeDeg
                    profile.longitudeDeg = saved.longitudeDeg
                    profile.elevationMeters = saved.elevationMeters
                    profile.cachedAt = .now
                    profile.detailsFetchedAt = .now
                    profile.lastPushedDigest = PayloadDigest.ofObservatoryFields(
                        id: saved.id, name: saved.name, latitudeDeg: saved.latitudeDeg,
                        longitudeDeg: saved.longitudeDeg, elevationMeters: saved.elevationMeters
                    ) ?? digest
                    try? modelContext.save()
                } catch {
                    telescope.errorMessage = "\(name): \(TelescopeSessionManager.describe(error))"
                    throw error
                }
            },
            acceptServer: {
                // Unlike a Rig, an Observatory payload is every field there is — the server's copy
                // genuinely can replace the local record.
                let serverCopy = try await telescope.getObservatory(id: id)
                profile.name = serverCopy.name
                profile.latitudeDeg = serverCopy.latitudeDeg
                profile.longitudeDeg = serverCopy.longitudeDeg
                profile.elevationMeters = serverCopy.elevationMeters
                profile.cachedAt = .now
                profile.detailsFetchedAt = .now
                profile.lastPushedDigest = PayloadDigest.ofObservatoryFields(
                    id: serverCopy.id, name: serverCopy.name, latitudeDeg: serverCopy.latitudeDeg,
                    longitudeDeg: serverCopy.longitudeDeg, elevationMeters: serverCopy.elevationMeters
                )
                try? modelContext.save()
            },
            acceptServerDescription: "Replaces Navi's local copy with the server's — your unsent edit is discarded."
        )
    }
}
