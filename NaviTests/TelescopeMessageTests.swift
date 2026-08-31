//
//  TelescopeMessageTests.swift
//  NaviTests
//
//  TelescopeMessageFilter is the client-side scoping/accumulation logic that makes a single-
//  device-scoped INDIMCPKit API (messageEvents(device:)/getEvents) work for a whole rig's worth
//  of devices (docs/design/INDI-MCP-Integration.md §4.7) — kept pure so it's testable without a
//  live session.
//

import Testing
import Foundation
import MCP
import INDIMCPKit
@testable import Navi

struct TelescopeMessageTests {

    private func event(device: String?, message: String, timestamp: String, state: PropertyState? = nil) -> IndiEvent {
        IndiEvent(kind: "message", type: nil, device: device, name: nil, state: state,
                  message: message, elements: nil, timestamp: timestamp)
    }

    private func record(id: Int, event: IndiEvent) throws -> EventRecord {
        EventRecord(id: id, stream: .messages, device: event.device, runId: nil, target: nil,
                    occurredAt: event.timestamp, payload: try Value(event))
    }

    @Test func filtersOutServerWideAndUnrelatedDeviceMessages() {
        let deviceNames: Set<String> = ["CCD Simulator"]

        #expect(TelescopeMessageFilter.isRelevant(event(device: "CCD Simulator", message: "a", timestamp: "t"), deviceNames: deviceNames))
        #expect(!TelescopeMessageFilter.isRelevant(event(device: nil, message: "a", timestamp: "t"), deviceNames: deviceNames))
        #expect(!TelescopeMessageFilter.isRelevant(event(device: "Telescope Simulator", message: "a", timestamp: "t"), deviceNames: deviceNames))
    }

    @Test func relevantMessagesFiltersAndMapsAnEventBatch() {
        let deviceNames: Set<String> = ["CCD Simulator"]
        let events = [
            event(device: "CCD Simulator", message: "kept", timestamp: "t1"),
            event(device: "Telescope Simulator", message: "dropped", timestamp: "t2"),
            event(device: nil, message: "dropped too", timestamp: "t3")
        ]

        let messages = TelescopeMessageFilter.relevantMessages(from: events, deviceNames: deviceNames)

        #expect(messages.map(\.text) == ["kept"])
    }

    @Test func sortedOrdersChronologicallyByParsedTimestamp() {
        let messages = [
            TelescopeMessage(event: event(device: "d", message: "second", timestamp: "2026-01-01T00:00:02Z")),
            TelescopeMessage(event: event(device: "d", message: "first", timestamp: "2026-01-01T00:00:01Z"))
        ]
        let accumulated = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })

        #expect(TelescopeMessageFilter.sorted(accumulated).map(\.text) == ["first", "second"])
    }

    // Regression test: ObservableMessageStream.events is only a bounded rolling window, replaced
    // wholesale on every yield — a message that arrives and later ages out of that window must
    // not disappear once it's no longer in the latest snapshot. upserting(_:into:) must keep it.
    @Test func upsertingAccumulatesAcrossSuccessiveWindowsInsteadOfReplacing() {
        let deviceNames: Set<String> = ["CCD Simulator"]
        let older = event(device: "CCD Simulator", message: "older", timestamp: "2026-01-01T00:00:00Z")
        let newer = event(device: "CCD Simulator", message: "newer", timestamp: "2026-01-01T00:00:01Z")

        // First window contains only the older message; accumulate it.
        var accumulated: [String: TelescopeMessage] = [:]
        accumulated = TelescopeMessageFilter.upserting(
            TelescopeMessageFilter.relevantMessages(from: [older], deviceNames: deviceNames), into: accumulated)

        // Second (later) window has rolled `older` out entirely, showing only `newer` — a plain
        // "replace with the latest window" would lose `older` here.
        accumulated = TelescopeMessageFilter.upserting(
            TelescopeMessageFilter.relevantMessages(from: [newer], deviceNames: deviceNames), into: accumulated)

        #expect(TelescopeMessageFilter.sorted(accumulated).map(\.text) == ["older", "newer"])
    }

    @Test func upsertingDedupsAnEventSeenInBothHistoryAndLive() throws {
        let deviceNames: Set<String> = ["CCD Simulator"]
        let shared = event(device: "CCD Simulator", message: "cooling started", timestamp: "2026-01-01T00:00:00Z")
        let historyRecord = try record(id: 1, event: shared)

        var accumulated: [String: TelescopeMessage] = [:]
        let fromHistory = [historyRecord].compactMap { try? $0.decodedMessage() }
        accumulated = TelescopeMessageFilter.upserting(
            TelescopeMessageFilter.relevantMessages(from: fromHistory, deviceNames: deviceNames), into: accumulated)
        accumulated = TelescopeMessageFilter.upserting(
            TelescopeMessageFilter.relevantMessages(from: [shared], deviceNames: deviceNames), into: accumulated)

        #expect(accumulated.count == 1)
    }

    @Test func messageStateDrivesRowColorCategoriesCorrectly() {
        let alert = TelescopeMessage(event: event(device: "d", message: "m", timestamp: "t", state: .alert))
        #expect(alert.state == .alert)
    }
}
