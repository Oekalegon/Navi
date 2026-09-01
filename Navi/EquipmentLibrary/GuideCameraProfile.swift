//
//  GuideCameraProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// A reusable guide-camera definition in Navi's local equipment library.
///
/// Kept independent of `ImagingTrainProfile` (not nested inside it) because a guide camera
/// attaches in two different places depending on setup (§4.3): paired with a
/// `.guideScope`-purposed `OpticalAssemblyProfile` (traditional piggyback guide scope), or used
/// as an off-axis guider inserted directly into the main imaging train. `RigProfile` records
/// which case applies for a given rig — this record itself is attachment-point-agnostic.
@Model
final class GuideCameraProfile {
    var name: String
    var make: String?
    var model: String?
    var deviceName: String?
    var cooled: Bool?
    var pixelsX: Int?
    var pixelsY: Int?
    var pixelSizeMicron: Double?
    var bitDepth: Int?
    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        make: String? = nil,
        model: String? = nil,
        deviceName: String? = nil,
        cooled: Bool? = nil,
        pixelsX: Int? = nil,
        pixelsY: Int? = nil,
        pixelSizeMicron: Double? = nil,
        bitDepth: Int? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.make = make
        self.model = model
        self.deviceName = deviceName
        self.cooled = cooled
        self.pixelsX = pixelsX
        self.pixelsY = pixelsY
        self.pixelSizeMicron = pixelSizeMicron
        self.bitDepth = bitDepth
        self.notes = notes
        self.modifiedAt = modifiedAt
    }
}
