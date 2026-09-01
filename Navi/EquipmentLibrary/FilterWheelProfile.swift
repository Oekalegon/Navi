//
//  FilterWheelProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3. NAVI-85 follow-up.
//

import Foundation
import SwiftData

/// A reusable filter-wheel definition in Navi's local equipment library — independently owned
/// equipment, not a fixed part of any one `ImagingTrainProfile` (the same physical wheel may move
/// between imaging trains over time).
@Model
final class FilterWheelProfile {
    var name: String
    var make: String?
    var model: String?
    var deviceName: String?

    // Stored as JSON `Data`, not `[FilterSlotEntry]?` directly — SwiftData's "collection of
    // codable" attribute support fails a runtime cast for custom struct arrays at save/fetch time,
    // confirmed empirically (see `ImagingTrainProfile.filterWheelSlotsData`, this type's
    // predecessor). `Data?` is a plain, reliably-supported attribute type.
    private var slotsData: Data?
    var slots: [FilterSlotEntry]? {
        get { slotsData.flatMap { try? JSONDecoder().decode([FilterSlotEntry].self, from: $0) } }
        set { slotsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        make: String? = nil,
        model: String? = nil,
        deviceName: String? = nil,
        slots: [FilterSlotEntry]? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.make = make
        self.model = model
        self.deviceName = deviceName
        self.slotsData = nil
        self.notes = notes
        self.modifiedAt = modifiedAt
        // Must come after every stored property above is set (definite initialization) since this
        // goes through the computed `slots` setter, not a plain assignment.
        self.slots = slots
    }
}
