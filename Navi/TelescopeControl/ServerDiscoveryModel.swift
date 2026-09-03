//
//  ServerDiscoveryModel.swift
//  Navi
//
//  NAVI-68: app-wide Bonjour/mDNS discovery of INDI-MCP servers, wrapping INDIMCPKit's
//  `ServerDiscovery`. A single shared instance, matching `TelescopeSessionManager.shared` — both
//  `ServerSettingsPane` and the toolbar's server menu can be on screen at once, so browsing is
//  refcounted via `beginObserving()`/`endObserving()` rather than each view owning its own
//  `NWBrowser`.
//

import Foundation
import INDIMCPKit
import Observation

@MainActor
@Observable
final class ServerDiscoveryModel {
    static let shared = ServerDiscoveryModel()

    private let discovery = ServerDiscovery()
    private var observerCount = 0

    var discoveredServers: [DiscoveredServer] { discovery.discoveredServers }

    private init() {}

    func beginObserving() {
        observerCount += 1
        if observerCount == 1 { discovery.start() }
    }

    func endObserving() {
        observerCount = max(0, observerCount - 1)
        if observerCount == 0 { discovery.stop() }
    }

    /// Whether `server` matches one of the currently-discovered Bonjour instances by host/port —
    /// the basis for the "Online"/"Offline" status text next to each configured server. This is
    /// presence-on-the-Bonjour-browse, not a live reachability probe: a server that's up but not
    /// advertising (an older INDIMCP-server build) or outside mDNS's local-network reach will read
    /// as "Offline" even if it would actually respond to a connect.
    ///
    /// Host comparison is case-insensitive: `DiscoveredServer.host` is always a resolved literal
    /// address, but `ServerProfile.url.host` may have been typed by hand (e.g. a `.local`
    /// hostname), so this only reliably matches servers whose `url` was itself filled in from a
    /// discovery — `ServerSettingsPane.addDiscovered(_:)` and `TelescopeToolbarButton.
    /// connectToDiscovered(_:)` both do this — rather than typed manually.
    func isDiscovered(_ server: ServerProfile) -> Bool {
        Self.isDiscovered(server, among: discoveredServers)
    }

    /// Discovered servers with no matching configured `ServerProfile` — the "Discovered" section
    /// shown below configured servers in both `ServerSettingsPane` and the toolbar's server menu.
    func unconfiguredServers(among servers: [ServerProfile]) -> [DiscoveredServer] {
        Self.unconfiguredServers(among: servers, discovered: discoveredServers)
    }

    // The `static` variants below take `discovered`/`servers` explicitly rather than reading
    // `self.discoveredServers` — pure functions, directly unit-testable without a real `NWBrowser`
    // (which the instance methods above would otherwise require standing up).

    nonisolated static func isDiscovered(_ server: ServerProfile, among discovered: [DiscoveredServer]) -> Bool {
        discovered.contains { isMatch(server, $0) }
    }

    nonisolated static func unconfiguredServers(among servers: [ServerProfile], discovered: [DiscoveredServer]) -> [DiscoveredServer] {
        discovered.filter { entry in
            !servers.contains { isMatch($0, entry) }
        }
    }

    /// `false` whenever `server.url` has no explicit port — a discovered server's port is always
    /// the real listening port, so there's no sensible implicit default to compare it against.
    nonisolated static func isMatch(_ server: ServerProfile, _ discovered: DiscoveredServer) -> Bool {
        guard let port = server.url.port else { return false }
        return server.url.host?.lowercased() == discovered.host.lowercased() && port == discovered.port
    }
}
