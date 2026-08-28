//
//  GeneralSettingsPane.swift
//  Navi
//
//  The Settings "General" tab: Anthropic API key, Archive path, and FITS data directory. Split
//  out of SettingsRootView.swift (NAVI-56) to match the one-file-per-pane convention the
//  Server/Observatory/Rig panes already follow.
//

import SwiftUI
import AppKit

struct GeneralSettingsPane: View {
    @Environment(SettingsManager.self) private var settings
    @State private var apiKeyInput: String = ""
    @State private var showingKey: Bool = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Anthropic API Key")
                        .font(.headline)
                    Text("Enter your Claude API key from console.anthropic.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        if showingKey {
                            TextField("sk-ant-api03-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-api03-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(action: { showingKey.toggle() }) {
                            Image(systemName: showingKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }

                    if !settings.apiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("API key saved").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Button("Clear") { settings.clearAPIKey(); apiKeyInput = "" }
                        .disabled(settings.apiKey.isEmpty)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Archive Path").font(.headline)
                    Text("Path to your AstroArchive database")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack {
                        TextField("/path/to/AstroArchive", text: $settings.archivePath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.message = "Select your AstroArchive directory"
                            panel.showsHiddenFiles = true
                            if panel.runModal() == .OK, let url = panel.url {
                                if url.startAccessingSecurityScopedResource() {
                                    settings.saveArchiveBookmark(url)
                                    settings.archivePath = url.path
                                    url.stopAccessingSecurityScopedResource()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("FITS Data Directory").font(.headline)
                    Text("Root folder containing your FITS image files")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack {
                        TextField("/path/to/FITS/data", text: $settings.dataPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.message = "Select the root folder of your FITS data"
                            panel.showsHiddenFiles = true
                            if panel.runModal() == .OK, let url = panel.url {
                                if url.startAccessingSecurityScopedResource() {
                                    settings.saveDataBookmark(url)
                                    settings.dataPath = url.path
                                    url.stopAccessingSecurityScopedResource()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding()
        }
        .onAppear { apiKeyInput = settings.apiKey }
        .onDisappear { commitAPIKeyIfChanged() }
    }

    /// Archive Path / FITS Data Directory bind straight to `settings` and persist every
    /// keystroke; the API key stages in `apiKeyInput` instead so typing doesn't hit Keychain on
    /// every character. Now that this pane is a persistent Settings tab rather than a modal sheet
    /// with a mandatory Save/Cancel choice, the window (or tab) can simply be closed mid-edit — so
    /// commit any staged, non-empty change here rather than silently discarding it.
    private func commitAPIKeyIfChanged() {
        guard !apiKeyInput.isEmpty, apiKeyInput != settings.apiKey else { return }
        settings.apiKey = apiKeyInput
    }
}
