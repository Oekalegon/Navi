//
//  SettingsView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var apiKeyInput: String = ""
    @State private var showingKey: Bool = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)

            Divider()

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
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 12) {
                Text("MCP Server Path").font(.headline)
                Text("Path to the AstrophotoKit MCP executable")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    TextField("/Users/username/.local/bin/astrokit-mcp", text: $settings.mcpPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        panel.canChooseFiles = true
                        panel.message = "Select the astrokit-mcp executable"
                        panel.showsHiddenFiles = true
                        panel.treatsFilePackagesAsDirectories = true
                        let homeDir = FileManager.default.homeDirectoryForCurrentUser
                        let localBin = homeDir.appendingPathComponent(".local/bin")
                        panel.directoryURL = FileManager.default.fileExists(atPath: localBin.path) ? localBin : homeDir
                        if panel.runModal() == .OK, let url = panel.url {
                            if url.startAccessingSecurityScopedResource() {
                                settings.saveMCPBookmark(url)
                                settings.mcpPath = url.path
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

            Spacer()

            HStack {
                Button("Clear") { settings.clearAPIKey(); apiKeyInput = "" }
                    .disabled(settings.apiKey.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { settings.apiKey = apiKeyInput; dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKeyInput.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear { apiKeyInput = settings.apiKey }
    }
}
