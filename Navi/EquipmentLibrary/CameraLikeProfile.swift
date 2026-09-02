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

extension CameraLikeProfile {
    /// Every editable field folded into one comparable value, so the editor can stamp `modifiedAt`
    /// from a single `.onChange` instead of one per field.
    ///
    /// Deliberately here rather than in the form: this is the same field list the protocol above
    /// declares, so the two drift together and in one file. `modifiedAt` drives
    /// `RigProfile.hasStaleLibraryReferences`, so a field missing from this key means edits to it
    /// leave a rig claiming to be in sync when it isn't — the reason this isn't ten separate
    /// handlers anyone could forget to extend.
    var editableChangeKey: String {
        // Built with explicit appends rather than one array literal: a literal mixing String,
        // String?, Bool?, Int? and Double? blew the type-checker's budget outright.
        var parts: [String] = []
        parts.append(name)
        parts.append(make ?? "")
        parts.append(model ?? "")
        parts.append(deviceName ?? "")
        parts.append(cooled.map { "\($0)" } ?? "")
        parts.append(pixelsX.map { "\($0)" } ?? "")
        parts.append(pixelsY.map { "\($0)" } ?? "")
        parts.append(pixelSizeMicron.map { "\($0)" } ?? "")
        parts.append(bitDepth.map { "\($0)" } ?? "")
        parts.append(notes ?? "")
        return parts.joined(separator: "\u{1F}")
    }
}
