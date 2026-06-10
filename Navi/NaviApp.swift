//
//  NaviApp.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AppKit

private struct ImportActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var importAction: (() -> Void)? {
        get { self[ImportActionKey.self] }
        set { self[ImportActionKey.self] = newValue }
    }
}

struct NaviCommands: Commands {
    @FocusedValue(\.importAction) private var importAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import…") {
                if let importAction {
                    importAction()
                } else {
                    showStandaloneImportPanel()
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }

    private func showStandaloneImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.title = "Import FITS Files"
        panel.prompt = "Import"
        panel.message = "Select FITS files or folders containing FITS files"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { await ArchiveManager.shared.importFITS(urls: urls) }
    }
}

@main
struct NaviApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { NaviCommands() }
    }
}
