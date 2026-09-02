//
//  StandaloneEquipmentProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import Foundation
import SwiftData

/// A reusable definition for one of the four device-bearing roles with no natural equipment
/// concept before NAVI-85: Power Hub, Flat Screen, Dew Heater, Observatory Control (§4.3). One
/// shared `@Model` for all four — they're structurally identical (name, make, model, device) —
/// distinguished by `role`, the same pattern `OpticalAssemblyProfile` already uses for
/// main-imaging vs. guide-scope purposes.
///
/// Replaces `StandaloneComponentEntry` (an anonymous, JSON-blob-backed value embedded directly on
/// `RigProfile`) entirely — giving these a real name/identity is the point: a power hub or dew
/// heater controller is equipment you own, not an anonymous per-rig binding, and the same physical
/// unit may be reused across rigs the same way a `MountProfile` already is.
@Model
final class StandaloneEquipmentProfile {
    var name: String
    var role: StandaloneEquipmentRole
    var make: String?
    var model: String?
    var deviceName: String?
    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        role: StandaloneEquipmentRole,
        make: String? = nil,
        model: String? = nil,
        deviceName: String? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.role = role
        self.make = make
        self.model = model
        self.deviceName = deviceName
        self.notes = notes
        self.modifiedAt = modifiedAt
    }
}
