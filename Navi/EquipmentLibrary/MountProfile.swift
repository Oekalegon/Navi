//
//  MountProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// A reusable mount definition in Navi's local equipment library.
///
/// Named `MountProfile`, not `Mount`, to avoid colliding with INDIMCPKit's `Mount` device handle
/// — that type represents a *live, connected* mount session; this type is a *local, offline*
/// equipment record that a `RigProfile` points at. A mount is reusable on its own since the same
/// mount may carry different optical assemblies over time.
///
/// `deviceName` is resolved by picking from the live INDI device list while connected (§4.2 —
/// never free text); it is `nil` until then. Everything else can be authored fully offline.
@Model
final class MountProfile {
    var name: String
    var make: String?
    var model: String?
    var deviceName: String?
    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection —
    /// a `RigProfile` referencing this entity is stale once its `lastResyncedAt` predates this.
    var modifiedAt: Date

    init(
        name: String,
        make: String? = nil,
        model: String? = nil,
        deviceName: String? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.make = make
        self.model = model
        self.deviceName = deviceName
        self.notes = notes
        self.modifiedAt = modifiedAt
    }
}
