//
//  TelescopeMessagesView.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §3.3, §4.7. A normal, button-driven pane (unlike the
//  Dashboard's auto-open exception) showing raw INDI-MCP messages scoped to the current rig's
//  devices — durable history loaded once on open, plus the live stream thereafter.
//

import SwiftUI
import INDIMCPKit

struct TelescopeMessagesView: View {
    var pane: SplitPane
    @State private var telescope = TelescopeSessionManager.shared
    @State private var stream: ObservableMessageStream?
    // Accumulated, not re-derived from history ∪ the live stream's current window on every
    // render: ObservableMessageStream.events is only a bounded rolling window, so a message that
    // arrives and later ages out of that window must stay visible here regardless (see
    // TelescopeMessage.swift's header comment).
    @State private var accumulated: [String: TelescopeMessage] = [:]
    @State private var historyError: String?

    private var deviceNames: Set<String> {
        Set(telescope.currentRig?.components.compactMap(\.device) ?? [])
    }

    private var messages: [TelescopeMessage] {
        TelescopeMessageFilter.sorted(accumulated)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: telescope.connectionSessionID) {
            await loadHistoryAndSubscribe()
        }
        .onChange(of: stream?.events) {
            upsert(stream?.events ?? [])
        }
    }

    // Loads durable history once, then holds the shared message-stream subscription for the
    // lifetime of one connected session — released (via defer) when this task is cancelled, either
    // by connectionSessionID changing or this view disappearing (pane closed), mirroring
    // ObservatoryDashboardView.holdDeviceAcquisitions().
    private func loadHistoryAndSubscribe() async {
        accumulated = [:]
        historyError = nil
        guard telescope.state == .connected else { return }
        stream = telescope.acquireMessageStream()
        defer {
            telescope.releaseMessageStream()
            stream = nil
        }
        do {
            let history = try await telescope.getMessageHistory()
            upsert(history.compactMap { try? $0.decodedMessage() })
        } catch {
            historyError = TelescopeSessionManager.describe(error)
        }
        // Folds in whatever's already in the live window at this point too, in case the
        // subscription's first window arrived before this history fetch completed.
        upsert(stream?.events ?? [])
        try? await Task.sleep(for: .seconds(86400))
    }

    private func upsert(_ events: [IndiEvent]) {
        let relevant = TelescopeMessageFilter.relevantMessages(from: events, deviceNames: deviceNames)
        accumulated = TelescopeMessageFilter.upserting(relevant, into: accumulated)
    }

    private var headerBar: some View {
        PaneHeaderBar(paneType: .telescopeMessages, pane: pane) {
            Image(systemName: "terminal")
                .font(.system(size: 14))
            Text("Messages")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if telescope.state != .connected {
            disconnectedState
        } else if messages.isEmpty {
            emptyState
        } else {
            List(messages) { message in
                TelescopeMessageRow(message: message)
            }
            .listStyle(.plain)
        }
    }

    private var disconnectedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not connected")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No Messages")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let historyError {
                Text(historyError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TelescopeMessageRow: View {
    let message: TelescopeMessage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
            Text(timeText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if let device = message.device {
                Text(device)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(message.text ?? "")
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var timeText: String {
        guard message.sortDate != .distantPast else { return message.timestamp }
        return message.sortDate.formatted(date: .omitted, time: .standard)
    }

    private var stateColor: Color {
        switch message.state {
        case .alert: .red
        case .busy: .orange
        case .ok: .green
        case .idle, .other, nil: .secondary
        }
    }
}
