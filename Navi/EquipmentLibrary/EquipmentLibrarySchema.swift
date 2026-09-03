//
//  EquipmentLibrarySchema.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// Version 1 of the equipment-library schema — Navi's first structured local data store
/// (previously just `UserDefaults`/Keychain and security-scoped bookmarks, per §4.3).
///
/// NAVI-85 gave `MountProfile`/`OpticalAssemblyProfile`/`ImagingTrainProfile`/`GuideCameraProfile`/
/// `RigProfile` real structural changes (driver fields; `RigProfile`'s standalone-component storage
/// moved from a JSON blob to real relationships) — so, per this enum's own established lesson (see
/// `EquipmentLibrarySchemaV2`'s doc comment below), those five models can no longer be referenced by
/// their *live* type here: `VersionedSchema` hashes a version's checksum from whatever the
/// referenced type currently looks like, so a version that keeps pointing at a live type drifts
/// silently to match that type's *current* shape, not the shape this version actually shipped with.
/// The nested nested snapshot types below freeze V1's shape permanently — never edit them once
/// created; ordinary schema evolution happens by adding a new `VersionedSchema` case, not by
/// changing an old one's snapshot.
enum EquipmentLibrarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MountProfile.self,
            OpticalAssemblyProfile.self,
            ImagingTrainProfile.self,
            GuideCameraProfile.self,
            ServerProfile.self,
            RigProfile.self,
        ]
    }

    /// Frozen ahead of NAVI-68's `lastConnectedAt` addition — `ServerProfile` had stayed live
    /// (unchanged) through V2/V3/V4/V5, so each needed its own frozen copy in the same commit
    /// (V2 cross-references this one directly, matching its existing `RigProfile` precedent; V3/
    /// V4/V5 each declare an independent, identically-shaped nested copy instead, matching how
    /// e.g. `MountProfile` is redeclared per version even when unchanged — a version's checksum is
    /// computed from whatever a *live* type currently looks like, so a live reference can't be left
    /// as-is once the type it points at is about to change shape; see `EquipmentLibrarySchemaV3`'s
    /// doc comment for the general rule).
    @Model
    final class ServerProfile {
        var name: String
        var url: URL
        var notes: String?
        var modifiedAt: Date

        init(name: String, url: URL, notes: String? = nil, modifiedAt: Date = .now) {
            self.name = name
            self.url = url
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class MountProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var notes: String?
        var modifiedAt: Date

        init(name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil, notes: String? = nil, modifiedAt: Date = .now) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class OpticalAssemblyProfile {
        var name: String
        var make: String?
        var model: String?
        var apertureMm: Double?
        var focalLengthMm: Double?
        var opticalDesign: OpticalDesign?
        var purpose: OpticalAssemblyPurpose
        var focuserMake: String?
        var focuserModel: String?
        var focuserDeviceName: String?
        var focuserMinPosition: Int?
        var focuserMaxPosition: Int?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, apertureMm: Double? = nil,
            focalLengthMm: Double? = nil, opticalDesign: OpticalDesign? = nil,
            purpose: OpticalAssemblyPurpose = .mainImaging, focuserMake: String? = nil,
            focuserModel: String? = nil, focuserDeviceName: String? = nil,
            focuserMinPosition: Int? = nil, focuserMaxPosition: Int? = nil, notes: String? = nil,
            modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.apertureMm = apertureMm
            self.focalLengthMm = focalLengthMm
            self.opticalDesign = opticalDesign
            self.purpose = purpose
            self.focuserMake = focuserMake
            self.focuserModel = focuserModel
            self.focuserDeviceName = focuserDeviceName
            self.focuserMinPosition = focuserMinPosition
            self.focuserMaxPosition = focuserMaxPosition
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

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
        private var filterWheelSlotsData: Data?
        var rotatorMake: String?
        var rotatorModel: String?
        var rotatorDeviceName: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, cameraMake: String? = nil, cameraModel: String? = nil,
            cameraDeviceName: String? = nil, cameraCooled: Bool? = nil, cameraPixelsX: Int? = nil,
            cameraPixelsY: Int? = nil, cameraPixelSizeMicron: Double? = nil, cameraBitDepth: Int? = nil,
            filterWheelMake: String? = nil, filterWheelModel: String? = nil,
            filterWheelDeviceName: String? = nil, filterWheelSlotsData: Data? = nil,
            rotatorMake: String? = nil, rotatorModel: String? = nil, rotatorDeviceName: String? = nil,
            notes: String? = nil, modifiedAt: Date = .now
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
            self.filterWheelSlotsData = filterWheelSlotsData
            self.rotatorMake = rotatorMake
            self.rotatorModel = rotatorModel
            self.rotatorDeviceName = rotatorDeviceName
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

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
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            cooled: Bool? = nil, pixelsX: Int? = nil, pixelsY: Int? = nil,
            pixelSizeMicron: Double? = nil, bitDepth: Int? = nil, notes: String? = nil,
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

    @Model
    final class RigProfile {
        @Attribute(.unique) var serverRigID: String
        var name: String
        @Relationship(deleteRule: .nullify) var mount: MountProfile?
        @Relationship(deleteRule: .nullify) var opticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var guideOpticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var imagingTrain: ImagingTrainProfile?
        @Relationship(deleteRule: .nullify) var guideCamera: GuideCameraProfile?
        var defaultObservatoryID: String?
        @Relationship(deleteRule: .nullify) var defaultServer: ServerProfile?
        private var standaloneComponentsData: Data
        var lastResyncedAt: Date

        init(
            serverRigID: String, name: String, mount: MountProfile? = nil,
            opticalAssembly: OpticalAssemblyProfile? = nil,
            guideOpticalAssembly: OpticalAssemblyProfile? = nil,
            imagingTrain: ImagingTrainProfile? = nil, guideCamera: GuideCameraProfile? = nil,
            defaultObservatoryID: String? = nil, defaultServer: ServerProfile? = nil,
            standaloneComponentsData: Data = Data(), lastResyncedAt: Date = .now
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
            self.standaloneComponentsData = standaloneComponentsData
            self.lastResyncedAt = lastResyncedAt
        }
    }
}

/// Version 2 — adds `ObservatoryProfile` (§4.1's local Observatory cache), including its
/// `latitudeDeg`/`longitudeDeg`/`elevationMeters` fields (§4.2's Observatory Settings pane).
///
/// A prior draft of this file split this into a separate V3 that referenced the exact same live
/// `ObservatoryProfile` type as V2 with no structural difference — `VersionedSchema` derives its
/// checksum from the live type's current `@Attribute` shape, not from a frozen historical
/// snapshot, so two versions pointing at the same unchanged type hash identically. SwiftData's
/// migration-plan validation rejects that outright at `ModelContainer` init with "Duplicate
/// version checksums detected," before any store even exists — confirmed by reproducing the
/// crash locally. Collapsed back to one version here since nothing shipped depends on a V3
/// migration step existing.
///
/// The other five models are unchanged since V1, so V2 reuses `EquipmentLibrarySchemaV1`'s frozen
/// nested types directly rather than duplicating them — `ServerProfile`/`ObservatoryProfile` are
/// still referenced live here since neither has (yet) had a post-V2 structural change.
enum EquipmentLibrarySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            EquipmentLibrarySchemaV1.MountProfile.self,
            EquipmentLibrarySchemaV1.OpticalAssemblyProfile.self,
            EquipmentLibrarySchemaV1.ImagingTrainProfile.self,
            EquipmentLibrarySchemaV1.GuideCameraProfile.self,
            EquipmentLibrarySchemaV1.ServerProfile.self,
            EquipmentLibrarySchemaV1.RigProfile.self,
            ObservatoryProfile.self,
        ]
    }
}

/// Version 3 (NAVI-85) — the Equipment Library pane redesign: `MountProfile`/
/// `OpticalAssemblyProfile`/`ImagingTrainProfile`/`GuideCameraProfile` each gain an optional
/// preferred-driver field (or three, for `ImagingTrainProfile`'s three device-bearing sub-roles),
/// and `RigProfile` drops its `standaloneComponentsData` JSON blob in favor of four real
/// relationships to the new `StandaloneEquipmentProfile` — see each type's own doc comment.
///
/// **Naming convention for frozen snapshots (read before adding a version).** A nested snapshot
/// keeps the *exact class name* of the live type it photographs — `MountProfile`, not
/// `MountProfileV3`. SwiftData derives an entity (table) name from the class name, so a suffixed
/// snapshot would describe a `ZMOUNTPROFILEV3` table that no store ever had, while the real store
/// writes `ZMOUNTPROFILE` (verified by inspecting the on-disk SQLite schema). Same-named nested
/// types are unambiguous because Swift lexical scoping resolves an unqualified reference inside a
/// version's own body to that version's sibling snapshot, shadowing the global — which is why the
/// `models` list below reads as bare `MountProfile.self` yet refers to *this* enum's copy, and why
/// `V2` must qualify explicitly (`EquipmentLibrarySchemaV1.MountProfile.self`) to reach V1's.
///
/// **When to freeze.** Freeze a model into a version at the moment you are about to change that
/// model's live shape — and freeze *every* prior version that still references it live, in the same
/// commit. A version's checksum is computed by reflecting over whatever the referenced types look
/// like *right now*, so a version pointing at a live type silently rewrites its own history the
/// next time that type changes. All eight models below are frozen: V4 changes `ImagingTrainProfile`
/// (flat fields to a composition) and therefore `RigProfile`'s `imagingTrain` relationship target,
/// and V5 removes `preferredDriverLabel` from the rest. `ObservatoryProfile` stays live because it
/// hasn't changed since V3; `ServerProfile` gets its own independent frozen copy here too, ahead
/// of NAVI-68's `lastConnectedAt` addition (V6).
enum EquipmentLibrarySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MountProfile.self,
            OpticalAssemblyProfile.self,
            ImagingTrainProfile.self,
            GuideCameraProfile.self,
            ServerProfile.self,
            RigProfile.self,
            ObservatoryProfile.self,
            StandaloneEquipmentProfile.self,
        ]
    }

    @Model
    final class ServerProfile {
        var name: String
        var url: URL
        var notes: String?
        var modifiedAt: Date

        init(name: String, url: URL, notes: String? = nil, modifiedAt: Date = .now) {
            self.name = name
            self.url = url
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class MountProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class OpticalAssemblyProfile {
        var name: String
        var make: String?
        var model: String?
        var apertureMm: Double?
        var focalLengthMm: Double?
        var opticalDesign: OpticalDesign?
        var purpose: OpticalAssemblyPurpose
        var focuserMake: String?
        var focuserModel: String?
        var focuserDeviceName: String?
        var focuserPreferredDriverLabel: String?
        var focuserMinPosition: Int?
        var focuserMaxPosition: Int?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, apertureMm: Double? = nil,
            focalLengthMm: Double? = nil, opticalDesign: OpticalDesign? = nil,
            purpose: OpticalAssemblyPurpose = .mainImaging, focuserMake: String? = nil,
            focuserModel: String? = nil, focuserDeviceName: String? = nil,
            focuserPreferredDriverLabel: String? = nil, focuserMinPosition: Int? = nil,
            focuserMaxPosition: Int? = nil, notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.apertureMm = apertureMm
            self.focalLengthMm = focalLengthMm
            self.opticalDesign = opticalDesign
            self.purpose = purpose
            self.focuserMake = focuserMake
            self.focuserModel = focuserModel
            self.focuserDeviceName = focuserDeviceName
            self.focuserPreferredDriverLabel = focuserPreferredDriverLabel
            self.focuserMinPosition = focuserMinPosition
            self.focuserMaxPosition = focuserMaxPosition
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class GuideCameraProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var cooled: Bool?
        var pixelsX: Int?
        var pixelsY: Int?
        var pixelSizeMicron: Double?
        var bitDepth: Int?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, cooled: Bool? = nil, pixelsX: Int? = nil,
            pixelsY: Int? = nil, pixelSizeMicron: Double? = nil, bitDepth: Int? = nil,
            notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.cooled = cooled
            self.pixelsX = pixelsX
            self.pixelsY = pixelsY
            self.pixelSizeMicron = pixelSizeMicron
            self.bitDepth = bitDepth
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class StandaloneEquipmentProfile {
        var name: String
        var role: StandaloneEquipmentRole
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, role: StandaloneEquipmentRole, make: String? = nil, model: String? = nil,
            deviceName: String? = nil, preferredDriverLabel: String? = nil, notes: String? = nil,
            modifiedAt: Date = .now
        ) {
            self.name = name
            self.role = role
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class ImagingTrainProfile {
        var name: String
        var cameraMake: String?
        var cameraModel: String?
        var cameraDeviceName: String?
        var cameraPreferredDriverLabel: String?
        var cameraCooled: Bool?
        var cameraPixelsX: Int?
        var cameraPixelsY: Int?
        var cameraPixelSizeMicron: Double?
        var cameraBitDepth: Int?
        var filterWheelMake: String?
        var filterWheelModel: String?
        var filterWheelDeviceName: String?
        var filterWheelPreferredDriverLabel: String?
        private var filterWheelSlotsData: Data?
        var rotatorMake: String?
        var rotatorModel: String?
        var rotatorDeviceName: String?
        var rotatorPreferredDriverLabel: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, cameraMake: String? = nil, cameraModel: String? = nil,
            cameraDeviceName: String? = nil, cameraPreferredDriverLabel: String? = nil,
            cameraCooled: Bool? = nil, cameraPixelsX: Int? = nil, cameraPixelsY: Int? = nil,
            cameraPixelSizeMicron: Double? = nil, cameraBitDepth: Int? = nil,
            filterWheelMake: String? = nil, filterWheelModel: String? = nil,
            filterWheelDeviceName: String? = nil, filterWheelPreferredDriverLabel: String? = nil,
            filterWheelSlotsData: Data? = nil, rotatorMake: String? = nil,
            rotatorModel: String? = nil, rotatorDeviceName: String? = nil,
            rotatorPreferredDriverLabel: String? = nil, notes: String? = nil,
            modifiedAt: Date = .now
        ) {
            self.name = name
            self.cameraMake = cameraMake
            self.cameraModel = cameraModel
            self.cameraDeviceName = cameraDeviceName
            self.cameraPreferredDriverLabel = cameraPreferredDriverLabel
            self.cameraCooled = cameraCooled
            self.cameraPixelsX = cameraPixelsX
            self.cameraPixelsY = cameraPixelsY
            self.cameraPixelSizeMicron = cameraPixelSizeMicron
            self.cameraBitDepth = cameraBitDepth
            self.filterWheelMake = filterWheelMake
            self.filterWheelModel = filterWheelModel
            self.filterWheelDeviceName = filterWheelDeviceName
            self.filterWheelPreferredDriverLabel = filterWheelPreferredDriverLabel
            self.filterWheelSlotsData = filterWheelSlotsData
            self.rotatorMake = rotatorMake
            self.rotatorModel = rotatorModel
            self.rotatorDeviceName = rotatorDeviceName
            self.rotatorPreferredDriverLabel = rotatorPreferredDriverLabel
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class RigProfile {
        @Attribute(.unique) var serverRigID: String
        var name: String
        @Relationship(deleteRule: .nullify) var mount: MountProfile?
        @Relationship(deleteRule: .nullify) var opticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var guideOpticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var imagingTrain: ImagingTrainProfile?
        @Relationship(deleteRule: .nullify) var guideCamera: GuideCameraProfile?
        @Relationship(deleteRule: .nullify) var powerHub: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var flatScreen: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var dewHeater: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var observatoryControl: StandaloneEquipmentProfile?
        var defaultObservatoryID: String?
        @Relationship(deleteRule: .nullify) var defaultServer: ServerProfile?
        var lastResyncedAt: Date

        init(
            serverRigID: String, name: String, mount: MountProfile? = nil,
            opticalAssembly: OpticalAssemblyProfile? = nil,
            guideOpticalAssembly: OpticalAssemblyProfile? = nil,
            imagingTrain: ImagingTrainProfile? = nil, guideCamera: GuideCameraProfile? = nil,
            powerHub: StandaloneEquipmentProfile? = nil, flatScreen: StandaloneEquipmentProfile? = nil,
            dewHeater: StandaloneEquipmentProfile? = nil,
            observatoryControl: StandaloneEquipmentProfile? = nil, defaultObservatoryID: String? = nil,
            defaultServer: ServerProfile? = nil, lastResyncedAt: Date = .now
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
        }
    }
}

/// Version 4 (NAVI-85 follow-up) — splits `ImagingTrainProfile`'s flat camera/filter-wheel/rotator
/// fields into three independently-owned equipment types (`CameraProfile`/`FilterWheelProfile`/
/// `RotatorProfile`), each managed on their own in the Equipment pane; `ImagingTrainProfile` becomes
/// a pure composition of relationships to them, the same shape `RigProfile` already uses for its
/// own roles. See each type's own doc comment.
///
/// Every model is frozen here (see `EquipmentLibrarySchemaV3`'s doc comment for the naming
/// convention and the rule about *when* to freeze): V5 removes `preferredDriverLabel` from all of
/// them, and the three new types plus `ImagingTrainProfile`/`RigProfile` are only this shape as of
/// V4. `ObservatoryProfile` stays live — it hasn't changed since V2; `ServerProfile` gets its own
/// independent frozen copy here too (NAVI-68), not live.
enum EquipmentLibrarySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MountProfile.self,
            OpticalAssemblyProfile.self,
            ImagingTrainProfile.self,
            GuideCameraProfile.self,
            ServerProfile.self,
            RigProfile.self,
            ObservatoryProfile.self,
            StandaloneEquipmentProfile.self,
            CameraProfile.self,
            FilterWheelProfile.self,
            RotatorProfile.self,
        ]
    }

    @Model
    final class ServerProfile {
        var name: String
        var url: URL
        var notes: String?
        var modifiedAt: Date

        init(name: String, url: URL, notes: String? = nil, modifiedAt: Date = .now) {
            self.name = name
            self.url = url
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class MountProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class OpticalAssemblyProfile {
        var name: String
        var make: String?
        var model: String?
        var apertureMm: Double?
        var focalLengthMm: Double?
        var opticalDesign: OpticalDesign?
        var purpose: OpticalAssemblyPurpose
        var focuserMake: String?
        var focuserModel: String?
        var focuserDeviceName: String?
        var focuserPreferredDriverLabel: String?
        var focuserMinPosition: Int?
        var focuserMaxPosition: Int?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, apertureMm: Double? = nil,
            focalLengthMm: Double? = nil, opticalDesign: OpticalDesign? = nil,
            purpose: OpticalAssemblyPurpose = .mainImaging, focuserMake: String? = nil,
            focuserModel: String? = nil, focuserDeviceName: String? = nil,
            focuserPreferredDriverLabel: String? = nil, focuserMinPosition: Int? = nil,
            focuserMaxPosition: Int? = nil, notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.apertureMm = apertureMm
            self.focalLengthMm = focalLengthMm
            self.opticalDesign = opticalDesign
            self.purpose = purpose
            self.focuserMake = focuserMake
            self.focuserModel = focuserModel
            self.focuserDeviceName = focuserDeviceName
            self.focuserPreferredDriverLabel = focuserPreferredDriverLabel
            self.focuserMinPosition = focuserMinPosition
            self.focuserMaxPosition = focuserMaxPosition
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class CameraProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var cooled: Bool?
        var pixelsX: Int?
        var pixelsY: Int?
        var pixelSizeMicron: Double?
        var bitDepth: Int?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, cooled: Bool? = nil, pixelsX: Int? = nil,
            pixelsY: Int? = nil, pixelSizeMicron: Double? = nil, bitDepth: Int? = nil,
            notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.cooled = cooled
            self.pixelsX = pixelsX
            self.pixelsY = pixelsY
            self.pixelSizeMicron = pixelSizeMicron
            self.bitDepth = bitDepth
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class FilterWheelProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        private var slotsData: Data?
        var slots: [FilterSlotEntry]? {
            get { slotsData.flatMap { try? JSONDecoder().decode([FilterSlotEntry].self, from: $0) } }
            set { slotsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
        }
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, slots: [FilterSlotEntry]? = nil,
            notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.slotsData = nil
            self.notes = notes
            self.modifiedAt = modifiedAt
            self.slots = slots
        }
    }

    @Model
    final class RotatorProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class GuideCameraProfile {
        var name: String
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var cooled: Bool?
        var pixelsX: Int?
        var pixelsY: Int?
        var pixelSizeMicron: Double?
        var bitDepth: Int?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, make: String? = nil, model: String? = nil, deviceName: String? = nil,
            preferredDriverLabel: String? = nil, cooled: Bool? = nil, pixelsX: Int? = nil,
            pixelsY: Int? = nil, pixelSizeMicron: Double? = nil, bitDepth: Int? = nil,
            notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.cooled = cooled
            self.pixelsX = pixelsX
            self.pixelsY = pixelsY
            self.pixelSizeMicron = pixelSizeMicron
            self.bitDepth = bitDepth
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class StandaloneEquipmentProfile {
        var name: String
        var role: StandaloneEquipmentRole
        var make: String?
        var model: String?
        var deviceName: String?
        var preferredDriverLabel: String?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, role: StandaloneEquipmentRole, make: String? = nil, model: String? = nil,
            deviceName: String? = nil, preferredDriverLabel: String? = nil, notes: String? = nil,
            modifiedAt: Date = .now
        ) {
            self.name = name
            self.role = role
            self.make = make
            self.model = model
            self.deviceName = deviceName
            self.preferredDriverLabel = preferredDriverLabel
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class ImagingTrainProfile {
        var name: String
        @Relationship(deleteRule: .nullify) var camera: CameraProfile?
        @Relationship(deleteRule: .nullify) var filterWheel: FilterWheelProfile?
        @Relationship(deleteRule: .nullify) var rotator: RotatorProfile?
        var notes: String?
        var modifiedAt: Date

        init(
            name: String, camera: CameraProfile? = nil, filterWheel: FilterWheelProfile? = nil,
            rotator: RotatorProfile? = nil, notes: String? = nil, modifiedAt: Date = .now
        ) {
            self.name = name
            self.camera = camera
            self.filterWheel = filterWheel
            self.rotator = rotator
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    @Model
    final class RigProfile {
        @Attribute(.unique) var serverRigID: String
        var name: String
        @Relationship(deleteRule: .nullify) var mount: MountProfile?
        @Relationship(deleteRule: .nullify) var opticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var guideOpticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var imagingTrain: ImagingTrainProfile?
        @Relationship(deleteRule: .nullify) var guideCamera: GuideCameraProfile?
        @Relationship(deleteRule: .nullify) var powerHub: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var flatScreen: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var dewHeater: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var observatoryControl: StandaloneEquipmentProfile?
        var defaultObservatoryID: String?
        @Relationship(deleteRule: .nullify) var defaultServer: ServerProfile?
        var lastResyncedAt: Date

        init(
            serverRigID: String, name: String, mount: MountProfile? = nil,
            opticalAssembly: OpticalAssemblyProfile? = nil,
            guideOpticalAssembly: OpticalAssemblyProfile? = nil,
            imagingTrain: ImagingTrainProfile? = nil, guideCamera: GuideCameraProfile? = nil,
            powerHub: StandaloneEquipmentProfile? = nil, flatScreen: StandaloneEquipmentProfile? = nil,
            dewHeater: StandaloneEquipmentProfile? = nil,
            observatoryControl: StandaloneEquipmentProfile? = nil, defaultObservatoryID: String? = nil,
            defaultServer: ServerProfile? = nil, lastResyncedAt: Date = .now
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
        }
    }
}

/// Version 5 (NAVI-85 second follow-up) — drops the "Preferred Driver" field/picker from every
/// equipment type. Starting/stopping an INDI driver is server-wide configuration
/// (`DriverManagementSheet`, embedded in the Server pane), not a per-equipment-item choice, and the
/// full driver catalog was an unusably long list to pick from once per piece of equipment — the
/// live `INDI Device` picker (already restricted to the *connected*, relevant devices) is the only
/// device-selection affordance equipment needs.
enum EquipmentLibrarySchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MountProfile.self,
            OpticalAssemblyProfile.self,
            ImagingTrainProfile.self,
            GuideCameraProfile.self,
            ServerProfile.self,
            RigProfile.self,
            ObservatoryProfile.self,
            StandaloneEquipmentProfile.self,
            CameraProfile.self,
            FilterWheelProfile.self,
            RotatorProfile.self,
        ]
    }

    @Model
    final class ServerProfile {
        var name: String
        var url: URL
        var notes: String?
        var modifiedAt: Date

        init(name: String, url: URL, notes: String? = nil, modifiedAt: Date = .now) {
            self.name = name
            self.url = url
            self.notes = notes
            self.modifiedAt = modifiedAt
        }
    }

    // NAVI-68: unlike every other model in this version's `models` list (all live/unqualified,
    // correctly picking up V5's real final shape since only `ServerProfile` is about to change),
    // `RigProfile` has to be frozen here too — it *holds a relationship* to `ServerProfile`
    // (`defaultServer`), and the live production `RigProfile` (RigProfile.swift) declares that
    // relationship as bare `ServerProfile?`, which resolves to the *live* `ServerProfile` (i.e.
    // gains `lastConnectedAt` the moment that lands) rather than the frozen copy this version's
    // `models` list actually declares as its `ServerProfile` entity. Reproduced and confirmed as
    // "Duplicate version checksums detected" at `ModelContainer` init before adding this freeze —
    // any entity with a relationship into a changing type needs freezing too, not just the type
    // whose own shape changes.
    @Model
    final class RigProfile {
        @Attribute(.unique) var serverRigID: String
        var name: String
        @Relationship(deleteRule: .nullify) var mount: MountProfile?
        @Relationship(deleteRule: .nullify) var opticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var guideOpticalAssembly: OpticalAssemblyProfile?
        @Relationship(deleteRule: .nullify) var imagingTrain: ImagingTrainProfile?
        @Relationship(deleteRule: .nullify) var guideCamera: GuideCameraProfile?
        @Relationship(deleteRule: .nullify) var powerHub: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var flatScreen: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var dewHeater: StandaloneEquipmentProfile?
        @Relationship(deleteRule: .nullify) var observatoryControl: StandaloneEquipmentProfile?
        var defaultObservatoryID: String?
        @Relationship(deleteRule: .nullify) var defaultServer: ServerProfile?
        var lastResyncedAt: Date

        init(
            serverRigID: String, name: String, mount: MountProfile? = nil,
            opticalAssembly: OpticalAssemblyProfile? = nil,
            guideOpticalAssembly: OpticalAssemblyProfile? = nil,
            imagingTrain: ImagingTrainProfile? = nil, guideCamera: GuideCameraProfile? = nil,
            powerHub: StandaloneEquipmentProfile? = nil, flatScreen: StandaloneEquipmentProfile? = nil,
            dewHeater: StandaloneEquipmentProfile? = nil,
            observatoryControl: StandaloneEquipmentProfile? = nil, defaultObservatoryID: String? = nil,
            defaultServer: ServerProfile? = nil, lastResyncedAt: Date = .now
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
        }
    }
}

/// Version 6 (NAVI-68) — adds `ServerProfile.lastConnectedAt`, so `ServerProfile` becomes live
/// again here after each of V1-V5 froze their own independent, identically-shaped copy of it (see
/// `EquipmentLibrarySchemaV3`'s doc comment). Every other model is unchanged since V5 and stays
/// live/unqualified, matching V5's own list.
///
/// `versionIdentifier` is `(6, 1, 0)`, not the "next" `(6, 0, 0)` — a concurrently in-flight
/// branch (NAVI-86) also defines its own, differently-shaped `(6, 0, 0)`. Reopening a store this
/// machine had already opened under that other `(6, 0, 0)` crashed outright with CoreData's
/// "Duplicate version checksums detected" (an uncatchable `NSException`, not a thrown `Error`) —
/// two schemas claiming the identical version number with different checksums, reproduced and
/// confirmed by bumping just the minor number, which made the crash disappear with no other
/// change. Whichever of the two branches merges second must renumber to avoid this permanently.
enum EquipmentLibrarySchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            MountProfile.self,
            OpticalAssemblyProfile.self,
            ImagingTrainProfile.self,
            GuideCameraProfile.self,
            ServerProfile.self,
            RigProfile.self,
            ObservatoryProfile.self,
            StandaloneEquipmentProfile.self,
            CameraProfile.self,
            FilterWheelProfile.self,
            RotatorProfile.self,
        ]
    }
}

enum EquipmentLibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            EquipmentLibrarySchemaV1.self, EquipmentLibrarySchemaV2.self, EquipmentLibrarySchemaV3.self,
            EquipmentLibrarySchemaV4.self, EquipmentLibrarySchemaV5.self, EquipmentLibrarySchemaV6.self,
        ]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: EquipmentLibrarySchemaV1.self, toVersion: EquipmentLibrarySchemaV2.self),
            // Lightweight migration only changes *shape*, not *values* — any rig with standalone
            // components already configured (Power Hub/Flat Screen/Dew Heater/Observatory Control)
            // loses those specific bindings here, since there's no automatic way to translate the
            // old JSON-blob entries into new StandaloneEquipmentProfile rows/relationships. Accepted
            // for NAVI-85 given this is pre-release local testing data — re-configure once, after.
            .lightweight(fromVersion: EquipmentLibrarySchemaV2.self, toVersion: EquipmentLibrarySchemaV3.self),
            // Same tradeoff again: any Imaging Train already configured loses its camera/filter-
            // wheel/rotator bindings here — there's no automatic way to turn the old flat fields
            // into new relationship targets. Accepted for the same reason as the stage above.
            .lightweight(fromVersion: EquipmentLibrarySchemaV3.self, toVersion: EquipmentLibrarySchemaV4.self),
            // Dropping `preferredDriverLabel` is a pure field removal — lightweight migration
            // handles this without any value loss elsewhere.
            .lightweight(fromVersion: EquipmentLibrarySchemaV4.self, toVersion: EquipmentLibrarySchemaV5.self),
            // Adding an optional `lastConnectedAt` is a pure field addition — no value loss.
            .lightweight(fromVersion: EquipmentLibrarySchemaV5.self, toVersion: EquipmentLibrarySchemaV6.self),
        ]
    }
}

/// Convenience alias for the schema's current version — what `NaviApp`'s `ModelContainer` and
/// tests build their `Schema`/`ModelConfiguration` from, without every call site needing to know
/// which `VersionedSchema` is current.
enum EquipmentLibrarySchema {
    static var models: [any PersistentModel.Type] { EquipmentLibrarySchemaV6.models }
}
