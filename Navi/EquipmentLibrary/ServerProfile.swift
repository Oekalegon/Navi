//
//  ServerProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import Foundation
import SwiftData

/// A named INDI-MCP server in Navi's local equipment library — purely a Navi-side convenience
/// (name + URL); INDIMCPKit/INDIMCP-server have no concept of a "named server," only the
/// connection endpoint Navi's `INDIMCPClient` talks to. A `RigProfile` references one as its
/// default server (§4.2's Server pane).
@Model
final class ServerProfile {
    var name: String
    var url: URL
    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(name: String, url: URL, notes: String? = nil, modifiedAt: Date = .now) {
        self.name = name
        self.url = url
        self.notes = notes
        self.modifiedAt = modifiedAt
    }
}
