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
            ServerProfile.self,
            EquipmentLibrarySchemaV1.RigProfile.self,
            ObservatoryProfile.self,
        ]
    }
}

/// Version 3 (NAVI-85) — the Equipment Library pane redesign: `MountProfile`/
/// `OpticalAssemblyProfile`/`ImagingTrainProfile`/`GuideCameraProfile` each gain an optional
/// preferred-driver field (or three, for `ImagingTrainProfile`'s three device-bearing sub-roles),
/// and `RigProfile` drops its `standaloneComponentsData` JSON blob in favor of four real
/// relationships to the new `StandaloneEquipmentProfile` — see each type's own doc comment. This is
/// the first version to actually diverge in shape from `EquipmentLibrarySchemaV1`'s frozen
/// snapshots, so it's the first to need its own real migration stage (see
/// `EquipmentLibraryMigrationPlan.stages`) rather than reusing V1's types.
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
}

enum EquipmentLibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EquipmentLibrarySchemaV1.self, EquipmentLibrarySchemaV2.self, EquipmentLibrarySchemaV3.self]
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
        ]
    }
}

/// Convenience alias for the schema's current version — what `NaviApp`'s `ModelContainer` and
/// tests build their `Schema`/`ModelConfiguration` from, without every call site needing to know
/// which `VersionedSchema` is current.
enum EquipmentLibrarySchema {
    static var models: [any PersistentModel.Type] { EquipmentLibrarySchemaV3.models }
}
