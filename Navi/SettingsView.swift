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
    @State private var showingServerSettings = false
    @State private var showingObservatorySettings = false
    @State private var showingRigSettings = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)

            Divider()
                .padding(.top, 12)

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

                VStack(alignment: .leading, spacing: 12) {
                    Text("Telescope Servers").font(.headline)
                    Text("Named INDI-MCP servers a rig can connect to")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Manage Servers…") { showingServerSettings = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Observatories").font(.headline)
                    Text("Observatory locations a rig can default to")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Manage Observatories…") { showingObservatorySettings = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Rigs").font(.headline)
                    Text("Equipment-library-backed rigs (mount, optics, cameras)")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Manage Rigs…") { showingRigSettings = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Clear") { settings.clearAPIKey(); apiKeyInput = "" }
                    .disabled(settings.apiKey.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { settings.apiKey = apiKeyInput; dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(apiKeyInput.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 640)
        .onAppear { apiKeyInput = settings.apiKey }
        .sheet(isPresented: $showingServerSettings) {
            ServerSettingsSheet()
        }
        .sheet(isPresented: $showingObservatorySettings) {
            ObservatorySettingsSheet()
        }
        .sheet(isPresented: $showingRigSettings) {
            RigSettingsSheet()
        }
    }
}
