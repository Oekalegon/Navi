//
//  WindowTabGroup.swift
//  Navi
//
//  NAVI-70: user-configurable named tabs. A macOS window scene now opens with a `WindowTabGroup`
//  (an ordered list of tabs + which is selected) instead of a bare `WindowToken` — each tab is
//  still exactly one `WindowToken`/`PaneManager` under the hood (`WindowRegistry.adopt`/`stage`/
//  `release` are unchanged), so this is purely an additive grouping-and-naming layer.
//

import Foundation

/// The persisted identity + user-facing name of one tab. `id` is the same UUID as the
/// `WindowToken.id`/`PaneManager.tabID` for that tab — the one thing that ties this naming layer
/// to the underlying pane-tree machinery.
struct TabDescriptor: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
}

/// What one macOS window actually opens with: an ordered set of tabs and which is showing.
struct WindowTabGroup: Codable, Hashable {
    var id: UUID
    var tabs: [TabDescriptor]
    var selectedTabID: UUID

    /// A single, freshly-named tab — what "File > New Window" (or any window beyond the app's
    /// very first) opens with. Deliberately not a copy of the main window's tabs: a new window is
    /// a blank slate, matching today's existing "New Window" behavior.
    static func blank(name: String = "Untitled") -> WindowTabGroup {
        single(tabID: UUID(), name: name)
    }

    /// A one-tab group wrapping an already-existing tab id — used when a pane is detached into
    /// its own window (PaneMoveButton) and the new window's single tab must reuse the id
    /// WindowRegistry.stage(_:) minted, not a fresh one.
    static func single(tabID: UUID, name: String = "Untitled") -> WindowTabGroup {
        WindowTabGroup(id: UUID(), tabs: [TabDescriptor(id: tabID, name: name)], selectedTabID: tabID)
    }

    private static let storageKey = "navi.mainWindowTabGroup"

    /// The main window's tab group: whatever was last persisted, or — on a fresh install — the
    /// two-tab default (Telescope Control, Post-Processing), which is itself just a starting
    /// point the user can immediately rename, reconfigure, or delete like any other tab.
    static func loadOrSeedMainWindow() -> WindowTabGroup {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let group = try? JSONDecoder().decode(WindowTabGroup.self, from: data) {
            return group
        }

        let telescopeControlID = UUID()
        let postProcessingID = UUID()
        // Persist each seeded tab's layout immediately so the normal adopt() ->
        // fromSavedLayout(tabID:) path picks it up the moment ContentView adopts it — no separate
        // staging mechanism needed for the seed case.
        PaneManager.telescopeControlDefault(tabID: telescopeControlID).saveLayout()
        PaneManager.postProcessingDefault(tabID: postProcessingID).saveLayout()

        let group = WindowTabGroup(
            id: UUID(),
            tabs: [
                TabDescriptor(id: telescopeControlID, name: "Telescope Control"),
                TabDescriptor(id: postProcessingID, name: "Post-Processing")
            ],
            selectedTabID: telescopeControlID
        )
        group.persistAsMainWindow()
        return group
    }

    func persistAsMainWindow() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Appends a new tab and selects it. Pulled out of ContentView so this ordering/selection
    /// logic is unit-testable without standing up a SwiftUI view (see WindowTabGroupTests).
    @discardableResult
    mutating func addingTab(id: UUID = UUID(), name: String = "Untitled") -> UUID {
        tabs.append(TabDescriptor(id: id, name: name))
        selectedTabID = id
        return id
    }

    /// Removes `tabID`, moving selection to its former neighbor if it was selected. A window
    /// always shows at least one tab, so this is a no-op (returns false) on the last tab —
    /// callers close the window itself instead.
    @discardableResult
    mutating func closingTab(_ tabID: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        tabs.remove(at: index)
        if selectedTabID == tabID {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        return true
    }

    mutating func movingTab(_ tabID: UUID, by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let newIndex = index + offset
        guard tabs.indices.contains(newIndex) else { return }
        tabs.swapAt(index, newIndex)
    }
}
