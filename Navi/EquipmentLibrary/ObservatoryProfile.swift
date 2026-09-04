//
//  ObservatoryProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.1, §4.2.
//

import Foundation
import SwiftData

/// A local cache of server-side Observatories. Not a full local mirror — `Observatory` itself
/// lives entirely server-side (see `RigProfile.defaultObservatoryID`'s doc comment), and this
/// cache's fields are only ever refreshed opportunistically while connected, never authored
/// locally — but it holds enough to be useful offline:
/// - `name` alone populates the toolbar's Observatory picker (§4.1) before any connection has
///   ever been made; refreshed in bulk via `listObservatories()`, which only returns id/name.
/// - `latitudeDeg`/`longitudeDeg`/`elevationMeters` are refreshed only when a specific
///   observatory's full definition is fetched (`getObservatory(id:)`, e.g. opening it in the
///   Observatory Settings pane) — `listObservatories()` doesn't return them, so these can lag
///   `name` in how current they are. Cached so Dashboard-style offline math (LST, sunrise/sunset)
///   doesn't need a live round-trip just to read coordinates that rarely change.
/// - The horizon-obstruction profile is deliberately *not* cached here — it's only ever needed
///   while actively editing an observatory (already a connected, live-fetch context), so caching
///   it would just be unused bytes most of the time.
///
/// Picker rows in `TelescopeSelectionSheet` are only selectable while connected (§4.1), and the
/// Observatory Settings pane's editor is read/save-only while connected (§4.2) — so a stale or
/// incomplete cache when disconnected is expected, not a bug.
@Model
final class ObservatoryProfile {
    @Attribute(.unique) var serverObservatoryID: String
    var name: String
    var latitudeDeg: Double
    var longitudeDeg: Double
    var elevationMeters: Double
    var cachedAt: Date

    /// See `RigProfile.lastPushedDigest` (NAVI-86).
    var lastPushedDigest: String?

    /// When this record's *coordinates* were last fetched from the server, or `nil` if they never
    /// were. `listObservatories` returns summaries — a record seeded from it holds id and name only,
    /// with latitude/longitude/elevation left at 0 — so without this there's no way to tell a
    /// summary-only entry from an observatory genuinely at 0/0/0, and pushing the former would
    /// replace its real location with zeros.
    var detailsFetchedAt: Date?

    init(
        serverObservatoryID: String,
        name: String,
        latitudeDeg: Double = 0,
        longitudeDeg: Double = 0,
        elevationMeters: Double = 0,
        cachedAt: Date = .now,
        lastPushedDigest: String? = nil,
        detailsFetchedAt: Date? = nil
    ) {
        self.serverObservatoryID = serverObservatoryID
        self.name = name
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
        self.elevationMeters = elevationMeters
        self.cachedAt = cachedAt
        self.lastPushedDigest = lastPushedDigest
        self.detailsFetchedAt = detailsFetchedAt
    }
}
