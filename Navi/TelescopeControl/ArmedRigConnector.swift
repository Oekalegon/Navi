//
//  ArmedRigConnector.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1. Shared "Connect the armed Rig" logic — resolves
//  the armed RigProfile's defaultServer and connects via TelescopeSessionManager.connect(server:
//  rigID:), opening the Dashboard pane on success (NAVI-50). Factored out once a second entry
//  point (the Telescope menu bar command, NAVI-64) needed the exact same steps as
//  TelescopeToolbarButton's Connect button, so the two can't drift apart.
//

import Foundation
import SwiftData

enum ArmedRigConnector {
    @MainActor
    static func connect(telescope: TelescopeSessionManager, modelContext: ModelContext, paneManager: PaneManager?) async {
        guard let rigID = telescope.armedRigID else { return }
        let descriptor = FetchDescriptor<RigProfile>(predicate: #Predicate { $0.serverRigID == rigID })
        guard let rig = try? modelContext.fetch(descriptor).first, let server = rig.defaultServer else {
            telescope.errorMessage = "The selected rig has no default server configured."
            return
        }
        await telescope.connect(server: server, rigID: rigID)
        if telescope.state == .connected {
            paneManager?.showObservatoryDashboard()
        }
    }
}
