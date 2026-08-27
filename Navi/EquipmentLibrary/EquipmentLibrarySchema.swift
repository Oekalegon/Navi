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

/// No migrations yet — `EquipmentLibrarySchemaV1` is the schema's first version. Add a
/// `MigrationStage` here (and a new `VersionedSchema` to `schemas`) once a second version exists.
enum EquipmentLibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [EquipmentLibrarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Convenience alias for the schema's current version — what `NaviApp`'s `ModelContainer` and
/// tests build their `Schema`/`ModelConfiguration` from, without every call site needing to know
/// which `VersionedSchema` is current.
enum EquipmentLibrarySchema {
    static var models: [any PersistentModel.Type] { EquipmentLibrarySchemaV1.models }
}
