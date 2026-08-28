//
//  ServerSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Server pane" (§4.2): a plain list of named INDI-MCP servers (name + URL) in the
/// local equipment library. A `RigProfile` references one as its default (§4.1's toolbar Connect
/// targets whichever server the armed rig defaults to) — changing that default is a Rig-editor
/// action (NAVI-55), not something this pane does.
///
/// Edits are live (SwiftData), not batched behind a form-wide Save — matches
/// `ArchiveFilterSheet`/`TelescopeSelectionSheet`'s pattern of a dedicated view for a
/// list-editing concern, rather than folding a CRUD list into `GeneralSettingsPane`'s
/// card-based form.
struct ServerSettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ServerProfile.name) private var servers: [ServerProfile]

    @State private var editingServer: ServerProfile?
    @State private var isPresentingNewServer = false
    @State private var serverPendingDeletion: ServerProfile?

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Telescope Servers",
                addHelp: "Add Server",
                onAdd: { isPresentingNewServer = true }
            )
            Divider()
            if servers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(servers) { server in
                        row(for: server)
                    }
                }
            }
        }
        .sheet(item: $editingServer) { server in
            ServerEditForm(server: server)
        }
        .sheet(isPresented: $isPresentingNewServer) {
            ServerEditForm(server: nil)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body)
                Text(server.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        .contentShape(Rectangle())
        .onTapGesture { editingServer = server }
    }

    private func delete(_ server: ServerProfile) {
        // Deleting a server that some RigProfile.defaultServer points to nullifies that
        // reference (RigProfile.defaultServer is @Relationship(deleteRule: .nullify), verified in
        // EquipmentLibrarySchemaTests) rather than blocking the delete — the confirmation dialog
        // above is the warning; there's no Rig editor yet (NAVI-55) to show which rigs it'd
        // affect by name, so the message stays generic for now.
        modelContext.delete(server)
        try? modelContext.save()
    }
}
