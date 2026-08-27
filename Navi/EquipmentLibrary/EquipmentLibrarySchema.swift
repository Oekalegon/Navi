//
//  EquipmentLibrarySchema.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3.
//

import SwiftData

/// The equipment-library `@Model` types Navi's `ModelContainer` needs to know about — Navi's
/// first structured local data store (previously just `UserDefaults`/Keychain and security-scoped
/// bookmarks, per §4.3).
enum EquipmentLibrarySchema {
    static let models: [any PersistentModel.Type] = [
        MountProfile.self,
        OpticalAssemblyProfile.self,
        ImagingTrainProfile.self,
        GuideCameraProfile.self,
        ServerProfile.self,
        RigProfile.self,
    ]
}
