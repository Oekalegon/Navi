//
//  TelescopeMessage.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.7. INDIMCPKit's messageEvents(device:)/getEvents
//  APIs only ever scope to a single device name, but the pane needs every device in the current
//  rig — TelescopeMessageFilter is the client-side scoping/dedup that makes that work, kept pure
//  and separate from TelescopeMessagesView so it's unit-testable without a live session.
//
//  Accumulate, don't re-derive: ObservableMessageStream.events is only a bounded rolling window,
//  replaced wholesale on every yield, not appended to — a message that arrives and then ages out
//  of that window must not disappear from the pane just because it's no longer in the latest
//  snapshot. TelescopeMessagesView folds each new window into a persistent accumulator via
//  `upserting(_:into:)` instead of recomputing the visible list from history ∪ current-window on
//  every render, which would silently drop exactly that class of message during a long session.
//

import Foundation
import INDIMCPKit

/// One row in the messages pane — the merged, display-ready shape of an `IndiEvent`, regardless of
/// whether it arrived via the live `ObservableMessageStream` or the durable `getEvents` history.
struct TelescopeMessage: Identifiable, Hashable {
    let id: String
    let device: String?
    let text: String?
    let state: PropertyState?
    let timestamp: String

    init(event: IndiEvent) {
        device = event.device
        text = event.message
        state = event.state
        timestamp = event.timestamp
        // Content-based, not EventRecord.id: the live stream (IndiEvent) has no durable id of its
        // own, and the same underlying INDI message decoded from history vs. received live has
        // identical timestamp/device/message — that's exactly the identity merge/dedup needs.
        id = "\(timestamp)|\(device ?? "")|\(text ?? "")"
    }

    // Parsed once for sorting; falls back to .distantPast (sorts first) rather than throwing or
    // crashing on a timestamp INDIMCPKit's ISO8601 formatter can't parse.
    var sortDate: Date {
        Self.formatter.date(from: timestamp) ?? .distantPast
    }

    private static let formatter = ISO8601DateFormatter()
}

enum TelescopeMessageFilter {
    /// Whether `event` belongs to one of the current rig's devices — server-wide messages
    /// (`device == nil`) and messages from unrelated equipment are both excluded, per §4.7 ("not
    /// the whole server — unrelated equipment's messages are just noise").
    static func isRelevant(_ event: IndiEvent, deviceNames: Set<String>) -> Bool {
        guard let device = event.device else { return false }
        return deviceNames.contains(device)
    }

    /// Filters `events` down to the rig's devices and maps them to display-ready messages —
    /// applied identically to a batch decoded from `getEvents` history and to a live window from
    /// `ObservableMessageStream.events`, since both reduce to the same `[IndiEvent]` shape.
    static func relevantMessages(from events: [IndiEvent], deviceNames: Set<String>) -> [TelescopeMessage] {
        events.filter { isRelevant($0, deviceNames: deviceNames) }.map(TelescopeMessage.init(event:))
    }

    /// Upserts `messages` into `accumulated` (keyed by `TelescopeMessage.id`) and returns the
    /// result, chronologically sorted. `id` is content-based (timestamp+device+text), so the same
    /// underlying event arriving via both history and the live stream collapses to one entry
    /// rather than being counted twice.
    static func upserting(_ messages: [TelescopeMessage], into accumulated: [String: TelescopeMessage]) -> [String: TelescopeMessage] {
        var result = accumulated
        for message in messages { result[message.id] = message }
        return result
    }

    static func sorted(_ accumulated: [String: TelescopeMessage]) -> [TelescopeMessage] {
        accumulated.values.sorted { $0.sortDate < $1.sortDate }
    }
}
