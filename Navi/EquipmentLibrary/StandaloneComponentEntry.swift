//
//  StandaloneComponentEntry.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation

/// A per-Rig component for a role with no reusable library entity: `.powerHub`,
/// `.observatoryControl`, `.flatScreen`, `.dewHeater` (§4.3 — none obviously fit "reusable
/// optical equipment"). Just a device picker row, no library backing, so this is a plain embedded
/// value on `RigProfile.standaloneComponents` rather than its own `@Model` type.
///
/// `role` is a raw string, not INDIMCPKit's `Role` type, so this file has no dependency on
/// INDIMCPKit — `Role` itself is open-ended (any string round-trips), and the mapping to a real
/// `Component` only needs to happen where a `RigProfile` gets translated for `saveRig`.
struct StandaloneComponentEntry: Codable, Hashable {
    /// Matches the corresponding server-side `Component.id` once saved.
    var id: String
    var role: String
    var make: String?
    var model: String?
    var deviceName: String?

    init(id: String, role: String, make: String? = nil, model: String? = nil, deviceName: String? = nil) {
        self.id = id
        self.role = role
        self.make = make
        self.model = model
        self.deviceName = deviceName
    }
}
