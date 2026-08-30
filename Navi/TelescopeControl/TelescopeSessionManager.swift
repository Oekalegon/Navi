//
//  TelescopeSessionManager.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §3.2, §4.4, §4.5.
//

import Foundation
import INDIMCPKit

/// Disambiguating alias for call sites (e.g. `ObservatoryDashboardView`) that need both this
/// package's `Observatory` and AstroKit's — each package also shadows its own module name with
/// an empty enum of the same name, which defeats a bare `INDIMCPKit.Observatory`/
/// `AstroKit.Observatory` qualification once both modules are imported in one file. Declared
/// here, in a file that only imports `INDIMCPKit`, where plain `Observatory` is unambiguous.
typealias INDIObservatory = Observatory

/// Owns Navi's single live INDI-MCP session — the connect/disconnect cascade (§4.4), liveness
/// detection (§3.2), and one shared `ObservableDevice` per role (§4.5/I-8) so every pane/window
/// observes the same live state instead of each spinning up its own subscription. Also the single
/// choke point for hardware commands (I-9): a device command should go through this manager's
/// `device(for:)`, never construct its own `ObservableDevice` or hold an `INDIMCPClient` directly.
///
/// Owned once, the same way `ArchiveManager`/`SettingsManager` are — created a single time and
/// referenced by panes, not one instance per pane/window.
///
/// **Testing note:** the connect-cascade *decision logic* (idempotent skips, per-component device
/// connection, error/timeout propagation) is covered by `TelescopeConnectCascadeTests` against a
/// fake `TelescopeClient`. This class's own orchestration on top of that — state transitions,
/// `handleConnectionLost`'s idempotency guard, `device(for:)`'s guard logic — is *not*
/// independently unit-tested: `connect(server:rigID:)` constructs a concrete `INDIMCPClient`
/// directly (required for `ObservableDevice`, which only accepts that concrete type, not a
/// protocol), so this layer can only be exercised against a real or fake INDIMCP-server, not a
/// substitutable client. A deliberate, documented gap, not an oversight.
@MainActor
@Observable
final class TelescopeSessionManager {
    static let shared = TelescopeSessionManager()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var state: ConnectionState = .disconnected
    /// I-4's existing convention: one place errors surface, read directly by views — no toasts
    /// or `.alert()` sheets.
    var errorMessage: String?

    private(set) var currentServer: ServerProfile?
    private(set) var currentRig: Rig?

    /// The user's *armed* Rig/Observatory choice (§4.1/§4.3.2) — set by confirming the toolbar's
    /// selection modal, independent of whether a connection is currently live. Persisted across
    /// launches via `UserDefaults`, matching `SettingsManager`'s own plain-`didSet` persistence
    /// idiom. `armedRigID` is a `RigProfile.serverRigID`; `armedObservatoryID` is a server-side
    /// `Observatory.id` (see `ObservatoryProfile`/`RigProfile.defaultObservatoryID`).
    var armedRigID: String? {
        didSet { UserDefaults.standard.set(armedRigID, forKey: Self.armedRigIDDefaultsKey) }
    }
    var armedObservatoryID: String? {
        didSet { UserDefaults.standard.set(armedObservatoryID, forKey: Self.armedObservatoryIDDefaultsKey) }
    }
    private static let armedRigIDDefaultsKey = "telescopeArmedRigID"
    private static let armedObservatoryIDDefaultsKey = "telescopeArmedObservatoryID"

    private var client: INDIMCPClient?
    private var devices: [Role: ObservableDevice] = [:]
    private var connectionEventsTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init() {
        armedRigID = UserDefaults.standard.string(forKey: Self.armedRigIDDefaultsKey)
        armedObservatoryID = UserDefaults.standard.string(forKey: Self.armedObservatoryIDDefaultsKey)
    }

    /// Connects to `server` and brings up `rigID`'s devices via the §4.4 cascade. No-ops if
    /// already connecting/connected — press Disconnect first to switch rigs/servers (§4.1: rig/
    /// server selection only ever *arms* a choice, Connect is always a separate, explicit action).
    func connect(server: ServerProfile, rigID: String) async {
        guard state == .disconnected else { return }
        state = .connecting
        errorMessage = nil

        let client = INDIMCPClient(endpoint: server.url)
        do {
            let rig = try await TelescopeConnectCascade.run(client: client, rigID: rigID)
            self.client = client
            self.currentRig = rig
            self.currentServer = server
            state = .connected
            startLiveness(client: client)
        } catch {
            // The cascade may have already completed the MCP handshake before a later step
            // failed — disconnect the locally-constructed client so that session doesn't dangle;
            // nothing else holds a reference to it since `self.client` is only set on success.
            await client.disconnect()
            errorMessage = Self.describe(error)
            state = .disconnected
        }
    }

    /// The deliberate, symmetric "shut it down" action (§4.4): stops every device this session
    /// started, then `indiserver` itself, then closes the MCP session. Distinct from Navi simply
    /// quitting or crashing, which touches nothing on the Pi.
    func disconnect() async {
        guard state != .disconnected else { return }
        stopLiveness()

        for device in devices.values { await device.stop() }
        devices.removeAll()

        if let client, let rig = currentRig {
            for component in rig.components where component.device != nil {
                _ = try? await client.disconnectDevice(rigId: rig.id, role: component.role.rawValue)
            }
            _ = try? await client.stopINDIServer()
            await client.disconnect()
        }

        self.client = nil
        currentRig = nil
        currentServer = nil
        state = .disconnected
    }

    /// Returns the shared `ObservableDevice` for `role` in the currently-connected rig, creating
    /// and starting it on first access. `nil` if not connected, or if the current rig has no
    /// device bound for that role. I-8: one instance per role, shared across every pane/window
    /// that asks for it, rather than each constructing its own.
    func device(for role: Role) -> ObservableDevice? {
        guard let client, let rig = currentRig, state == .connected else { return nil }
        guard rig.components.contains(where: { $0.role == role && $0.device != nil }) else { return nil }
        if let existing = devices[role] { return existing }
        let observable = ObservableDevice(client: client, rigId: rig.id, role: role)
        devices[role] = observable
        Task { await observable.start() }
        return observable
    }

    /// Live Observatory list from the currently-connected server, for refreshing the toolbar's
    /// local `ObservatoryProfile` cache (§4.1) — throws `TelescopeSessionError.notConnected` when
    /// there's no live session, since Observatory has no server of its own to ask before one
    /// exists. Callers should treat that as "nothing to refresh right now," not a hard failure.
    func listObservatories() async throws -> [ObservatorySummary] {
        guard let client else { throw TelescopeSessionError.notConnected }
        return try await client.listObservatories()
    }

    /// The full definition of one observatory (§4.2's editor needs this — `listObservatories()`
    /// only returns id/name, not coordinates/horizon profile).
    func getObservatory(id: String) async throws -> Observatory {
        guard let client else { throw TelescopeSessionError.notConnected }
        return try await client.getObservatory(id: id)
    }

    /// Saves an observatory definition (§4.2). `overwrite` matches `INDIMCPClient.saveObservatory`
    /// — required to replace an existing one, so a reused id can't silently destroy a prior save.
    @discardableResult
    func saveObservatory(_ observatory: Observatory, overwrite: Bool = false) async throws -> Observatory {
        guard let client else { throw TelescopeSessionError.notConnected }
        return try await client.saveObservatory(observatory, overwrite: overwrite)
    }

    /// Saves a rig definition (§4.2's Rig pane, built by `RigProfile.makeComponents()`).
    /// `overwrite` matches `INDIMCPClient.saveRig` — required to replace an existing one, so a
    /// reused id can't silently destroy a prior save.
    @discardableResult
    func saveRig(_ rig: Rig, overwrite: Bool = false) async throws -> Rig {
        guard let client else { throw TelescopeSessionError.notConnected }
        return try await client.saveRig(rig, overwrite: overwrite)
    }

    /// The best available approximation of "the live device list" for the Rig editor's
    /// device-picker fields (§4.2: every device-bearing field is selection-only from this list,
    /// never free text). INDIMCPKit/INDIMCP-server have no dedicated "list live INDI device
    /// names" call today — only `listRunningINDIDrivers()`, which reports running *drivers* by
    /// their catalog label (e.g. `"CCD Simulator"`), not the INDI device name(s) that driver
    /// exposes. In practice a driver's default device name commonly matches its catalog label,
    /// so labels of currently-running drivers are used as the candidate device names here — but
    /// this is a known approximation, not a guarantee, since a driver is free to expose a
    /// differently-named (or multiple) INDI device(s). TODO: replace with a real device-name
    /// listing once INDIMCP-server exposes one; filed for follow-up alongside INDIMCP-138/139.
    func liveDeviceNames() async throws -> [String] {
        guard let client else { throw TelescopeSessionError.notConnected }
        let running = try await client.listRunningINDIDrivers()
        return running.filter(\.running).map(\.label).sorted()
    }

    private func startLiveness(client: INDIMCPClient) {
        connectionEventsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await events in client.connectionEvents(target: nil) {
                    await self.handle(events)
                }
            } catch {
                await self.handleConnectionLost(Self.describe(error))
            }
        }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                do {
                    _ = try await TelescopeConnectCascade.withTimeout(seconds: 10) {
                        try await client.getINDIServerStatus()
                    }
                } catch {
                    await self.handleConnectionLost("Heartbeat failed: \(Self.describe(error))")
                    return
                }
            }
        }
    }

    private func stopLiveness() {
        connectionEventsTask?.cancel()
        heartbeatTask?.cancel()
        connectionEventsTask = nil
        heartbeatTask = nil
    }

    private func handle(_ events: [ConnectionEvent]) async {
        for event in events where event.kind == .connectionLost {
            // "server" here is INDIMCP-server's own link to indiserver (not Navi's MCP session to
            // INDIMCP-server, which has no dedicated event — see ConnectionEvent's doc comment
            // and I-4). Both "server" and "indiserver" losing their connection mean nothing
            // device-related can work; a single driver's label losing connection is narrower and
            // is ObservableDevice's own concern via its messageEvents subscription, not a reason
            // to tear down the whole session.
            guard event.target == "server" || event.target == "indiserver" else { continue }
            await handleConnectionLost(event.message ?? "The INDI-MCP server lost its connection to indiserver.")
        }
    }

    /// Only tears down `.connected` state — a lost-connection signal arriving after an explicit
    /// `disconnect()` (or a duplicate signal) is a no-op, not a re-entrant teardown. `async`,
    /// awaiting each device's `stop()` in turn, matching `disconnect()`'s own teardown — both of
    /// this method's call sites already `await` it, so there's no reason for a fire-and-forget
    /// `Task { await device.stop() }` here instead.
    private func handleConnectionLost(_ message: String) async {
        guard state == .connected else { return }
        errorMessage = message
        stopLiveness()
        for device in devices.values { await device.stop() }
        devices.removeAll()
        client = nil
        currentRig = nil
        currentServer = nil
        state = .disconnected
    }

    /// I-4: `INDIMCPClientError`/`DeviceControlError`/`TelescopeSessionError` all funnel into one
    /// string here. A lost MCP connection has no dedicated error case of its own — it surfaces as
    /// whatever the underlying transport throws, hence the generic fallback.
    ///
    /// Not `private` — other telescope-control views (e.g. `TelescopeSelectionSheet`) surfacing
    /// their own errors into `errorMessage` should format them the same way, rather than falling
    /// back to `error.localizedDescription`, which doesn't use these types' `CustomStringConvertible`
    /// descriptions (they don't conform to `LocalizedError`).
    nonisolated static func describe(_ error: Error) -> String {
        if let error = error as? TelescopeSessionError { return error.description }
        if let error = error as? INDIMCPClientError { return error.description }
        if let error = error as? DeviceControlError { return error.description }
        return error.localizedDescription
    }
}
