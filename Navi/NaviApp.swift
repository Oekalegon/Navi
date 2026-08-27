//
//  NaviApp.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import SwiftData
import AppKit // NSOpenPanel in NaviCommands.showStandaloneImportPanel()

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
    // Explicit container (rather than `.modelContainer(for:)`'s single-root-type relationship
    // inference) so `EquipmentLibrarySchema.models` stays the one source of truth for what's in
    // the store.
    private let equipmentLibraryContainer: ModelContainer = {
        let schema = Schema(EquipmentLibrarySchema.models)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: EquipmentLibraryMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema)]
            )
        } catch {
            fatalError("Failed to create equipment library ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Every window — the initial one, File > New Window, and panes detached
        // via the move-pane menu's New Window item (NAVI-10) — is keyed by a
        // WindowToken that resolves to its PaneManager in the WindowRegistry.
        WindowGroup(for: WindowToken.self) { $token in
            ContentView(token: token)
        } defaultValue: {
            WindowToken(id: UUID(), rootType: .aiAssistant)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { NaviCommands() }
        .modelContainer(equipmentLibraryContainer)
    }
}
