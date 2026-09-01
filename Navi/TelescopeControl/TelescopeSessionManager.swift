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

    /// The server a `connect(...)` call currently has in flight, non-nil only while `state ==
    /// .connecting`. Exists so multi-window UI (NAVI-63: `ServerSettingsPane`'s per-row Connect
    /// button) can show *which* row is connecting from every window, not just the one that
    /// initiated it — tracking that as view-local `@State` would leave every other window's copy
    /// of the same list unable to distinguish "connecting" from "unavailable, something else is
    /// live" until the connect resolves.
    private(set) var connectingServer: ServerProfile?

    /// Bumped on every successful `connect()` — even a reconnect to the identical rig/server —
    /// and reset to `nil` on disconnect/connection-loss. Exists purely so a SwiftUI `.task(id:)`
    /// call site (e.g. `ObservatoryDashboardView`'s device acquisition, §3.3) can detect "a fresh
    /// connected session started" and re-`acquireDevice`, which `currentRig?.id` alone can't do
    /// when reconnecting to the same rig (its id wouldn't change, so `.task(id:)` wouldn't
    /// restart).
    private(set) var connectionSessionID: Int?
    private var nextSessionID = 0

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
    private var deviceRefCounts: [Role: Int] = [:]
    private var messageStream: ObservableMessageStream?
    private var messageStreamRefCount = 0
    private var connectionEventsTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    // NAVI-52: capture progress + the frame-import reconciliation loop.
    /// The runId of the capture this rig session is currently watching, if any — cleared once its
    /// status turns terminal. Distinct from CaptureRunTracker's durable per-rig record: this is
    /// just "which one to show live progress for," not "which frames Navi still owes an import."
    private(set) var activeCaptureRunId: String?
    private(set) var activeCaptureStatus: ScriptRunStatus?
    private var captureEventsTask: Task<Void, Never>?
    private var reconcileTask: Task<Void, Never>?

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
        connectingServer = server

        let client = INDIMCPClient(endpoint: server.url)
        do {
            let rig = try await TelescopeConnectCascade.run(client: client, rigID: rigID)
            self.client = client
            self.currentRig = rig
            self.currentServer = server
            connectingServer = nil
            nextSessionID += 1
            connectionSessionID = nextSessionID
            state = .connected
            startLiveness(client: client)
            await resumeActiveCaptureIfNeeded(rig: rig, client: client)
            Task { await CaptureImportManager.shared.reconcile(rig: rig, client: client) }
        } catch {
            // The cascade may have already completed the MCP handshake before a later step
            // failed — disconnect the locally-constructed client so that session doesn't dangle;
            // nothing else holds a reference to it since `self.client` is only set on success.
            await client.disconnect()
            connectingServer = nil
            errorMessage = Self.describe(error)
            state = .disconnected
        }
    }

    /// Connects to `server` alone, with no Rig armed (NAVI-63) — just the MCP handshake, e.g. for
    /// testing/managing a server from Settings before any Rig references it. No-ops if already
    /// connecting/connected, matching `connect(server:rigID:)`'s contract — press Disconnect
    /// first. Unlike the rig-bound connect, there's no device cascade to run and no `currentRig`
    /// to set, so callers relying on `device(for:)`/`acquireDevice(for:)` will simply find no
    /// components bound (their guards already require `currentRig`).
    func connect(server: ServerProfile) async {
        guard state == .disconnected else { return }
        state = .connecting
        errorMessage = nil
        connectingServer = server

        let client = INDIMCPClient(endpoint: server.url)
        do {
            // 15s to match TelescopeConnectCascade.run's default timeoutSeconds, which wraps
            // this same handshake (via establishSession()) for the rig-bound path — an
            // unreachable host shouldn't hang on whatever default timeout the underlying
            // transport happens to use.
            _ = try await TelescopeConnectCascade.withTimeout(seconds: 15) { try await client.connect() }
            self.client = client
            self.currentServer = server
            connectingServer = nil
            nextSessionID += 1
            connectionSessionID = nextSessionID
            state = .connected
            startLiveness(client: client)
        } catch {
            await client.disconnect()
            connectingServer = nil
            errorMessage = Self.describe(error)
            state = .disconnected
        }
    }

    /// The deliberate, symmetric "shut it down" action (§4.4): stops every device this session
    /// started, then (if a Rig is armed) `indiserver` itself, then always closes the MCP session
    /// regardless. Distinct from Navi simply quitting or crashing, which touches nothing on the
    /// Pi.
    func disconnect() async {
        guard state != .disconnected else { return }
        stopLiveness()

        for device in devices.values { await device.stop() }
        devices.removeAll()
        deviceRefCounts.removeAll()
        if let messageStream { await messageStream.stop() }
        messageStream = nil
        messageStreamRefCount = 0
        connectionSessionID = nil

        if let client {
            if let rig = currentRig {
                for component in rig.components where component.device != nil {
                    _ = try? await client.disconnectDevice(rigId: rig.id, role: component.role.rawValue)
                }
                _ = try? await client.stopINDIServer()
            }
            // Always close the MCP session itself, even for a bare-server connect (no rig) that
            // has nothing device-level to tear down first.
            await client.disconnect()
        }

        self.client = nil
        currentRig = nil
        currentServer = nil
        state = .disconnected
    }

    /// Returns the shared `ObservableDevice` for `role`, if one is currently active — `nil` if
    /// not connected, the current rig has no device bound for that role, or nothing has
    /// `acquireDevice(for:)`'d it yet. Read-only: unlike the old single-method design, this does
    /// *not* start tracking on its own — call `acquireDevice(for:)` once per consumer lifecycle
    /// (e.g. a pane's `.task`) to start it, paired with `releaseDevice(for:)` when that consumer
    /// goes away.
    func device(for role: Role) -> ObservableDevice? {
        devices[role]
    }

    /// Starts (or joins) the shared `ObservableDevice` subscription for `role`, reference-counted
    /// so it's stopped only once every consumer has released it (§3.3: "closing a pane should
    /// call `ObservableDevice.stop()` (or have `TelescopeSessionManager` reference-count and stop
    /// only when the last consumer goes away)"). `nil` if not connected or the current rig has no
    /// device bound for that role — matches `device(for:)`'s existing guard. I-8: one instance per
    /// role, shared across every pane/window that acquires it, rather than each constructing its
    /// own.
    @discardableResult
    func acquireDevice(for role: Role) -> ObservableDevice? {
        guard let client, let rig = currentRig, state == .connected else { return nil }
        guard rig.components.contains(where: { $0.role == role && $0.device != nil }) else { return nil }
        deviceRefCounts[role, default: 0] += 1
        if let existing = devices[role] { return existing }
        let observable = ObservableDevice(client: client, rigId: rig.id, role: role)
        devices[role] = observable
        Task { await observable.start() }
        return observable
    }

    /// Releases one consumer's interest in `role`'s device, stopping and removing it once the
    /// last consumer has released. A no-op if `role` was never acquired (or a full disconnect/
    /// connection-loss already cleared every device out from under it) — safe to call
    /// unconditionally from a consumer's teardown path regardless of how it got there.
    func releaseDevice(for role: Role) {
        guard let count = deviceRefCounts[role] else { return }
        if count <= 1 {
            deviceRefCounts[role] = nil
            if let device = devices.removeValue(forKey: role) {
                Task { await device.stop() }
            }
        } else {
            deviceRefCounts[role] = count - 1
        }
    }

    // MARK: - Camera commands (NAVI-52) — the single choke point for camera hardware commands
    // (I-9): CameraPanelView never holds a `Camera`/`FilterWheel` handle directly, only calls
    // through here, so two panes/windows can't independently fire conflicting commands. Reading
    // standing/live state (temperature, cooler, gain) instead goes through the shared
    // `ObservableDevice` from `acquireDevice(for: .camera)`, matching every other pane's convention
    // — only commands that change hardware state route through this section.

    /// Captures one frame and starts tracking its progress (`activeCaptureRunId`/
    /// `activeCaptureStatus`) — the same runId is recorded in `CaptureRunTracker` immediately, so
    /// it survives even if Navi disconnects or quits before the exposure finishes.
    @discardableResult
    func captureFrame(
        exposureSeconds: Double, frameType: FrameType, binningX: Int, binningY: Int,
        gain: Double?, offset: Double?
    ) async throws -> ScriptRunStarted {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        let started = try await client.camera(rigId: rig.id).captureFrame(
            exposureSeconds: exposureSeconds, frameType: frameType,
            binningX: binningX, binningY: binningY, gain: gain, offset: offset)
        CaptureRunTracker.recordRunStarted(rigId: rig.id, runId: started.runId)
        activeCaptureRunId = started.runId
        activeCaptureStatus = .started(started)
        subscribeToActiveCapture(runId: started.runId, client: client)
        return started
    }

    /// Aborts the camera's currently in-progress exposure — an explicit, separate user action
    /// only (I-3), never implied by this pane closing or Navi quitting.
    func abortExposure() async throws {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        _ = try await client.camera(rigId: rig.id).abortExposure()
    }

    func coolCamera(targetTempC: Double) async throws {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        _ = try await client.camera(rigId: rig.id).coolCamera(targetTempC: targetTempC)
    }

    func coolerOn() async throws {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        _ = try await client.camera(rigId: rig.id).coolerOn()
    }

    func coolerOff() async throws {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        _ = try await client.camera(rigId: rig.id).coolerOff()
    }

    func setTargetTempC(_ targetTempC: Double) async throws {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        try await client.camera(rigId: rig.id).setTargetTempC(targetTempC)
    }

    /// The rig's configured filter-wheel slot names (`Component.slots`) — not a live driver read,
    /// matching `FilterWheel.filterNames()`'s own contract.
    func filterNames() async throws -> [Int: String] {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        return try await client.filterWheel(rigId: rig.id).filterNames()
    }

    func selectFilter(_ filterName: String) async throws {
        guard let client, let rig = currentRig else { throw TelescopeSessionError.notConnected }
        _ = try await client.filterWheel(rigId: rig.id).selectFilter(filterName)
    }

    /// Starts (or joins) the shared, unscoped `ObservableMessageStream`, reference-counted the same
    /// way `acquireDevice(for:)` is (§3.3/§4.7). Unscoped (not `messageEvents(device:)`'s single-
    /// device filter) because the pane needs messages from every device in the current rig, and
    /// the underlying stream can only ever scope to one device at a time — callers filter
    /// `events`/history down to the rig's device names themselves (`TelescopeMessageFilter`).
    /// Doesn't key by role like `devices`/`deviceRefCounts` — a message stream isn't per-role, so
    /// this is a single optional field with its own ref count instead.
    @discardableResult
    func acquireMessageStream() -> ObservableMessageStream? {
        guard let client, state == .connected else { return nil }
        messageStreamRefCount += 1
        if let existing = messageStream { return existing }
        let observable = ObservableMessageStream(client: client)
        messageStream = observable
        Task { await observable.start() }
        return observable
    }

    /// Releases one consumer's interest in the shared message stream, stopping and removing it
    /// once the last consumer has released — mirrors `releaseDevice(for:)`.
    func releaseMessageStream() {
        guard messageStreamRefCount > 0 else { return }
        if messageStreamRefCount <= 1 {
            messageStreamRefCount = 0
            if let stream = messageStream {
                messageStream = nil
                Task { await stream.stop() }
            }
        } else {
            messageStreamRefCount -= 1
        }
    }

    /// The durable message-event log (§4.7's "also loads history... on open, rather than starting
    /// from a blank slate"), unscoped for the same reason `acquireMessageStream()` is — callers
    /// filter to the rig's device names themselves.
    func getMessageHistory(since: String? = nil) async throws -> [EventRecord] {
        guard let client else { throw TelescopeSessionError.notConnected }
        return try await client.getEvents(stream: .messages, since: since)
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
        // NAVI-52: catches up on frames that finished while Navi wasn't watching (or wasn't even
        // running) — the live scriptEvents subscription alone isn't resilient to disconnects, so
        // this periodic sweep is the durable backstop, on top of the one-shot pass connect()
        // already triggers. 60s, not tied to the 30s heartbeat's tighter connection-liveness need.
        reconcileTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, let rig = self.currentRig else { return }
                await CaptureImportManager.shared.reconcile(rig: rig, client: client)
            }
        }
    }

    private func stopLiveness() {
        connectionEventsTask?.cancel()
        heartbeatTask?.cancel()
        reconcileTask?.cancel()
        captureEventsTask?.cancel()
        connectionEventsTask = nil
        heartbeatTask = nil
        reconcileTask = nil
        captureEventsTask = nil
        activeCaptureRunId = nil
        activeCaptureStatus = nil
    }

    /// On connect, resumes live progress tracking for whichever of this rig's tracked runs (§NAVI-
    /// 52's CaptureRunTracker) is still non-terminal — an in-progress exposure keeps running on
    /// the Pi regardless of what Navi's UI does, so the panel should come up already showing
    /// progress/abort rather than a stale idle state (I-3), not just after Navi itself started it.
    private func resumeActiveCaptureIfNeeded(rig: Rig, client: INDIMCPClient) async {
        for runId in CaptureRunTracker.runIDs(forRig: rig.id) {
            guard let status = try? await client.getScriptStatus(runId: runId), !status.isTerminal else { continue }
            activeCaptureRunId = runId
            activeCaptureStatus = status
            subscribeToActiveCapture(runId: runId, client: client)
            return
        }
    }

    /// Live progress for the UI only — not relied on for correctness. `scriptEvents` isn't
    /// resilient to disconnects (I-3); the durable catch-up is `reconcile()`'s periodic sweep and
    /// `resumeActiveCaptureIfNeeded`'s status poll on the next connect, not this stream.
    private func subscribeToActiveCapture(runId: String, client: INDIMCPClient) {
        captureEventsTask?.cancel()
        captureEventsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await window in client.scriptEvents(runId: runId) {
                    guard let latest = window.first else { continue }
                    await self.applyCaptureStatus(latest, runId: runId)
                }
            } catch {
                // Best-effort live signal only — see this method's own doc comment.
            }
        }
    }

    private func applyCaptureStatus(_ status: ScriptRunStatus, runId: String) {
        guard activeCaptureRunId == runId else { return }
        activeCaptureStatus = status
        if status.isTerminal {
            activeCaptureRunId = nil
        }
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
        deviceRefCounts.removeAll()
        if let messageStream { await messageStream.stop() }
        messageStream = nil
        messageStreamRefCount = 0
        connectionSessionID = nil
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
