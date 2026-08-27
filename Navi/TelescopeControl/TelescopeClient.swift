//
//  TelescopeClient.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.4.
//

import INDIMCPKit

/// Abstraction over the subset of `INDIMCPClient` the connect/disconnect cascade
/// (`TelescopeConnectCascade`) needs, so that logic can be tested against a fake without a live
/// INDIMCP-server. `ObservableDevice` requires a *concrete* `INDIMCPClient` to construct (not a
/// protocol), so `TelescopeSessionManager` still holds the real type for that — this protocol
/// only covers the cascade/liveness calls that don't need it.
protocol TelescopeClient: Sendable {
    /// Wraps `INDIMCPClient.connect()`, discarding its `Initialize.Result` — the cascade never
    /// needs the handshake result, and this keeps the MCP SDK's `Initialize` type out of Navi's
    /// own protocol surface.
    func establishSession() async throws
    func disconnect() async

    func getINDIServerStatus() async throws -> IndiServerStatus
    func startINDIServer(port: Int) async throws -> IndiServerStatus
    func stopINDIServer() async throws -> IndiServerStatus

    func getINDIMessagingStatus() async throws -> MessagingStatus
    func startINDIMessaging(host: String, port: Int) async throws -> MessagingStatus

    func getRig(id: String) async throws -> Rig
    func connectDevice(rigId: String, role: String) async throws -> ScriptRunStarted
    func disconnectDevice(rigId: String, role: String) async throws -> ScriptRunStarted

    func connectionEvents(target: String?) -> AsyncThrowingStream<[ConnectionEvent], Error>
}

extension INDIMCPClient: TelescopeClient {
    func establishSession() async throws {
        try await connect()
    }
}
