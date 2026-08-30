//
//  TelescopeConnectivityTester.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md. NAVI-63: a one-shot reachability check for a bare
//  INDI-MCP server endpoint, independent of TelescopeSessionManager's single live session — I-9's
//  "one choke point" rule is about actual hardware commands/session state, not this stateless
//  pre-flight check. ServerSettingsPane's per-row button is a real
//  TelescopeSessionManager.connect(server:)/disconnect(), not this — this stateless tester exists
//  for the one case a real connect can't handle: giving feedback on a newly saved/edited server
//  when some other server or rig is already occupying the single live session, without stealing
//  it.
//

import Foundation
import INDIMCPKit

enum TelescopeConnectivityTester {
    /// `nil` on success; a human-readable error description on failure. Opens its own throwaway
    /// `INDIMCPClient`, runs the MCP handshake, and disconnects immediately — it never touches
    /// `TelescopeSessionManager.shared`. Bounded to 10s (matching
    /// `TelescopeSessionManager`'s own heartbeat timeout) rather than trusting whatever default
    /// timeout the underlying HTTP transport uses — an unreachable host should read as "not
    /// reachable" within a few seconds, not however long a bare socket connect takes to fail.
    static func testConnection(to url: URL) async -> String? {
        let client = INDIMCPClient(endpoint: url)
        do {
            _ = try await TelescopeConnectCascade.withTimeout(seconds: 10) {
                try await client.connect()
            }
            await client.disconnect()
            return nil
        } catch {
            return TelescopeSessionManager.describe(error)
        }
    }
}
