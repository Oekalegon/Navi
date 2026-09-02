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

    /// No `.new` case: "+" inserts a blank server and selects it, so there's no draft state.
    private enum Selection: Hashable {
        case existing(PersistentIdentifier)
    }
    @State private var selection: Selection?
    @State private var serverPendingDeletion: ServerProfile?

    private var selectedServer: ServerProfile? {
        guard case .existing(let id) = selection else { return nil }
        return servers.first { $0.persistentModelID == id }
    }
    @State private var unreachableWarning: String?
    /// Result of a stateless reachability check, shown inline in the detail pane. Only reachable
    /// while another server/rig owns the session, where connecting outright isn't an option.
    @State private var reachabilityResult: String?

    /// A blank server needs a syntactically valid URL to exist at all (`ServerProfile.url` is
    /// non-optional); the user replaces it immediately in the detail pane. Hoisted to a constant so
    /// the force-unwrap is written once, against a literal that provably can't fail, rather than
    /// inline where it invites copying somewhere it isn't safe.
    private static let placeholderServerURL = URL(string: "http://localhost:8000/mcp")!

    /// Inserts a blank server and selects it.
    private func insert() {
        let new = ServerProfile(name: "", url: Self.placeholderServerURL)
        modelContext.insert(new)
        try? modelContext.save()
        selection = .existing(new.persistentModelID)
    }

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
                onAdd: { insert() },
                isRemoveDisabled: selectedServer == nil,
                removeHelp: "Remove the selected server",
                onRemove: { if let server = selectedServer { serverPendingDeletion = server } }
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
        case nil:
            placeholder
        }
    }

    private func serverDetail(for server: ServerProfile) -> some View {
        VStack(spacing: 0) {
            ServerEditForm(server: server)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            connectionSection(for: server)
                .onChange(of: server.persistentModelID) { reachabilityResult = nil }
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
        let connectionState = connectionState(for: server)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body)
                Text(server.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Status only — the Connect/Disconnect *action* lives in the detail pane, so the row
            // stays a plain list row (matching how deletion moved to the header's "−"). A passive
            // dot is still worth keeping: it's the only way to see which server is live without
            // selecting each one in turn.
            switch connectionState {
            case .connected:
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help("Connected")
            case .connecting:
                ProgressView().controlSize(.small).frame(width: 12, height: 12)
            case .disconnected, .unavailable:
                EmptyView()
            }
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

    private func connectionState(for server: ServerProfile) -> RowConnectionState {
        if telescope.state == .connecting, telescope.connectingServer?.persistentModelID == server.persistentModelID {
            return .connecting
        }
        if telescope.state == .connected, telescope.currentServer?.persistentModelID == server.persistentModelID {
            return .connected
        }
        return telescope.state == .disconnected ? .disconnected : .unavailable
    }

    /// The Connect/Disconnect control, in the detail pane rather than on each row. Previously a
    /// successful Save connected automatically; with edits now committing continuously there's no
    /// equivalent moment to hang that off (a half-typed host would trigger it), so connecting is an
    /// explicit action on the server you're looking at.
    @ViewBuilder
    private func connectionSection(for server: ServerProfile) -> some View {
        let state = connectionState(for: server)
        HStack(spacing: 10) {
            switch state {
            case .connected:
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.callout)
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Connecting\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .unavailable:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Another server or rig is connected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let reachabilityResult {
                        Text(reachabilityResult)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            case .disconnected:
                Text("Not connected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch state {
            case .connected:
                Button("Disconnect") { Task { await telescope.disconnect() } }
            case .connecting:
                Button("Connect") {}
                    .disabled(true)
            case .unavailable:
                // Connecting would steal the live session, so offer the stateless reachability
                // check instead — the same one the old connect-on-save path fell back to when
                // something else was already connected (NAVI-63).
                Button("Test Connection") { test(server) }
                    .help("Check this server is reachable without disturbing the current session")
            case .disconnected:
                Button("Connect") { connect(server) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func connect(_ server: ServerProfile) {
        Task { await connectAndReportFailure(server) }
    }

    private func test(_ server: ServerProfile) {
        reachabilityResult = "Checking\u{2026}"
        Task {
            if let error = await TelescopeConnectivityTester.testConnection(to: server.url) {
                reachabilityResult = "Not reachable — \(error)"
            } else {
                reachabilityResult = "Reachable"
            }
        }
    }

    // Shared by the detail pane's Connect button and NAVI-67's auto-upgrade path.
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
