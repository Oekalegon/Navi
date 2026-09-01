//
//  CameraProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3. NAVI-85 follow-up.
//

import Foundation
import SwiftData

/// A reusable imaging-camera definition in Navi's local equipment library — the main camera an
/// `ImagingTrainProfile` picks, independent of any one train (the same physical camera may move
/// between imaging trains over time, just like a `MountProfile` may carry different optical
/// assemblies). Distinct from `GuideCameraProfile`, which is used for guiding, not imaging.
@Model
final class CameraProfile {
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
