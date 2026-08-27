//
//  ImagingTrainProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// A reusable imaging-train definition in Navi's local equipment library — the camera, filter
/// wheel, and rotator that sit behind an `OpticalAssemblyProfile` (§4.3). An imaging train pairs
/// freely with any optical assembly; no compatibility constraint is modeled — image-circle/
/// back-focus fit is a human judgment call at pick-time, not validated in software for v1.
///
/// Filter wheel and rotator fields are each optional as a group: `nil` for all of them means that
/// role isn't part of this train, matching a Rig `Component`'s "selected but no device" vs.
/// "role not present at all" distinction from §4.3. `filterWheelSlots` covers the same
/// information as INDIMCPKit's `Component.slots: [Int: String]` (see `FilterSlotEntry`) so the
/// camera panel's filter picker can be populated the same way whether the source is a live
/// `Component` or this offline record.
@Model
final class ImagingTrainProfile {
    var name: String

    var cameraMake: String?
    var cameraModel: String?
    var cameraDeviceName: String?
    var cameraCooled: Bool?
    var cameraPixelsX: Int?
    var cameraPixelsY: Int?
    var cameraPixelSizeMicron: Double?
    var cameraBitDepth: Int?

    var filterWheelMake: String?
    var filterWheelModel: String?
    var filterWheelDeviceName: String?

    // Stored as JSON `Data`, not `[FilterSlotEntry]?` directly — SwiftData's "collection of
    // codable" attribute support fails a runtime cast for custom struct arrays at save/fetch time
    // (`Fatal error: This attribute is marked as being a collection of codable but it failed to
    // cast to a sequence`, confirmed empirically), even though `Codable`/`JSONEncoder` alone
    // handle `[FilterSlotEntry]` fine. `Data?` is a plain, reliably-supported attribute type.
    private var filterWheelSlotsData: Data?
    var filterWheelSlots: [FilterSlotEntry]? {
        get { filterWheelSlotsData.flatMap { try? JSONDecoder().decode([FilterSlotEntry].self, from: $0) } }
        set { filterWheelSlotsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var rotatorMake: String?
    var rotatorModel: String?
    var rotatorDeviceName: String?

    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        cameraDeviceName: String? = nil,
        cameraCooled: Bool? = nil,
        cameraPixelsX: Int? = nil,
        cameraPixelsY: Int? = nil,
        cameraPixelSizeMicron: Double? = nil,
        cameraBitDepth: Int? = nil,
        filterWheelMake: String? = nil,
        filterWheelModel: String? = nil,
        filterWheelDeviceName: String? = nil,
        filterWheelSlots: [FilterSlotEntry]? = nil,
        rotatorMake: String? = nil,
        rotatorModel: String? = nil,
        rotatorDeviceName: String? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.cameraDeviceName = cameraDeviceName
        self.cameraCooled = cameraCooled
        self.cameraPixelsX = cameraPixelsX
        self.cameraPixelsY = cameraPixelsY
        self.cameraPixelSizeMicron = cameraPixelSizeMicron
        self.cameraBitDepth = cameraBitDepth
        self.filterWheelMake = filterWheelMake
        self.filterWheelModel = filterWheelModel
        self.filterWheelDeviceName = filterWheelDeviceName
        self.filterWheelSlotsData = nil
        self.rotatorMake = rotatorMake
        self.rotatorModel = rotatorModel
        self.rotatorDeviceName = rotatorDeviceName
        self.notes = notes
        self.modifiedAt = modifiedAt
        // Must come after every stored property above is set (definite initialization) since
        // this goes through the computed `filterWheelSlots` setter, not a plain assignment.
        self.filterWheelSlots = filterWheelSlots
    }

    var hasFilterWheel: Bool {
        filterWheelDeviceName != nil || filterWheelMake != nil || filterWheelModel != nil
    }
    var hasRotator: Bool {
        rotatorDeviceName != nil || rotatorMake != nil || rotatorModel != nil
    }
}
