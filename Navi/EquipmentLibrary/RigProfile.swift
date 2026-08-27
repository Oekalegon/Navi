//
//  RigProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// Navi-local companion record tracking which equipment-library entities compose one saved
/// server-side `Rig` (INDIMCPKit's `Rig` only ever sees the *flattened* `Component` list a
/// `RigProfile` gets translated into on save — it has no concept of reusable library entities).
/// This is what lets "swap the whole Imaging Train" work as a unit later, rather than every Rig
/// edit meaning re-picking every field from scratch (§4.3).
///
/// Named `RigProfile`, not `Rig`, to avoid colliding with INDIMCPKit's `Rig` — that type is the
/// server-side wire format; this type is Navi's local record of *how* a `Rig` was composed.
///
/// `guideOpticalAssembly` and `guideCamera` together capture where a guide camera attaches
/// (§4.3): if `guideOpticalAssembly` is set, the guide camera rides on that separate piggyback
/// scope; if it's `nil` but `guideCamera` is set, the guide camera is an off-axis guider inserted
/// directly into `imagingTrain` instead. `opticalAssembly` (the main imaging tube) and
/// `guideOpticalAssembly` are independent relationships — they may even point at the same
/// `OpticalAssemblyProfile` in an unusual setup, though normally they won't.
///
/// Every device-bearing role (mount, optical assembly's focuser, imaging train's camera/filter
/// wheel/rotator, guide camera) is optional here for the same reason it's optional in a Rig's
/// component list (§4.2): a role that isn't selected for this rig is simply omitted, not forced.
@Model
final class RigProfile {
    /// The id of the corresponding server-side `Rig`, once saved via `saveRig`.
    @Attribute(.unique) var serverRigID: String

    /// Cached display name — kept in sync with the server-side `Rig.name` at save/resync time,
    /// not authoritative; the server owns the real name.
    var name: String

    var mount: MountProfile?
    var opticalAssembly: OpticalAssemblyProfile?
    var guideOpticalAssembly: OpticalAssemblyProfile?
    var imagingTrain: ImagingTrainProfile?
    var guideCamera: GuideCameraProfile?

    /// The id of the server-side `Observatory` this rig defaults to. `Observatory` lives entirely
    /// server-side (fetched via `listObservatories`/`saveObservatory`) — Navi doesn't mirror it
    /// locally, so this is just a reference id, not a relationship.
    var defaultObservatoryID: String?

    /// The rig's default INDI-MCP server (§4.2) — overriding this mapping is a Settings-only
    /// action, never a transient toolbar override (§4.1).
    var defaultServer: ServerProfile?

    // Stored as JSON `Data`, not `[StandaloneComponentEntry]` directly — SwiftData's "collection
    // of codable" attribute support fails a runtime cast for custom struct arrays at save/fetch
    // time, confirmed empirically (see `ImagingTrainProfile.filterWheelSlotsData`). `Data` is a
    // plain, reliably-supported attribute type.
    private var standaloneComponentsData: Data

    /// Components for roles with no reusable library entity (§4.3): `.powerHub`,
    /// `.observatoryControl`, `.flatScreen`, `.dewHeater`.
    var standaloneComponents: [StandaloneComponentEntry] {
        get { (try? JSONDecoder().decode([StandaloneComponentEntry].self, from: standaloneComponentsData)) ?? [] }
        set { standaloneComponentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// When this rig's `Component` list was last pushed to the server via `saveRig`. Compared
    /// against each referenced library entity's `modifiedAt` to drive the §4.3 "Resync all"
    /// stale-Rig detection: a rig is stale once any entity it references has `modifiedAt` later
    /// than this.
    var lastResyncedAt: Date

    init(
        serverRigID: String,
        name: String,
        mount: MountProfile? = nil,
        opticalAssembly: OpticalAssemblyProfile? = nil,
        guideOpticalAssembly: OpticalAssemblyProfile? = nil,
        imagingTrain: ImagingTrainProfile? = nil,
        guideCamera: GuideCameraProfile? = nil,
        defaultObservatoryID: String? = nil,
        defaultServer: ServerProfile? = nil,
        standaloneComponents: [StandaloneComponentEntry] = [],
        lastResyncedAt: Date = .now
    ) {
        self.serverRigID = serverRigID
        self.name = name
        self.mount = mount
        self.opticalAssembly = opticalAssembly
        self.guideOpticalAssembly = guideOpticalAssembly
        self.imagingTrain = imagingTrain
        self.guideCamera = guideCamera
        self.defaultObservatoryID = defaultObservatoryID
        self.defaultServer = defaultServer
        self.standaloneComponentsData = Data()
        self.lastResyncedAt = lastResyncedAt
        // Must come after every stored property above is set (definite initialization) since
        // this goes through the computed `standaloneComponents` setter, not a plain assignment.
        self.standaloneComponents = standaloneComponents
    }

    /// Whether any referenced library entity has changed since this rig was last resynced —
    /// the trigger for the §4.3 "Resync all" affordance.
    var hasStaleLibraryReferences: Bool {
        let referencedEntityDates = [
            mount?.modifiedAt,
            opticalAssembly?.modifiedAt,
            guideOpticalAssembly?.modifiedAt,
            imagingTrain?.modifiedAt,
            guideCamera?.modifiedAt,
            defaultServer?.modifiedAt,
        ].compactMap { $0 }
        return referencedEntityDates.contains { $0 > lastResyncedAt }
    }
}
