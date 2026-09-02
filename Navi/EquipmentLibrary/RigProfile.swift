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

    // Explicit `.nullify` on every optional to-one relationship below, rather than relying on
    // SwiftData's implicit default (which Apple's docs say is already `.nullify`) — makes the
    // intent unambiguous. Note for anyone testing this: asserting nullification by re-fetching
    // through the *same* ModelContext that performed the delete is unreliable — an already-
    // materialized object doesn't reliably reflect a delete+save that just happened in that same
    // context (see deletingAServerNullifiesRigsThatDefaultToIt in EquipmentLibrarySchemaTests,
    // which uses a fresh context for its post-delete fetch specifically because of this).
    @Relationship(deleteRule: .nullify) var mount: MountProfile?
    @Relationship(deleteRule: .nullify) var opticalAssembly: OpticalAssemblyProfile?
    @Relationship(deleteRule: .nullify) var guideOpticalAssembly: OpticalAssemblyProfile?
    @Relationship(deleteRule: .nullify) var imagingTrain: ImagingTrainProfile?
    @Relationship(deleteRule: .nullify) var guideCamera: GuideCameraProfile?
    // NAVI-85: these four used to be an anonymous `[StandaloneComponentEntry]` embedded directly
    // here (JSON-blob-backed, since SwiftData can't store arrays of custom Codable structs) — now
    // real named `StandaloneEquipmentProfile` library entities, same relationship shape as the five
    // above.
    @Relationship(deleteRule: .nullify) var powerHub: StandaloneEquipmentProfile?
    @Relationship(deleteRule: .nullify) var flatScreen: StandaloneEquipmentProfile?
    @Relationship(deleteRule: .nullify) var dewHeater: StandaloneEquipmentProfile?
    @Relationship(deleteRule: .nullify) var observatoryControl: StandaloneEquipmentProfile?

    /// The id of the server-side `Observatory` this rig defaults to. `Observatory` lives entirely
    /// server-side (fetched via `listObservatories`/`saveObservatory`) — Navi doesn't mirror it
    /// locally, so this is just a reference id, not a relationship.
    var defaultObservatoryID: String?

    /// The rig's default INDI-MCP server (§4.2) — overriding this mapping is a Settings-only
    /// action, never a transient toolbar override (§4.1).
    @Relationship(deleteRule: .nullify) var defaultServer: ServerProfile?

    /// When this rig's `Component` list was last pushed to the server via `saveRig`. Compared
    /// against each referenced library entity's `modifiedAt` to drive the §4.3 "Resync all"
    /// stale-Rig detection: a rig is stale once any entity it references has `modifiedAt` later
    /// than this.
    var lastResyncedAt: Date

    /// Fingerprint of the `Rig` payload as the server last accepted it (NAVI-86). Serves two jobs
    /// from one field: this rig needs pushing when its current digest differs from this, and
    /// someone else changed it underneath us when the *server's* current digest differs from this.
    /// `nil` means never pushed from this install.
    var lastPushedDigest: String?

    init(
        serverRigID: String,
        name: String,
        mount: MountProfile? = nil,
        opticalAssembly: OpticalAssemblyProfile? = nil,
        guideOpticalAssembly: OpticalAssemblyProfile? = nil,
        imagingTrain: ImagingTrainProfile? = nil,
        guideCamera: GuideCameraProfile? = nil,
        powerHub: StandaloneEquipmentProfile? = nil,
        flatScreen: StandaloneEquipmentProfile? = nil,
        dewHeater: StandaloneEquipmentProfile? = nil,
        observatoryControl: StandaloneEquipmentProfile? = nil,
        defaultObservatoryID: String? = nil,
        defaultServer: ServerProfile? = nil,
        lastResyncedAt: Date = .now,
        lastPushedDigest: String? = nil
    ) {
        self.serverRigID = serverRigID
        self.name = name
        self.mount = mount
        self.opticalAssembly = opticalAssembly
        self.guideOpticalAssembly = guideOpticalAssembly
        self.imagingTrain = imagingTrain
        self.guideCamera = guideCamera
        self.powerHub = powerHub
        self.flatScreen = flatScreen
        self.dewHeater = dewHeater
        self.observatoryControl = observatoryControl
        self.defaultObservatoryID = defaultObservatoryID
        self.defaultServer = defaultServer
        self.lastResyncedAt = lastResyncedAt
        self.lastPushedDigest = lastPushedDigest
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
            powerHub?.modifiedAt,
            flatScreen?.modifiedAt,
            dewHeater?.modifiedAt,
            observatoryControl?.modifiedAt,
            defaultServer?.modifiedAt,
        ].compactMap { $0 }
        return referencedEntityDates.contains { $0 > lastResyncedAt }
    }
}
