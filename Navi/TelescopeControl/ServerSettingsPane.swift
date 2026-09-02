//
//  ServerSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Server pane" (§4.2): a plain list of named INDI-MCP servers (name + URL) in the
/// local equipment library, shown as a master-detail layout (NAVI-77) — the sidebar list on the
/// left, `ServerEditForm` embedded inline as detail content on the right, no modal sheet.
/// Deliberately a plain `HStack`, not `NavigationSplitView`: this pane is one tab of
/// `SettingsRootView`'s `TabView`, and `NavigationSplitView` hooks into the *window's* toolbar/
/// sidebar chrome the same way `TabView` itself does (see `TelescopeControlView`'s NAVI-76 doc
/// comment for the sibling case) — nesting one window-chrome-owning container inside another left
/// a previous tab's sidebar list stuck on screen when switching tabs. A plain `HStack` gives the
/// same sidebar/detail look with no AppKit toolbar/sidebar integration to conflict with `TabView`.
/// A `RigProfile` references one as its default (§4.1's toolbar Connect targets whichever
/// server the armed rig defaults to) — changing that default is a Rig-editor action (NAVI-55), not
/// something this pane does.
///
/// Edits are live (SwiftData), not batched behind a form-wide Save — matches
/// `ArchiveFilterSheet`/`TelescopeSelectionSheet`'s pattern of a dedicated view for a
/// list-editing concern, rather than folding a CRUD list into `GeneralSettingsPane`'s
/// card-based form.
///
/// NAVI-63: each row has a real Connect/Disconnect button backed by
/// `TelescopeSessionManager.connect(server:)` — a bare, Rig-less connect, distinct from the
/// toolbar's Rig-bound Connect (§4.1). Since `TelescopeSessionManager` holds a single live
/// session app-wide, only one server (or Rig) can be connected at a time; a row for any other
/// server just shows disabled/unavailable while something else is live. Saving a new/edited
/// server also attempts to connect to it automatically (if nothing else is already connected) and
/// stays connected on success — warning, not blocking, on failure.
///
/// NAVI-62/NAVI-77: the detail pane also embeds `DriverManagementSheet` as a plain conditional
/// section, shown only while the selected server is the one actually connected — it disappears on
/// its own on disconnect since the detail view is already reactive to `telescope.state`.
struct ServerSettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ServerProfile.name) private var servers: [ServerProfile]
    @State private var telescope = TelescopeSessionManager.shared

    private enum Selection: Hashable {
        case existing(PersistentIdentifier)
        case new
    }
    @State private var selection: Selection?
    @State private var serverPendingDeletion: ServerProfile?
    @State private var unreachableWarning: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Delete “\(serverPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { serverPendingDeletion != nil },
                set: { if !$0 { serverPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let server = serverPendingDeletion { delete(server) }
                serverPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { serverPendingDeletion = nil }
        } message: {
            Text("Any rig that defaults to this server will need a new default server chosen before it can connect.")
        }
        .alert(
            "Server Not Reachable",
            isPresented: Binding(
                get: { unreachableWarning != nil },
                set: { if !$0 { unreachableWarning = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text((unreachableWarning ?? "") + "\n\nThe server is still saved — you can try connecting again once it's back online.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Telescope Servers",
                addHelp: "Add Server",
                onAdd: { selection = .new }
            )
            Divider()
            if servers.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(servers) { server in
                        row(for: server)
                            .tag(Selection.existing(server.persistentModelID))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .existing(let id):
            if let server = servers.first(where: { $0.persistentModelID == id }) {
                serverDetail(for: server)
                    .id(id)
            } else {
                placeholder
            }
        case .new:
            ServerEditForm(
                server: nil,
                onSaved: { saved in Task { await connectAfterSave(saved) } },
                onFinished: { selection = nil }
            )
        case nil:
            placeholder
        }
    }

    private func serverDetail(for server: ServerProfile) -> some View {
        VStack(spacing: 0) {
            ServerEditForm(
                server: server,
                onSaved: { saved in Task { await connectAfterSave(saved) } },
                onFinished: { selection = nil }
            )
            .fixedSize(horizontal: false, vertical: true)
            if telescope.state == .connected, telescope.currentServer?.persistentModelID == server.persistentModelID {
                Divider()
                DriverManagementSheet(serverName: server.name)
            }
        }
    }

    private var placeholder: some View {
        Text("Select a server, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No servers yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add the INDI-MCP server for your observatory Pi.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for server: ServerProfile) -> some View {
        let connectionState = rowConnectionState(for: server)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body)
                Text(server.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            connectionButton(for: server, state: connectionState)
            // Explicit buttons, not a gesture/swipe: macOS's List(selection:)+.onDelete idiom
            // (the iOS edit-mode/swipe convention) has no reachable UI path here without a
            // selection binding — plain buttons are the reliable, discoverable macOS pattern.
            Button(action: { serverPendingDeletion = server }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete Server")
        }
    }

    private enum RowConnectionState {
        case connected
        case connecting
        case disconnected
        // Some other server (or a Rig) already occupies TelescopeSessionManager's single live
        // session — this row can't connect without disconnecting that one first.
        case unavailable
    }

    private func rowConnectionState(for server: ServerProfile) -> RowConnectionState {
        if telescope.state == .connecting, telescope.connectingServer?.persistentModelID == server.persistentModelID {
            return .connecting
        }
        if telescope.state == .connected, telescope.currentServer?.persistentModelID == server.persistentModelID {
            return .connected
        }
        return telescope.state == .disconnected ? .disconnected : .unavailable
    }

    @ViewBuilder
    private func connectionButton(for server: ServerProfile, state: RowConnectionState) -> some View {
        switch state {
        case .connected:
            Button(action: { Task { await telescope.disconnect() } }) {
                Image(systemName: "circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .help("Connected — click to disconnect")
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .unavailable:
            Button(action: {}) {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary.opacity(0.4))
            .disabled(true)
            .help("Disconnect from the current server or rig first")
        case .disconnected:
            Button(action: { connect(server) }) {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Connect")
        }
    }

    private func connect(_ server: ServerProfile) {
        Task { await connectAndReportFailure(server) }
    }

    // Shared by the row button and connectAfterSave.
    private func connectAndReportFailure(_ server: ServerProfile) async {
        await telescope.connect(server: server)
        if let error = telescope.errorMessage {
            unreachableWarning = "\(server.name): \(error)"
        } else {
            // NAVI-67: a bare-server connect has no Rig armed — see if the now-live devices
            // match an existing local Rig and, if so, upgrade to a full rig-bound connection
            // automatically rather than leaving the toolbar showing "Select Rig…" despite
            // already being connected.
            await RigAutoMatcher.matchAndUpgrade(telescope: telescope, modelContext: modelContext, server: server)
        }
    }

    // NAVI-63: if nothing else is connected, a newly saved/edited server should end up actually
    // connected, not just tested-and-dropped — this is the same connect(server:) the row button
    // uses, so a manual reconnect later behaves identically. If some other server/rig is already
    // live, don't steal that session — fall back to a stateless reachability check
    // (TelescopeConnectivityTester) so the user still gets feedback without disrupting it.
    private func connectAfterSave(_ server: ServerProfile) async {
        if telescope.state == .disconnected {
            await connectAndReportFailure(server)
        } else if let error = await TelescopeConnectivityTester.testConnection(to: server.url) {
            unreachableWarning = "\(server.name): \(error)"
        }
    }

    private func delete(_ server: ServerProfile) {
        // Deleting a server that some RigProfile.defaultServer points to nullifies that
        // reference (RigProfile.defaultServer is @Relationship(deleteRule: .nullify), verified in
        // EquipmentLibrarySchemaTests) rather than blocking the delete — the confirmation dialog
        // above is the warning; there's no Rig editor yet (NAVI-55) to show which rigs it'd
        // affect by name, so the message stays generic for now.
        if telescope.state == .connected, telescope.currentServer?.persistentModelID == server.persistentModelID {
            Task { await telescope.disconnect() }
        }
        if selection == .existing(server.persistentModelID) {
            selection = nil
        }
        modelContext.delete(server)
        try? modelContext.save()
    }
}
