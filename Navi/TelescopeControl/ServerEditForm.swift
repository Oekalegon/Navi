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
struct ServerEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let server: ServerProfile?

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

        if let server {
            server.name = trimmedName
            server.url = url
            server.modifiedAt = .now
        } else {
            modelContext.insert(ServerProfile(name: trimmedName, url: url))
        }
        try? modelContext.save()
        dismiss()
    }
}
