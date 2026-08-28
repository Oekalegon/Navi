//
//  EquipmentLibrarySchema.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3.
//

import SwiftData

/// Version 1 of the equipment-library schema — Navi's first structured local data store
/// (previously just `UserDefaults`/Keychain and security-scoped bookmarks, per §4.3).
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
/// migration step existing. If `ObservatoryProfile` (or any model here) gains a real structural
/// change in the future, that's when a genuine new `VersionedSchema` entry belongs — and per
/// Apple's guidance, it should reference a **frozen snapshot type** for the old shape (e.g. a
/// nested type per version), not the live class reused across versions, to avoid this exact bug
/// recurring.
enum EquipmentLibrarySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MountProfile.self,
            OpticalAssemblyProfile.self,
            ImagingTrainProfile.self,
            GuideCameraProfile.self,
            ServerProfile.self,
            RigProfile.self,
            ObservatoryProfile.self,
        ]
    }
}

enum EquipmentLibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [EquipmentLibrarySchemaV1.self, EquipmentLibrarySchemaV2.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: EquipmentLibrarySchemaV1.self, toVersion: EquipmentLibrarySchemaV2.self)]
    }
}

/// Convenience alias for the schema's current version — what `NaviApp`'s `ModelContainer` and
/// tests build their `Schema`/`ModelConfiguration` from, without every call site needing to know
/// which `VersionedSchema` is current.
enum EquipmentLibrarySchema {
    static var models: [any PersistentModel.Type] { EquipmentLibrarySchemaV2.models }
}
