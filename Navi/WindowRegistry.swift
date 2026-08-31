//
//  WindowRegistry.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import Foundation

/// Identifies a window scene. Codable so macOS window restoration can bring a
/// window back after relaunch: the staged PaneManager is gone by then, but the
/// root pane type survives in the token, so a detached FITS-viewer window at
/// least reopens as a FITS viewer instead of a default AI-assistant window.
struct WindowToken: Codable, Hashable {
    var id: UUID
    var rootType: PaneType
}

/// A FITS viewer that could show a frame selected in an archive pane,
/// described for the user by the window it lives in.
struct FrameDestination: Identifiable {
    let id: UUID
    let title: String
    let paneManager: PaneManager
}

/// One PaneManager per window (NAVI-10). The first window registered is the
/// main window. Managers for windows opened via "New Window" in the move-pane
/// menu are staged here first; openWindow(value:) then delivers the UUID to
/// the new scene, whose ContentView adopts the staged manager.
///
/// Not @Observable on purpose: every use happens inside an action handler
/// (menu click, selection change), never during a view update. @MainActor is
/// explicit rather than relying on the target's default-isolation setting, so
/// the contract survives a move to another target or package.
@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    struct Entry {
        let id: UUID
        let paneManager: PaneManager
        let number: Int    // 1 = main window; never reused while the app runs
    }

    private(set) var entries: [Entry] = []
    private var staged: [UUID: PaneManager] = [:]
    private var released: Set<UUID> = []
    private var nextNumber = 1

    // NAVI-70 window-level tracking (separate from the per-tab Entry bookkeeping above): every
    // currently open window's tab group, keyed by the window's own WindowTabGroup.id, plus the
    // order windows were opened in (oldest first — the same "oldest surviving = main" convention
    // `destination(for:)` already uses for panes, generalized to windows).
    private var windowBoxes: [UUID: TabGroupBox] = [:]
    private var windowOrder: [UUID] = []
    private var hasStartedLaunchWindowRestoration = false

    /// The PaneManager backing a window scene: a previously staged manager, the
    /// already-registered one, or a fresh manager showing the token's root pane
    /// type (the restoration path — the staged manager did not survive the
    /// relaunch). Idempotent because SwiftUI re-creates a window's root view
    /// many times. A released ID is terminal: SwiftUI gives no guarantee the
    /// root view isn't re-initialized during window teardown, and
    /// re-registering here would create a zombie entry that shows up as a
    /// routing destination with no window behind it.
    func adopt(_ token: WindowToken) -> PaneManager {
        if let entry = entries.first(where: { $0.id == token.id }) { return entry.paneManager }
        guard !released.contains(token.id) else { return PaneManager(tabID: token.id, rootType: token.rootType) }
        let manager: PaneManager
        if let s = staged.removeValue(forKey: token.id) {
            manager = s
        } else if let restored = PaneManager.fromSavedLayout(tabID: token.id) {
            // NAVI-70: tab ids are now stable across relaunch (persisted in WindowTabGroup), so
            // any tab's saved layout can be restored this way — not just a single hardcoded
            // "first aiAssistant window" special case as before.
            manager = restored
        } else {
            manager = PaneManager(tabID: token.id, rootType: token.rootType)
        }
        entries.append(Entry(id: token.id, paneManager: manager, number: nextNumber))
        nextNumber += 1
        return manager
    }

    /// Stages a manager for a window about to open and returns the value to
    /// pass to openWindow.
    func stage(_ manager: PaneManager) -> WindowToken {
        // The token's id must match manager.tabID — not a fresh UUID — so saveLayout()'s
        // persistence key and this token's registry/restoration identity stay the same value
        // (NAVI-70; previously harmless since layout persistence wasn't per-tab).
        let token = WindowToken(
            id: manager.tabID,
            rootType: manager.rootPane.isLeaf ? manager.rootPane.paneType : .aiAssistant)
        staged[token.id] = manager
        return token
    }

    func release(_ id: UUID) {
        released.insert(id)
        entries.removeAll { $0.id == id }
    }

    /// The TabGroupBox backing a window scene: the already-registered one, or a freshly boxed
    /// `group` for a window opening for the first time. Idempotent for the same reason `adopt(_:)`
    /// is — SwiftUI can re-create a window's root view.
    func adoptWindow(_ group: WindowTabGroup) -> TabGroupBox {
        if let box = windowBoxes[group.id] { return box }
        let box = TabGroupBox(group)
        windowBoxes[group.id] = box
        windowOrder.append(group.id)
        persistAllWindows()
        return box
    }

    func releaseWindow(_ id: UUID) {
        windowBoxes[id] = nil
        windowOrder.removeAll { $0 == id }
        // Never persist a "zero windows" list: closing windows one at a time (including the
        // sequence of onDisappear calls a full app quit can fire, one per open window) would
        // otherwise shrink the persisted list a step at a time and, on whichever window happens
        // to close last, overwrite it with an empty list — wiping the user's actual arrangement
        // and making NaviApp's defaultValue reseed the fresh two-tab default on next launch. A
        // window closing on its own while others remain open still correctly shrinks the list.
        guard !windowOrder.isEmpty else { return }
        persistAllWindows()
    }

    func persistAllWindows() {
        WindowTabGroup.persistAll(windowOrder.compactMap { windowBoxes[$0]?.group })
    }

    /// One-shot gate for NaviApp's launch-time window restoration: true (and flips permanently)
    /// exactly once per app run, so only the very first ContentView instance to ask opens the
    /// rest of the persisted windows — every window opened afterwards (including those it opens)
    /// gets `false` and skips the step.
    func beginLaunchWindowRestorationIfNeeded() -> Bool {
        guard !hasStartedLaunchWindowRestoration else { return false }
        hasStartedLaunchWindowRestoration = true
        return true
    }

    /// Windows other than `excluding`, labeled for a "Move to Window" menu by whichever tab they
    /// currently have selected — more useful to the user than an arbitrary window number, and
    /// avoids introducing a second, possibly-inconsistent numbering scheme alongside
    /// `destination(for:)`'s pane-oriented one.
    func otherWindows(excluding: UUID) -> [(id: UUID, title: String)] {
        windowOrder.filter { $0 != excluding }.compactMap { id in
            guard let box = windowBoxes[id] else { return nil }
            let selectedName = box.group.tabs.first { $0.id == box.group.selectedTabID }?.name ?? "Untitled"
            let isMain = windowOrder.first == id
            return (id: id, title: isMain ? "Main Window" : selectedName)
        }
    }

    /// Moves `tab` out of whichever open window currently holds it (if any) and into
    /// `destinationID`'s group, selecting it there. Refuses the move — leaving every window
    /// untouched — if the destination doesn't exist, already has it, or it's the only tab in its
    /// current window (a window always keeps at least one tab; "New Window" is the way to pop out
    /// a window's last remaining tab).
    @discardableResult
    func moveTab(_ tab: TabDescriptor, toWindow destinationID: UUID) -> Bool {
        guard let destination = windowBoxes[destinationID],
              !destination.group.tabs.contains(where: { $0.id == tab.id })
        else { return false }
        guard let source = windowBoxes.values.first(where: { $0.group.tabs.contains { $0.id == tab.id } })
        else { return false }
        guard source.group.tabs.count > 1 else { return false }
        source.group.closingTab(tab.id)
        destination.group.tabs.append(tab)
        destination.group.selectedTabID = tab.id
        persistAllWindows()
        return true
    }

    /// The archive pane that windows without one of their own follow: the main
    /// window's, or — when the main window has none (e.g. its archive pane was
    /// moved out) — the first window that shows an archive pane.
    var primaryArchiveManager: PaneManager? {
        entries.first { $0.paneManager.isArchiveViewerVisible }?.paneManager
    }

    /// Routes a frame selected in `source`'s archive pane (NAVI-10): the source
    /// window's own FITS viewer and info panel follow the selection, and — when
    /// `source` holds the primary archive — so do the panes of every window
    /// without an archive pane of its own. Info panels all update directly.
    /// The frame is shown in the single candidate FITS viewer; if several could
    /// show it, nothing is shown and the candidates are returned so the caller
    /// can ask the user to pick one.
    func showFrame(url: URL, from source: PaneManager) -> [FrameDestination] {
        let followers = followers(of: source)
        for follower in followers {
            follower.paneManager.showInfoIfVisible(url: url)
        }
        let fitsCandidates = followers.filter { $0.paneManager.isFITSViewerVisible }
        if fitsCandidates.count <= 1 {
            fitsCandidates.first?.paneManager.showFITSViewerIfVisible(url: url)
            return []
        }
        return fitsCandidates
    }

    /// Syncs the rejected badge of every FITS viewer showing the frame at
    /// `path`: with multiple windows the same frame can be on display in
    /// several of them, so a reject toggled in one window must reach them all.
    func frameRejectionChanged(path: String, rejected: Bool) {
        for entry in entries where entry.paneManager.fitsURL?.path == path {
            entry.paneManager.fitsFrameRejected = rejected
        }
    }

    // The windows whose dependent panes follow `source`'s archive selection,
    // the source window itself first.
    private func followers(of source: PaneManager) -> [FrameDestination] {
        guard let sourceEntry = entries.first(where: { $0.paneManager === source }) else {
            // Not registered (e.g. unit tests driving a bare manager): the
            // selection stays within the source window.
            return [FrameDestination(id: UUID(), title: "This Window", paneManager: source)]
        }
        var result = [destination(for: sourceEntry, title: "This Window")]
        if source === primaryArchiveManager {
            for entry in entries
            where entry.paneManager !== source && !entry.paneManager.isArchiveViewerVisible {
                result.append(destination(for: entry))
            }
        }
        return result
    }

    private func destination(for entry: Entry, title: String? = nil) -> FrameDestination {
        // "Main Window" follows position, not the original number: when the
        // main window closes, the oldest remaining window takes over main-
        // window behaviour (entries order drives primaryArchiveManager), so
        // its title must say so too.
        let isMain = entries.first?.id == entry.id
        return FrameDestination(
            id: entry.id,
            title: title ?? (isMain ? "Main Window" : "Window \(entry.number)"),
            paneManager: entry.paneManager)
    }
}
