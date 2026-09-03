//
//  ServerDiscoveryModelTests.swift
//  NaviTests
//

import Testing
import Foundation
import INDIMCPKit
@testable import Navi

struct ServerDiscoveryModelTests {
    private func server(host: String, port: Int? = 8000) -> ServerProfile {
        let string = port.map { "http://\(host):\($0)/mcp" } ?? "http://\(host)/mcp"
        return ServerProfile(name: "Test Server", url: URL(string: string)!)
    }

    private func discovered(host: String, port: Int = 8000) -> DiscoveredServer {
        DiscoveredServer(name: "raspberrypi", host: host, port: port)
    }

    @Test func matchesOnHostAndPortCaseInsensitively() {
        let server = server(host: "RaspberryPi.local")
        let discovered = discovered(host: "raspberrypi.local")
        #expect(ServerDiscoveryModel.isMatch(server, discovered))
    }

    @Test func doesNotMatchOnPortMismatch() {
        let server = server(host: "raspberrypi.local", port: 8000)
        let discovered = discovered(host: "raspberrypi.local", port: 8001)
        #expect(!ServerDiscoveryModel.isMatch(server, discovered))
    }

    @Test func doesNotMatchOnHostMismatch() {
        let server = server(host: "raspberrypi.local")
        let discovered = discovered(host: "192.168.1.5")
        #expect(!ServerDiscoveryModel.isMatch(server, discovered))
    }

    @Test func doesNotMatchWhenServerURLHasNoExplicitPort() {
        let server = server(host: "raspberrypi.local", port: nil)
        let discovered = discovered(host: "raspberrypi.local", port: 80)
        #expect(!ServerDiscoveryModel.isMatch(server, discovered))
    }

    @Test func isDiscoveredTrueWhenAnyEntryMatches() {
        let server = server(host: "raspberrypi.local")
        let entries = [discovered(host: "some-other-host"), discovered(host: "raspberrypi.local")]
        #expect(ServerDiscoveryModel.isDiscovered(server, among: entries))
    }

    @Test func isDiscoveredFalseWhenNoEntryMatches() {
        let server = server(host: "raspberrypi.local")
        let entries = [discovered(host: "some-other-host")]
        #expect(!ServerDiscoveryModel.isDiscovered(server, among: entries))
    }

    @Test func unconfiguredServersExcludesEntriesMatchingAConfiguredServer() {
        let configured = [server(host: "raspberrypi.local")]
        let entries = [discovered(host: "raspberrypi.local"), discovered(host: "unconfigured-host")]

        let unconfigured = ServerDiscoveryModel.unconfiguredServers(among: configured, discovered: entries)

        #expect(unconfigured.count == 1)
        #expect(unconfigured.first?.host == "unconfigured-host")
    }

    @Test func unconfiguredServersReturnsAllEntriesWhenNoneAreConfigured() {
        let entries = [discovered(host: "a"), discovered(host: "b")]
        let unconfigured = ServerDiscoveryModel.unconfiguredServers(among: [], discovered: entries)
        #expect(unconfigured.count == 2)
    }
}
