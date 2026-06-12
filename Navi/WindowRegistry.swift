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
        guard !released.contains(token.id) else { return PaneManager(rootType: token.rootType) }
        let manager = staged.removeValue(forKey: token.id) ?? PaneManager(rootType: token.rootType)
        entries.append(Entry(id: token.id, paneManager: manager, number: nextNumber))
        nextNumber += 1
        return manager
    }

    /// Stages a manager for a window about to open and returns the value to
    /// pass to openWindow.
    func stage(_ manager: PaneManager) -> WindowToken {
        let token = WindowToken(
            id: UUID(),
            rootType: manager.rootPane.isLeaf ? manager.rootPane.paneType : .aiAssistant)
        staged[token.id] = manager
        return token
    }

    func release(_ id: UUID) {
        released.insert(id)
        entries.removeAll { $0.id == id }
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
        FrameDestination(
            id: entry.id,
            title: title ?? (entry.number == 1 ? "Main Window" : "Window \(entry.number)"),
            paneManager: entry.paneManager)
    }
}
