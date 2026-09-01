//
//  RotatorProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3. NAVI-85 follow-up.
//

import Foundation
import SwiftData

/// A reusable rotator definition in Navi's local equipment library — independently owned
/// equipment, not a fixed part of any one `ImagingTrainProfile` (the same physical rotator may move
/// between imaging trains over time).
@Model
final class RotatorProfile {
    var name: String
    var make: String?
    var model: String?
    var deviceName: String?
    /// See `MountProfile.preferredDriverLabel`'s doc comment (NAVI-85).
    var preferredDriverLabel: String?
    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        make: String? = nil,
        model: String? = nil,
        deviceName: String? = nil,
        preferredDriverLabel: String? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.make = make
        self.model = model
        self.deviceName = deviceName
        self.preferredDriverLabel = preferredDriverLabel
        self.notes = notes
        self.modifiedAt = modifiedAt
    }
}
