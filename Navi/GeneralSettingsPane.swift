//
//  GeneralSettingsPane.swift
//  Navi
//
//  The Settings "General" tab: the Archive path. The Anthropic API key lives in its own
//  APIKeySettingsPane tab (NAVI-56 follow-up).
//

import SwiftUI
import AppKit

struct GeneralSettingsPane: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var settings = settings

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
