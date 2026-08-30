//
//  RigAutoMatcher.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1. NAVI-67: after a bare-server connect
//  (TelescopeSessionManager.connect(server:), NAVI-63 — no Rig armed yet), checks whether the
//  live/running devices match an existing local RigProfile bound to this server and, if so,
//  *upgrades* the bare session into a full rig-bound one (connect(server:rigID:)) — not just
//  remembering the Rig's id, since a bare connect never runs the device cascade
//  (TelescopeConnectCascade.run) that populates currentRig/per-device connection state. Without
//  the upgrade, the Dashboard's Rig section and device(for:) status badges would still show
//  nothing even though a Rig had technically been "matched."
//

import Foundation
import SwiftData

enum RigAutoMatcher {
    /// A no-op if a Rig is already armed (never overrides an explicit/existing choice), nothing
    /// is live, or no local Rig bound to `server` shares any device with what's actually running.
    @MainActor
    static func matchAndUpgrade(telescope: TelescopeSessionManager, modelContext: ModelContext, server: ServerProfile) async {
        guard telescope.state == .connected, telescope.armedRigID == nil else { return }
        guard let liveNames = try? await telescope.liveDeviceNames(), !liveNames.isEmpty else { return }

        // SwiftData relationships aren't compared inside #Predicate anywhere else in this
        // codebase (ArmedRigConnector.swift fetches by scalar id and reads relationships in
        // Swift afterward) — fetch everything and filter/score here instead of risking an
        // unproven relationship predicate.
        guard let allRigs = try? modelContext.fetch(FetchDescriptor<RigProfile>()) else { return }
        let candidates = allRigs.filter { $0.defaultServer?.persistentModelID == server.persistentModelID }
        guard let match = bestMatch(liveNames: liveNames, candidates: candidates) else { return }

        // Same pairing TelescopeSelectionSheet applies when a Rig is picked manually.
        let defaultObservatoryID = match.defaultObservatoryID

        await telescope.disconnect()
        telescope.armedRigID = match.serverRigID
        if let defaultObservatoryID {
            telescope.armedObservatoryID = defaultObservatoryID
        }
        await telescope.connect(server: server, rigID: match.serverRigID)
    }

    // Highest count of live device names present among a candidate Rig's bound devices; ties
    // broken by fetch order (undefined but deterministic per run) rather than prompting the user
    // to disambiguate — an accepted v1 simplification. Not `private`: covered directly by
    // RigAutoMatcherTests, which don't need a live TelescopeSessionManager/ModelContext.
    static func bestMatch(liveNames: [String], candidates: [RigProfile]) -> RigProfile? {
        let liveSet = Set(liveNames)
        var best: (rig: RigProfile, score: Int)?
        for rig in candidates {
            guard let components = try? rig.makeComponents() else { continue }
            let boundDevices = Set(components.compactMap(\.device))
            let score = boundDevices.intersection(liveSet).count
            guard score > 0, best == nil || score > best!.score else { continue }
            best = (rig, score)
        }
        return best?.rig
    }
}
