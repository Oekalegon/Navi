//
//  ServerSettingsSheet.swift
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
/// Edits are live (SwiftData), not batched behind a form-wide Save the way the rest of
/// `SettingsView` works — matches `ArchiveFilterSheet`/`TelescopeSelectionSheet`'s pattern of a
/// dedicated sheet for a list-editing concern, rather than folding a CRUD list into the single-
/// VStack settings form.
struct ServerSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ServerProfile.name) private var servers: [ServerProfile]

    @State private var editingServer: ServerProfile?
    @State private var isPresentingNewServer = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if servers.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(servers) { server in
                        row(for: server)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .frame(width: 420, height: 360)
        .sheet(item: $editingServer) { server in
            ServerEditForm(server: server)
        }
        .sheet(isPresented: $isPresentingNewServer) {
            ServerEditForm(server: nil)
        }
    }

    private var header: some View {
        HStack {
            Text("Telescope Servers")
                .font(.headline)
            Spacer()
            Button(action: { isPresentingNewServer = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .help("Add Server")
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
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
            Button("Edit") { editingServer = server }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingServer = server }
    }

    private func delete(at offsets: IndexSet) {
        // Deleting a server that some RigProfile.defaultServer points to nullifies that
        // reference (RigProfile.defaultServer is @Relationship(deleteRule: .nullify), verified in
        // EquipmentLibrarySchemaTests) rather than blocking the delete — no warning shown here,
        // since there's no Rig editor yet (NAVI-55) to actually create that reference through the
        // UI. Revisit once one exists.
        for index in offsets {
            modelContext.delete(servers[index])
        }
        try? modelContext.save()
    }
}
