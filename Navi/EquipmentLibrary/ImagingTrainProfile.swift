//
//  ImagingTrainProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// A named combination of a `CameraProfile`, `FilterWheelProfile`, and `RotatorProfile` — the
/// imaging chain behind an optical assembly (§4.3). Deliberately a pure *composition*, not a bag of
/// flat camera/filter-wheel/rotator fields (that was NAVI-85's original shape, corrected in this
/// follow-up): a camera, filter wheel, and rotator are each independently-owned physical equipment,
/// managed on their own in the Equipment pane, the same way a `RigProfile` composes `MountProfile`/
/// `OpticalAssemblyProfile`/etc. rather than embedding their fields directly.
///
/// All three roles are optional, matching every other composition in this app: a role that isn't
/// selected for this train is simply omitted, not forced (an imaging train with no camera yet is a
/// valid, saveable "blank" state while it's being put together).
@Model
final class ImagingTrainProfile {
    var name: String
    @Relationship(deleteRule: .nullify) var camera: CameraProfile?
    @Relationship(deleteRule: .nullify) var filterWheel: FilterWheelProfile?
    @Relationship(deleteRule: .nullify) var rotator: RotatorProfile?
    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        camera: CameraProfile? = nil,
        filterWheel: FilterWheelProfile? = nil,
        rotator: RotatorProfile? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.camera = camera
        self.filterWheel = filterWheel
        self.rotator = rotator
        self.notes = notes
        self.modifiedAt = modifiedAt
    }
}
