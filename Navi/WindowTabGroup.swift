//
//  WindowTabGroup.swift
//  Navi
//
//  NAVI-70: user-configurable named tabs. A macOS window scene now opens with a `WindowTabGroup`
//  (an ordered list of tabs + which is selected) instead of a bare `WindowToken` — each tab is
//  still exactly one `WindowToken`/`PaneManager` under the hood (`WindowRegistry.adopt`/`stage`/
//  `release` are unchanged), so this is purely an additive grouping-and-naming layer. Every
//  window — not just the main one — gets this, including reliable persistence across relaunch and
//  the ability to move a tab into another open window (see WindowRegistry's window-tracking
//  additions).
//

import Foundation
import Observation

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

    /// A single, freshly-named tab — what "File > New Window" opens with.
    static func blank(name: String = "Untitled") -> WindowTabGroup {
        single(tabID: UUID(), name: name)
    }

    /// A one-tab group wrapping an already-existing tab id — used when a pane is detached into
    /// its own window (PaneMoveButton) or a tab is moved into its own window, where the new
    /// window's single tab must reuse an id minted elsewhere, not a fresh one.
    static func single(tabID: UUID, name: String = "Untitled") -> WindowTabGroup {
        WindowTabGroup(id: UUID(), tabs: [TabDescriptor(id: tabID, name: name)], selectedTabID: tabID)
    }

    /// The two-tab starting point seeded on a fresh install — a sensible, fully user-editable
    /// starting point the user can immediately rename, reconfigure, or delete, not a fixed preset.
    static func seedDefaultMainWindow() -> WindowTabGroup {
        let telescopeControlID = UUID()
        let postProcessingID = UUID()
        // Persist each seeded tab's layout immediately so the normal adopt() ->
        // fromSavedLayout(tabID:) path picks it up the moment ContentView adopts it — no separate
        // staging mechanism needed for the seed case.
        PaneManager.telescopeControlDefault(tabID: telescopeControlID).saveLayout()
        PaneManager.postProcessingDefault(tabID: postProcessingID).saveLayout()

        return WindowTabGroup(
            id: UUID(),
            tabs: [
                TabDescriptor(id: telescopeControlID, name: "Telescope Control"),
                TabDescriptor(id: postProcessingID, name: "Post-Processing")
            ],
            selectedTabID: telescopeControlID
        )
    }

    private static let allWindowsKey = "navi.allWindowTabGroups"

    /// Every window's tab group, in the order they were opened — the main window first. Restored
    /// as a batch at launch (NaviApp hands the first to its default window, ContentView opens the
    /// rest); WindowRegistry re-persists this list after every add/close/rename/reorder/move so it
    /// stays current for the next relaunch, not left to macOS's own fragile session restoration.
    static func loadAllPersisted() -> [WindowTabGroup] {
        guard let data = UserDefaults.standard.data(forKey: allWindowsKey),
              let groups = try? JSONDecoder().decode([WindowTabGroup].self, from: data)
        else { return [] }
        return groups
    }

    static func persistAll(_ groups: [WindowTabGroup]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: allWindowsKey)
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
    /// always shows at least one tab, so this is a no-op (returns false) on the last tab — the
    /// same restriction "Close Tab" and "Move to another window" both already enforce in the UI.
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

/// The live, observable home of one window's WindowTabGroup, held by WindowRegistry and adopted
/// by that window's ContentView exactly the way a tab's PaneManager is adopted — a reference type
/// so a tab moved in from another window (WindowRegistry.moveTab(_:toWindow:) mutating this same
/// instance) is picked up by this window's already-rendered body without any extra plumbing.
@Observable
final class TabGroupBox {
    var group: WindowTabGroup
    init(_ group: WindowTabGroup) { self.group = group }
}
