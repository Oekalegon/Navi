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

/// Version 2 — adds `ObservatoryProfile` (§4.1's local Observatory cache). Purely additive, no
/// existing model's fields changed, so the migration below is a lightweight/inferred one.
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
    static var schemas: [any VersionedSchema.Type] { [EquipmentLibrarySchemaV1.self, EquipmentLibrarySchemaV2.self] }
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
