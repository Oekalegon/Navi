//
//  BareServerConnector.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1. NAVI-67: shared "Connect to this Server
//  directly, no Rig armed yet" logic — connects via TelescopeSessionManager.connect(server:)
//  (NAVI-63), then RigAutoMatcher.matchAndUpgrade to upgrade to a full rig-bound connection if
//  the now-live devices match an existing local Rig, then opens the Dashboard pane on success,
//  mirroring ArmedRigConnector's rig-bound equivalent. Shared by TelescopeToolbarButton and
//  TelescopeCommands so the two Connect entry points can't drift.
//

import SwiftData

enum BareServerConnector {
    @MainActor
    static func connect(server: ServerProfile, telescope: TelescopeSessionManager, modelContext: ModelContext, paneManager: PaneManager?) async {
        await telescope.connect(server: server)
        guard telescope.state == .connected else { return }
        await RigAutoMatcher.matchAndUpgrade(telescope: telescope, modelContext: modelContext, server: server)
        // matchAndUpgrade disconnects-then-reconnects when it finds a match — guard again in
        // case that reconnect itself failed, rather than assuming the earlier bare connect's
        // success still holds.
        if telescope.state == .connected {
            paneManager?.showObservatoryDashboard()
        }
    }
}
