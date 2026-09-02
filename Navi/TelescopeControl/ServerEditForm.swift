//
//  ServerEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// Editor for one `ServerProfile` (§4.2) — a named INDI-MCP endpoint. See `MountEditForm` for the
/// bind-directly-to-the-record, no-Save-button convention.
///
/// The URL is the one field that can't bind straight through: `ServerProfile.url` is a
/// non-optional `URL`, and a half-typed address doesn't parse. So the text is held locally and
/// written to the record only once it parses, with a hint shown meanwhile — the record keeps its
/// last good URL rather than being cleared mid-keystroke.
///
/// There's deliberately no connect-on-save any more: that fired from the old Save button, and with
/// continuous editing there's no equivalent moment (a half-typed host would trigger it). Each row
/// in `ServerSettingsPane` has an explicit Connect/Disconnect button (NAVI-63), which is the
/// discoverable place for it.
struct ServerEditForm: View {
    @Bindable var server: ServerProfile

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    @State private var urlString = ""
    @State private var urlError: String?

    var body: some View {
        SettingsDetailForm(title: server.name.isEmpty ? "Untitled Server" : server.name) {
            LabeledField("Name") {
                TextField("Observatory Pi", text: $server.name)
                        .focused($isNameFocused)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledField("URL") {
                TextField("http://telescope.local:8000/mcp", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
            }
            if let urlError {
                Text(urlError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $server.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onAppear {
            if server.name.isEmpty { isNameFocused = true }
            urlString = server.url.absoluteString
        }
        .onChange(of: urlString) { commitURL() }
        .onChange(of: changeKey) { server.modifiedAt = .now }
    }

    /// Name and notes only — the URL stamps `modifiedAt` itself in `commitURL()`, since it's
    /// written to the record only once the typed text parses.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(server.name)
        parts.append(server.notes ?? "")
        return parts.joined(separator: "\u{1F}")
    }

    private func commitURL() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            urlError = "Not a valid URL yet — e.g. http://telescope.local:8000/mcp"
            return
        }
        urlError = nil
        guard url != server.url else { return }
        server.url = url
        server.modifiedAt = .now
    }
}
