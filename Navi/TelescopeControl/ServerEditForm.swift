//
//  ServerEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// Add/edit form for one `ServerProfile`. `server == nil` means "creating a new one" — saving
/// inserts it; otherwise saving mutates the passed-in record in place.
///
/// NAVI-63: saving never blocks on reachability — a server can be registered while offline.
/// `onSaved` is where the caller (`ServerSettingsPane`) attempts to actually connect to it and
/// surfaces a warning if that fails, since that's also where the live connect/disconnect state
/// lives (`TelescopeSessionManager`); this form itself stays a plain, synchronous save.
struct ServerEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let server: ServerProfile?
    /// Called with the saved (inserted-or-mutated) server, so a caller like `RigEditForm` can
    /// adopt it as this rig's `defaultServer` right away, or `ServerSettingsPane` can attempt to
    /// connect to it.
    var onSaved: (ServerProfile) -> Void = { _ in }

    @State private var name = ""
    @State private var urlString = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(server == nil ? "Add Server" : "Edit Server")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Observatory Pi", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("http://telescope.local:8000/mcp", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360, height: 220)
        .onAppear {
            name = server?.name ?? ""
            urlString = server?.url.absoluteString ?? ""
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }
        guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
            validationError = "Enter a valid URL, e.g. http://telescope.local:8000/mcp"
            return
        }

        let saved: ServerProfile
        if let server {
            server.name = trimmedName
            server.url = url
            server.modifiedAt = .now
            saved = server
        } else {
            let created = ServerProfile(name: trimmedName, url: url)
            modelContext.insert(created)
            saved = created
        }
        try? modelContext.save()
        onSaved(saved)
        dismiss()
    }
}
