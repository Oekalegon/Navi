//
//  ObservatoryProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.1.
//

import Foundation
import SwiftData

/// A lightweight local cache of server-side Observatories — just enough (id + name) to populate
/// the toolbar's Observatory picker (§4.1) without needing a live connection every time it's
/// opened. Not a full local mirror: `Observatory` itself lives entirely server-side (see
/// `RigProfile.defaultObservatoryID`'s doc comment) — this cache exists purely so the picker has
/// *something* to show before a connection has ever been made. Populated opportunistically
/// whenever `TelescopeSessionManager.listObservatories()` succeeds while connected; picker rows
/// are only selectable while connected (§4.1), so a stale/empty cache when disconnected is
/// expected, not a bug.
@Model
final class ObservatoryProfile {
    @Attribute(.unique) var serverObservatoryID: String
    var name: String
    var cachedAt: Date

    init(serverObservatoryID: String, name: String, cachedAt: Date = .now) {
        self.serverObservatoryID = serverObservatoryID
        self.name = name
        self.cachedAt = cachedAt
    }
}
