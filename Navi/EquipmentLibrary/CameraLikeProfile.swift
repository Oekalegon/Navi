//
//  CameraLikeProfile.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85 follow-up.
//

import Foundation
import SwiftData

/// The shape `CameraProfile` and `GuideCameraProfile` share exactly (§4.3): both are a named,
/// device-bearing sensor with the same optical characteristics, differing only in the role they
/// play in a rig — imaging vs. guiding. They stay *separate* `@Model` types rather than one type
/// with a `role` discriminator (the way `StandaloneEquipmentProfile` handles its four roles)
/// because a rig references them through different relationships and the Equipment pane lists them
/// as different kinds; collapsing them would make "which cameras can I pick here" a filter rather
/// than a type.
///
/// This protocol exists so the *edit form* can be written once — see `CameraLikeEditForm`. Before
/// it, `CameraEditForm` and `GuideCameraEditForm` were byte-identical apart from the type name and
/// two placeholder strings, which meant adding a field to one and forgetting the other would
/// silently leave the two cameras disagreeing about their own shape.
///
/// `@Model`'s generated stored properties satisfy these requirements directly, so both conformances
/// are empty extensions — but that also means **this protocol must be kept in sync by hand**: a new
/// field added to both models isn't editable in the shared form until it's declared here too.
protocol CameraLikeProfile: AnyObject, PersistentModel {
    var name: String { get set }
    var make: String? { get set }
    var model: String? { get set }
    var deviceName: String? { get set }
    var cooled: Bool? { get set }
    var pixelsX: Int? { get set }
    var pixelsY: Int? { get set }
    var pixelSizeMicron: Double? { get set }
    var bitDepth: Int? { get set }
    var notes: String? { get set }
    var modifiedAt: Date { get set }
    /// Supplied by each conformer's own extension in `EquipmentDisplayName.swift`, since the
    /// placeholder text differs ("Untitled Camera" vs "Untitled Guide Camera").
    var displayName: String { get }
}

extension CameraProfile: CameraLikeProfile {}
extension GuideCameraProfile: CameraLikeProfile {}
