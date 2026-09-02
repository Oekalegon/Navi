//
//  EquipmentDisplayName.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85 follow-up.
//

import Foundation

/// How an equipment record labels itself in lists and headers when the user hasn't given it an
/// explicit name.
///
/// A name is *not* required (NAVI-85 follow-up): most equipment already identifies itself perfectly
/// well as "ZWO ASI2600MM Pro", and forcing a separate name field before a record can be saved is
/// busywork. So `name` is treated as an optional override — when it's blank, the make/model pair
/// stands in for it, and only a record with nothing filled in at all falls back to the placeholder.
///
/// Make before model ("ZWO ASI2600MM Pro"), the conventional reading order for equipment.
func equipmentDisplayName(name: String, make: String?, model: String?, fallback: String) -> String {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedName.isEmpty { return trimmedName }

    let parts = [make, model]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return parts.isEmpty ? fallback : parts.joined(separator: " ")
}

extension MountProfile {
    var displayName: String { equipmentDisplayName(name: name, make: make, model: model, fallback: "Untitled Mount") }
}

extension OpticalAssemblyProfile {
    var displayName: String {
        equipmentDisplayName(
            name: name,
            make: make,
            model: model,
            fallback: purpose == .guideScope ? "Untitled Guide Optical Assembly" : "Untitled Optical Assembly"
        )
    }
}

extension CameraProfile {
    var displayName: String { equipmentDisplayName(name: name, make: make, model: model, fallback: "Untitled Camera") }
}

extension FilterWheelProfile {
    var displayName: String { equipmentDisplayName(name: name, make: make, model: model, fallback: "Untitled Filter Wheel") }
}

extension RotatorProfile {
    var displayName: String { equipmentDisplayName(name: name, make: make, model: model, fallback: "Untitled Rotator") }
}

extension GuideCameraProfile {
    var displayName: String { equipmentDisplayName(name: name, make: make, model: model, fallback: "Untitled Guide Camera") }
}

extension StandaloneEquipmentProfile {
    var displayName: String { equipmentDisplayName(name: name, make: make, model: model, fallback: "Untitled \(role.title)") }
}

/// An imaging train has no make/model of its own — it's a composition — so it falls straight
/// through to the placeholder when unnamed.
extension ImagingTrainProfile {
    var displayName: String { equipmentDisplayName(name: name, make: nil, model: nil, fallback: "Untitled Imaging Train") }
}
