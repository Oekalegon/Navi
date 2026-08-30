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

// NAVI-64: exposes the focused window's PaneManager to menu-bar commands (TelescopeCommands),
// which — unlike a pane view — have no window of their own to read it from directly.
private struct PaneManagerKey: FocusedValueKey {
    typealias Value = PaneManager
}

extension FocusedValues {
    var importAction: (() -> Void)? {
        get { self[ImportActionKey.self] }
        set { self[ImportActionKey.self] = newValue }
    }

    var paneManager: PaneManager? {
        get { self[PaneManagerKey.self] }
        set { self[PaneManagerKey.self] = newValue }
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
                configurations: [ModelConfiguration(schema: schema, url: Self.equipmentLibraryStoreURL())]
            )
        } catch {
            fatalError("Failed to create equipment library ModelContainer: \(error)")
        }
    }()

    /// An explicit, app-namespaced store URL. Navi isn't sandboxed, so `ModelConfiguration`'s
    /// default (no `url:` given) resolves to the bare, unnamespaced `~/Library/Application
    /// Support/default.store` — a path shared by *every* unsandboxed SwiftData app on the same
    /// Mac that also omits an explicit URL. Confirmed by hitting exactly this collision locally:
    /// another app's store already occupied that path, so Navi's migration plan saw a completely
    /// unrelated schema and failed with "Cannot use staged migration with an unknown model
    /// version." Scoping the store under the bundle identifier avoids that class of collision.
    private static func equipmentLibraryStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: Bundle.main.bundleIdentifier ?? "org.oekalegon.Navi", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "EquipmentLibrary.store")
    }

    var body: some Scene {
        // Every window — the initial one, File > New Window, and panes detached via the
        // move-pane menu's New Window item (NAVI-10) — opens with a WindowTabGroup: an ordered,
        // named set of tabs, each of which resolves to its own PaneManager in the WindowRegistry
        // exactly as a single window did before NAVI-70 added tabs.
        WindowGroup(for: WindowTabGroup.self) { $group in
            ContentView(group: group)
        } defaultValue: {
            // Only the very first window (nothing registered yet) restores/seeds the main
            // window's persisted tabs; a later explicit File > New Window starts blank, matching
            // pre-NAVI-70 "New Window" behavior rather than duplicating the main window's tabs.
            WindowRegistry.shared.entries.isEmpty ? WindowTabGroup.loadOrSeedMainWindow() : WindowTabGroup.blank()
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            NaviCommands()
            TelescopeCommands()
        }
        .modelContainer(equipmentLibraryContainer)

        Settings {
            SettingsRootView()
                .environment(SettingsManager.shared)
        }
        .modelContainer(equipmentLibraryContainer)
    }
}
