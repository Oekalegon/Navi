//
//  RigProfileTranslator.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import Foundation
import INDIMCPKit

/// Thrown while flattening a `RigProfile` into INDIMCPKit's `[Component]` list.
enum RigProfileTranslationError: Error, CustomStringConvertible {
    /// Two components would resolve to the same `role` once flattened — INDIMCPKit's data model
    /// tolerates this server-side (`DeviceControlError.ambiguousComponentForRole` exists
    /// specifically for it), but §4.2 explicitly disallows it in the Rig editor for now: there's
    /// no way to group a duplicate's associated components (e.g. two focusers) as belonging to
    /// one optical path vs. another, since `Component` is a flat list with no parent/group field
    /// (tracked upstream as INDIMCP-138).
    case duplicateRole(role: Role)

    var description: String {
        switch self {
        case .duplicateRole(let role):
            return "This rig has more than one component for the '\(role)' role, which isn't supported yet " +
                "(INDIMCP-138). The most common cause: both the main optical assembly and the guide optical " +
                "assembly have a focuser configured — remove one before saving."
        }
    }
}

/// Flattens one rig's constituent equipment-library entities into the `[Component]` list
/// INDIMCPKit's `saveRig` expects (§4.3). A free function rather than only a `RigProfile` method
/// so callers with the parts in hand but no persisted (or even inserted) `RigProfile` yet — e.g.
/// `RigEditForm.save()`, which holds each role as a separate `@State` var while the user is still
/// composing a new rig — can compute the flattened list directly, without constructing a
/// throwaway SwiftData model instance purely to call a method on it.
///
/// A role that isn't selected for this rig (`mount == nil`, or an optical assembly with no
/// focuser) is simply omitted from the result, matching §4.2's "blank vs. missing" model: a
/// component that's present with `device == nil` is a valid, saveable "blank" state; a role
/// that's absent entirely isn't represented at all.
///
/// - Throws: `RigProfileTranslationError.duplicateRole` if two components would resolve to the
///   same `Role`. Given this model's shape (every role, including the four standalone ones since
///   NAVI-85, is a single optional relationship, not an array), the only place this can actually
///   arise is `opticalAssembly` and `guideOpticalAssembly` both having a focuser — everything else
///   maps 1:1 from a distinct relationship to a distinct, fixed role, so duplication elsewhere
///   isn't representable in this UI at all.
func makeRigComponents(
    mount: MountProfile?,
    opticalAssembly: OpticalAssemblyProfile?,
    guideOpticalAssembly: OpticalAssemblyProfile?,
    imagingTrain: ImagingTrainProfile?,
    guideCamera: GuideCameraProfile?,
    powerHub: StandaloneEquipmentProfile?,
    flatScreen: StandaloneEquipmentProfile?,
    dewHeater: StandaloneEquipmentProfile?,
    observatoryControl: StandaloneEquipmentProfile?
) throws -> [Component] {
    var components: [Component] = []

    if let mount {
        components.append(Component(
            role: .mount,
            id: "mount",
            make: mount.make,
            model: mount.model,
            device: mount.deviceName
        ))
    }

    if let opticalAssembly {
        components.append(contentsOf: opticalAssembly.makeComponents(
            bodyRole: .telescope,
            bodyID: "telescope",
            focuserID: "focuser"
        ))
    }

    if let guideOpticalAssembly {
        components.append(contentsOf: guideOpticalAssembly.makeComponents(
            bodyRole: .guideTelescope,
            bodyID: "guideTelescope",
            focuserID: "guideFocuser"
        ))
    }

    // Flattened *through* the composition (NAVI-85 follow-up: ImagingTrainProfile no longer holds
    // flat camera/filter-wheel/rotator fields itself, just relationships to independently-owned
    // Camera/FilterWheel/RotatorProfile entities) — "is this role present" is simply "is the
    // relationship non-nil," the same test every other role in this function already uses.
    if let camera = imagingTrain?.camera {
        components.append(Component(
            role: .camera,
            id: "camera",
            make: camera.make,
            model: camera.model,
            device: camera.deviceName,
            cooled: camera.cooled,
            pixelsX: camera.pixelsX,
            pixelsY: camera.pixelsY,
            pixelSizeMicron: camera.pixelSizeMicron,
            bitDepth: camera.bitDepth
        ))
    }
    if let filterWheel = imagingTrain?.filterWheel {
        var slots: [Int: String]?
        if let filterWheelSlots = filterWheel.slots, !filterWheelSlots.isEmpty {
            slots = Dictionary(uniqueKeysWithValues: filterWheelSlots.map { ($0.slot, $0.name) })
        }
        components.append(Component(
            role: .filterWheel,
            id: "filterWheel",
            make: filterWheel.make,
            model: filterWheel.model,
            device: filterWheel.deviceName,
            slots: slots
        ))
    }
    if let rotator = imagingTrain?.rotator {
        components.append(Component(
            role: .rotator,
            id: "rotator",
            make: rotator.make,
            model: rotator.model,
            device: rotator.deviceName
        ))
    }

    if let guideCamera {
        components.append(Component(
            role: .guideCamera,
            id: "guideCamera",
            make: guideCamera.make,
            model: guideCamera.model,
            device: guideCamera.deviceName,
            cooled: guideCamera.cooled,
            pixelsX: guideCamera.pixelsX,
            pixelsY: guideCamera.pixelsY,
            pixelSizeMicron: guideCamera.pixelSizeMicron,
            bitDepth: guideCamera.bitDepth
        ))
    }

    // Fixed per-slot id, matching "mount"/"telescope"/"camera" above — simpler than trying to
    // carry over a user-authored or `persistentModelID`-derived id for a single-slot role.
    if let powerHub {
        components.append(Component(role: .powerHub, id: "powerHub", make: powerHub.make, model: powerHub.model, device: powerHub.deviceName))
    }
    if let flatScreen {
        components.append(Component(role: .flatScreen, id: "flatScreen", make: flatScreen.make, model: flatScreen.model, device: flatScreen.deviceName))
    }
    if let dewHeater {
        components.append(Component(role: .dewHeater, id: "dewHeater", make: dewHeater.make, model: dewHeater.model, device: dewHeater.deviceName))
    }
    if let observatoryControl {
        components.append(Component(role: .observatoryControl, id: "observatoryControl", make: observatoryControl.make, model: observatoryControl.model, device: observatoryControl.deviceName))
    }

    // Duplicate-role guard (see this function's doc comment for why the focuser pairing is the
    // only case reachable given this model's shape) — grouped generically rather than
    // hand-checking just that one pairing, so this stays correct if the model ever grows a second
    // way to produce the same role.
    let roleCounts = Dictionary(grouping: components, by: \.role).mapValues(\.count)
    if let duplicated = roleCounts.first(where: { $0.value > 1 })?.key {
        throw RigProfileTranslationError.duplicateRole(role: duplicated)
    }

    return components
}

extension RigProfile {
    /// Convenience wrapper over `makeRigComponents(mount:opticalAssembly:...)` for an already-
    /// composed `RigProfile` — see that function for the full behavior/throws contract.
    func makeComponents() throws -> [Component] {
        try makeRigComponents(
            mount: mount,
            opticalAssembly: opticalAssembly,
            guideOpticalAssembly: guideOpticalAssembly,
            imagingTrain: imagingTrain,
            guideCamera: guideCamera,
            powerHub: powerHub,
            flatScreen: flatScreen,
            dewHeater: dewHeater,
            observatoryControl: observatoryControl
        )
    }
}

private extension OpticalAssemblyProfile {
    /// Shared by `opticalAssembly`/`guideOpticalAssembly` — an optical assembly always produces
    /// its telescope-body component, plus a `.focuser` component only if `hasFocuser`.
    func makeComponents(bodyRole: Role, bodyID: String, focuserID: String) -> [Component] {
        var components = [Component(
            role: bodyRole,
            id: bodyID,
            make: make,
            model: model,
            apertureMm: apertureMm,
            focalLengthMm: focalLengthMm
        )]
        if hasFocuser {
            components.append(Component(
                role: .focuser,
                id: focuserID,
                make: focuserMake,
                model: focuserModel,
                device: focuserDeviceName,
                minPosition: focuserMinPosition,
                maxPosition: focuserMaxPosition
            ))
        }
        return components
    }
}
