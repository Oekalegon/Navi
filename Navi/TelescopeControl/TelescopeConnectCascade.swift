//
//  TelescopeConnectCascade.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.4.
//

import INDIMCPKit

/// The §4.4 connect cascade, factored out of `TelescopeSessionManager` as pure logic against the
/// `TelescopeClient` abstraction so it's testable without a live server.
enum TelescopeConnectCascade {
    /// Races `operation` against a `seconds`-long timeout, throwing
    /// `TelescopeSessionError.timedOut` if it loses. `INDIMCPClient` has no built-in request
    /// timeout (I-5), so every cascade step (and `TelescopeSessionManager`'s own heartbeat) wraps
    /// its call through this rather than risking the UI spinning forever on an unresponsive
    /// server. Nested here rather than a bare module-level function, so it doesn't sit in Navi's
    /// global namespace under a name generic enough to collide with something unrelated later.
    static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TelescopeSessionError.timedOut
            }
            guard let result = try await group.next() else {
                throw TelescopeSessionError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    /// Runs the cascade against `client`, returning the resolved `Rig` once every device-bound
    /// component has had `connectDevice` issued for it. Every step is idempotent (§4.4: never
    /// restart something already running) and timeout-wrapped (I-5).
    ///
    /// **Known gap:** §4.4 step 4 also says to "start that component's driver only if it isn't
    /// already running" before connecting it — deliberately not implemented here. INDIMCPKit's
    /// `Component` has no field mapping a resolved `device` name to a driver catalog `label`
    /// (`DriverInfo.label`), so there's no reliable way to know which driver a given component
    /// needs started. `connectDevice` is called directly per component instead; if its driver
    /// genuinely isn't running, the resulting `ScriptRunStarted` will surface as a failed run
    /// once script-run progress tracking is built (I-3), not as a silent no-op. Worth resolving
    /// alongside I-3 rather than guessing at a mapping here.
    static func run(
        client: some TelescopeClient,
        rigID: String,
        timeoutSeconds: Double = 15
    ) async throws -> Rig {
        try await Self.withTimeout(seconds: timeoutSeconds) { try await client.establishSession() }

        let serverStatus = try await Self.withTimeout(seconds: timeoutSeconds) {
            try await client.getINDIServerStatus()
        }
        if !serverStatus.running {
            _ = try await Self.withTimeout(seconds: timeoutSeconds) {
                try await client.startINDIServer(port: defaultINDIServerPort)
            }
        }

        let messagingStatus = try await Self.withTimeout(seconds: timeoutSeconds) {
            try await client.getINDIMessagingStatus()
        }
        if !messagingStatus.running {
            _ = try await Self.withTimeout(seconds: timeoutSeconds) {
                try await client.startINDIMessaging(host: "localhost", port: defaultINDIServerPort)
            }
        }

        let rig = try await Self.withTimeout(seconds: timeoutSeconds) { try await client.getRig(id: rigID) }

        for component in rig.components where component.device != nil {
            _ = try await Self.withTimeout(seconds: timeoutSeconds) {
                try await client.connectDevice(rigId: rig.id, role: component.role.rawValue)
            }
        }

        return rig
    }
}
