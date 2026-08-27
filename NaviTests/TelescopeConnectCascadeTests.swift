//
//  TelescopeConnectCascadeTests.swift
//  NaviTests
//

import Testing
import INDIMCPKit
@testable import Navi

/// Fakes `TelescopeClient` so `TelescopeConnectCascade`'s decision logic (idempotent skips, per-
/// component device connection, error/timeout propagation) is testable without a live
/// INDIMCP-server. `ObservableDevice`/`TelescopeSessionManager`'s own orchestration isn't covered
/// here — `ObservableDevice` requires a concrete `INDIMCPClient` to construct, which this fake
/// isn't, so that part can only be exercised against a real server.
final class FakeTelescopeClient: TelescopeClient, @unchecked Sendable {
    private(set) var establishSessionCallCount = 0
    private(set) var startServerCallCount = 0
    private(set) var startMessagingCallCount = 0
    private(set) var connectedDeviceRoles: [String] = []

    var serverStatus = IndiServerStatus(running: false, port: defaultINDIServerPort)
    var messagingStatus = MessagingStatus(running: false, host: "localhost", port: defaultINDIServerPort)
    var rig: Rig
    var establishSessionError: Error?
    var getRigError: Error?
    /// If set, `establishSession()` hangs forever instead of returning — for exercising the
    /// timeout path.
    var hangOnEstablishSession = false

    init(rig: Rig) {
        self.rig = rig
    }

    func establishSession() async throws {
        establishSessionCallCount += 1
        if hangOnEstablishSession {
            try await Task.sleep(for: .seconds(3600))
        }
        if let establishSessionError { throw establishSessionError }
    }

    func disconnect() async {}

    func getINDIServerStatus() async throws -> IndiServerStatus { serverStatus }

    func startINDIServer(port: Int) async throws -> IndiServerStatus {
        startServerCallCount += 1
        serverStatus = IndiServerStatus(running: true, port: port)
        return serverStatus
    }

    func stopINDIServer() async throws -> IndiServerStatus {
        serverStatus = IndiServerStatus(running: false, port: serverStatus.port)
        return serverStatus
    }

    func getINDIMessagingStatus() async throws -> MessagingStatus { messagingStatus }

    func startINDIMessaging(host: String, port: Int) async throws -> MessagingStatus {
        startMessagingCallCount += 1
        messagingStatus = MessagingStatus(running: true, host: host, port: port)
        return messagingStatus
    }

    func getRig(id: String) async throws -> Rig {
        if let getRigError { throw getRigError }
        return rig
    }

    func connectDevice(rigId: String, role: String) async throws -> ScriptRunStarted {
        connectedDeviceRoles.append(role)
        return ScriptRunStarted(runId: "run-\(role)", script: "set_connection", rigId: rigId, startedAt: "now", pausable: false)
    }

    func disconnectDevice(rigId: String, role: String) async throws -> ScriptRunStarted {
        ScriptRunStarted(runId: "run-\(role)", script: "set_connection", rigId: rigId, startedAt: "now", pausable: false)
    }

    func connectionEvents(target: String?) -> AsyncThrowingStream<[ConnectionEvent], Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

struct TelescopeConnectCascadeTests {

    private func makeRig() -> Rig {
        Rig(
            id: "rig-1",
            name: "Test Rig",
            components: [
                Component(role: .mount, id: "mount-1", device: "EQMod Mount"),
                Component(role: .camera, id: "camera-1", device: "ZWO CCD ASI2600MM Pro"),
                // Blank component — no device bound yet. Must be skipped, not connected.
                Component(role: .filterWheel, id: "filterwheel-1", device: nil),
            ]
        )
    }

    @Test func cascadeStartsServerAndMessagingOnlyWhenNotAlreadyRunning() async throws {
        let client = FakeTelescopeClient(rig: makeRig())
        client.serverStatus = IndiServerStatus(running: false, port: defaultINDIServerPort)
        client.messagingStatus = MessagingStatus(running: false, host: "localhost", port: defaultINDIServerPort)

        _ = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1")

        #expect(client.establishSessionCallCount == 1)
        #expect(client.startServerCallCount == 1)
        #expect(client.startMessagingCallCount == 1)
    }

    @Test func cascadeSkipsStartingServerAndMessagingWhenAlreadyRunning() async throws {
        let client = FakeTelescopeClient(rig: makeRig())
        client.serverStatus = IndiServerStatus(running: true, port: defaultINDIServerPort)
        client.messagingStatus = MessagingStatus(running: true, host: "localhost", port: defaultINDIServerPort)

        _ = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1")

        #expect(client.startServerCallCount == 0)
        #expect(client.startMessagingCallCount == 0)
    }

    @Test func cascadeConnectsOnlyDeviceBoundComponentsSkippingBlankOnes() async throws {
        let client = FakeTelescopeClient(rig: makeRig())

        _ = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1")

        #expect(Set(client.connectedDeviceRoles) == ["mount", "camera"])
        #expect(!client.connectedDeviceRoles.contains("filterWheel"))
    }

    @Test func cascadeReturnsTheResolvedRig() async throws {
        let client = FakeTelescopeClient(rig: makeRig())

        let rig = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1")

        #expect(rig.id == "rig-1")
        #expect(rig.components.count == 3)
    }

    @Test func cascadePropagatesAnEstablishSessionFailure() async throws {
        let client = FakeTelescopeClient(rig: makeRig())
        client.establishSessionError = INDIMCPClientError.toolCallFailed(tool: "connect", message: "boom")

        await #expect(throws: INDIMCPClientError.self) {
            _ = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1")
        }

        // Should never have gotten past the failed handshake to touch the server/messaging/rig.
        #expect(client.startServerCallCount == 0)
    }

    @Test func cascadePropagatesAGetRigFailure() async throws {
        let client = FakeTelescopeClient(rig: makeRig())
        client.getRigError = INDIMCPClientError.toolCallFailed(tool: "get_rig", message: "not found")

        await #expect(throws: INDIMCPClientError.self) {
            _ = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1")
        }

        #expect(client.connectedDeviceRoles.isEmpty)
    }

    @Test func cascadeTimesOutAgainstAnUnresponsiveServer() async throws {
        let client = FakeTelescopeClient(rig: makeRig())
        client.hangOnEstablishSession = true

        await #expect(throws: TelescopeSessionError.self) {
            _ = try await TelescopeConnectCascade.run(client: client, rigID: "rig-1", timeoutSeconds: 0.05)
        }
    }
}
