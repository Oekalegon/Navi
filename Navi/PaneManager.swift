//
//  PaneManager.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import Observation

@Observable
class PaneManager {
    var rootPane: SplitPane
    var archiveContent: ArchiveViewerContent?
    var archiveFilter: ArchiveFilter = ArchiveFilter()
    private var archiveBackStack: [ArchiveNavState] = []
    private var archiveForwardStack: [ArchiveNavState] = []
    var canGoBack: Bool { !archiveBackStack.isEmpty }
    var canGoForward: Bool { !archiveForwardStack.isEmpty }
    var fitsURL: URL?
    var fitsFrameRejected: Bool = false
    var infoURL: URL?
    var focusedPaneID: UUID? = nil

    // Live pane-frame providers, registered by each pane's FocusTrackerView and
    // keyed by tracker identity so a transient duplicate tracker for the same
    // pane can never clobber the live one. Frames are queried on demand (when
    // the move-pane menu opens) because cached frames go stale when an outer
    // divider moves without resizing the inner hosting view.
    @ObservationIgnored var paneFrameProviders: [ObjectIdentifier: () -> (UUID, CGRect)?] = [:]

    // Current frame of every laid-out leaf pane, in window coordinates (y-up).
    func currentPaneFrames() -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for provider in paneFrameProviders.values {
            if let (id, rect) = provider() { frames[id] = rect }
        }
        return frames
    }

    init(rootType: PaneType = .aiAssistant) {
        self.rootPane = SplitPane(type: rootType)
    }

    func findPane(ofType type: PaneType, in pane: SplitPane) -> SplitPane? {
        if pane.isLeaf { return pane.paneType == type ? pane : nil }
        return pane.children?.compactMap { findPane(ofType: type, in: $0) }.first
    }

    func findPane(id: UUID, in pane: SplitPane) -> SplitPane? {
        if pane.id == id { return pane }
        return pane.children?.compactMap { findPane(id: id, in: $0) }.first
    }

    func splitPane(_ pane: SplitPane, direction: SplitDirection,
                   newPaneType: PaneType,
                   newPanePreferredWidth: CGFloat? = nil,
                   newPanePreferredHeight: CGFloat? = nil,
                   prepend: Bool = false) {
        guard pane.children == nil else { return }
        insertPane(newPaneType, at: pane, direction: direction, before: prepend,
                   preferredWidth: newPanePreferredWidth,
                   preferredHeight: newPanePreferredHeight)
    }

    // Splits `node` (leaf or split) in `direction`, pushing its current content
    // down into one child and placing a new leaf of `type` on the other side.
    @discardableResult
    func insertPane(_ type: PaneType, at node: SplitPane,
                    direction: SplitDirection, before: Bool,
                    preferredWidth: CGFloat? = nil,
                    preferredHeight: CGFloat? = nil) -> SplitPane {
        let existing = SplitPane(type: node.paneType)
        existing.direction = node.direction
        existing.children = node.children
        existing.preferredWidth = node.preferredWidth
        existing.preferredHeight = node.preferredHeight
        let newPane = SplitPane(type: type)
        newPane.preferredWidth = preferredWidth
        newPane.preferredHeight = preferredHeight
        node.paneType = .empty
        node.direction = direction
        node.children = before ? [newPane, existing] : [existing, newPane]
        node.preferredWidth = nil
        node.preferredHeight = nil
        return newPane
    }

    func showContent(type: PaneType, splitFrom sourcePane: SplitPane, direction: SplitDirection) {
        if let existing = findPane(ofType: type, in: rootPane) {
            existing.paneType = type
        } else {
            splitPane(sourcePane, direction: direction, newPaneType: type)
        }
    }

    // Archive viewer prefers a wide/horizontal layout: find the widest leaf and split it
    // vertically (top/bottom) so the archive takes the full available width.
    func showArchivePane() {
        if findPane(ofType: .archiveViewer, in: rootPane) != nil { return }
        guard let target = widestLeafPane(in: rootPane) else { return }
        if target.paneType == .empty {
            target.paneType = .archiveViewer
        } else if target.paneType == .aiAssistant {
            // Never stack below the assistant column: pin it to 300pt on the
            // left and give the archive the remaining width.
            target.preferredWidth = 300
            splitPane(target, direction: .horizontal, newPaneType: .archiveViewer)
        } else {
            splitPane(target, direction: .vertical, newPaneType: .archiveViewer)
        }
    }

    func navigateArchiveTo(content: ArchiveViewerContent?, filter: ArchiveFilter = ArchiveFilter()) {
        if archiveContent != nil || archiveFilter.isActive {
            archiveBackStack.append(ArchiveNavState(content: archiveContent, filter: archiveFilter))
            archiveForwardStack.removeAll()
        }
        archiveContent = content
        archiveFilter = filter
    }

    func archiveBack() {
        guard let prev = archiveBackStack.popLast() else { return }
        archiveForwardStack.append(ArchiveNavState(content: archiveContent, filter: archiveFilter))
        archiveContent = prev.content
        archiveFilter = prev.filter
    }

    func archiveForward() {
        guard let next = archiveForwardStack.popLast() else { return }
        archiveBackStack.append(ArchiveNavState(content: archiveContent, filter: archiveFilter))
        archiveContent = next.content
        archiveFilter = next.filter
    }

    func setArchiveFilter(_ filter: ArchiveFilter) {
        guard filter != archiveFilter else { return }
        archiveBackStack.append(ArchiveNavState(content: archiveContent, filter: archiveFilter))
        archiveForwardStack.removeAll()
        archiveFilter = filter
    }

    func showArchiveViewer(content: ArchiveViewerContent, filter: ArchiveFilter = ArchiveFilter()) {
        navigateArchiveTo(content: content, filter: filter)
        showArchivePane()
    }

    var isFITSViewerVisible: Bool {
        findPane(ofType: .fitsViewer, in: rootPane) != nil
    }

    var isAIAssistantVisible: Bool {
        findPane(ofType: .aiAssistant, in: rootPane) != nil
    }

    var isArchiveViewerVisible: Bool {
        findPane(ofType: .archiveViewer, in: rootPane) != nil
    }

    func toggleAIAssistant() {
        if isAIAssistantVisible {
            closePane(ofType: .aiAssistant)
        } else {
            openAIAssistantPane()
        }
    }

    func toggleArchiveViewer() {
        if isArchiveViewerVisible {
            closePane(ofType: .archiveViewer)
        } else {
            showArchivePane()
        }
    }

    // Close the pane showing `type`; its sibling takes over the freed space.
    func closePane(ofType type: PaneType) {
        guard type != .empty,
              let pane = findPane(ofType: type, in: rootPane) else { return }
        removeLeaf(pane)
    }

    // Remove a leaf from the tree; its sibling takes over the freed space.
    func removeLeaf(_ leaf: SplitPane) {
        if rootPane === leaf {
            rootPane.paneType = .empty
            return
        }
        guard leaf.isLeaf,
              let (parent, index) = findParent(of: leaf, in: rootPane),
              let children = parent.children, children.count == 2 else { return }
        let sibling = children[1 - index]
        parent.paneType = sibling.paneType
        parent.direction = sibling.direction
        parent.children = sibling.children
        parent.preferredWidth = sibling.preferredWidth
        parent.preferredHeight = sibling.preferredHeight
        // Both leaf IDs disappear in the collapse (sibling's content is copied
        // onto the parent node), so any focus pointing at them is stale.
        if focusedPaneID == leaf.id || focusedPaneID == sibling.id {
            focusedPaneID = nil
        }
    }

    // Exchange the contents of two leaves; geometry stays with the position.
    func swapPanes(_ a: SplitPane, _ b: SplitPane) {
        guard a.isLeaf, b.isLeaf, a !== b else { return }
        let type = a.paneType
        a.paneType = b.paneType
        b.paneType = type
        // Focus follows the content to its new position.
        if focusedPaneID == a.id {
            focusedPaneID = b.id
        } else if focusedPaneID == b.id {
            focusedPaneID = a.id
        }
    }

    // Move a leaf to a new position: remove it (sibling absorbs the space),
    // then split the target node and place the pane on the chosen side.
    func movePane(_ leaf: SplitPane, toTarget targetID: UUID,
                  direction: SplitDirection, before: Bool) {
        guard leaf.isLeaf,
              let (parent, index) = findParent(of: leaf, in: rootPane),
              let children = parent.children, children.count == 2,
              let preTarget = findPane(id: targetID, in: rootPane),
              preTarget !== leaf else { return }
        let sibling = children[1 - index]
        let type = leaf.paneType
        let width = leaf.preferredWidth
        let height = leaf.preferredHeight
        removeLeaf(leaf)
        // The sibling node is absorbed into the parent during removal, so a
        // move targeting the sibling must re-target the parent.
        let target = preTarget === sibling ? parent : preTarget
        let newLeaf = insertPane(type, at: target, direction: direction, before: before,
                                 preferredWidth: width, preferredHeight: height)
        focusedPaneID = newLeaf.id
    }

    // Remove a leaf and build the PaneManager for a new window showing it,
    // carrying over the data its content needs (NAVI-10). The remaining tree
    // collapses as in removeLeaf; the last pane in a window cannot detach.
    func detachPaneManager(for leaf: SplitPane) -> PaneManager? {
        guard leaf.isLeaf, leaf.paneType != .empty, rootPane !== leaf,
              findParent(of: leaf, in: rootPane) != nil else { return nil }
        let manager = PaneManager(rootType: leaf.paneType)
        switch leaf.paneType {
        case .fitsViewer:
            manager.fitsURL = fitsURL
            manager.fitsFrameRejected = fitsFrameRejected
        case .infoPanel:
            manager.infoURL = infoURL
        case .archiveViewer:
            manager.archiveContent = archiveContent
            manager.archiveFilter = archiveFilter
        case .aiAssistant, .empty:
            break
        }
        removeLeaf(leaf)
        return manager
    }

    // AI assistant prefers the left edge: reuse an empty pane if available,
    // otherwise wrap the whole tree so AI sits to the left of everything.
    private func openAIAssistantPane() {
        if findPane(ofType: .aiAssistant, in: rootPane) != nil { return }
        if let empty = findPane(ofType: .empty, in: rootPane) {
            empty.paneType = .aiAssistant
            return
        }
        insertPane(.aiAssistant, at: rootPane, direction: .horizontal, before: true,
                   preferredWidth: 300)
    }

    var isInfoPanelVisible: Bool {
        findPane(ofType: .infoPanel, in: rootPane) != nil
    }

    func toggleInfoPanel(url: URL? = nil) {
        if isInfoPanelVisible {
            closePane(ofType: .infoPanel)
        } else {
            if let url { infoURL = url }
            openInfoPane()
        }
    }

    func showInfoIfVisible(url: URL) {
        guard isInfoPanelVisible else { return }
        infoURL = url
    }

    // Info panel is a tall column at the right edge: reuse an empty pane if
    // available, otherwise wrap the whole tree so it sits right of everything.
    private func openInfoPane() {
        if findPane(ofType: .infoPanel, in: rootPane) != nil { return }
        if let empty = findPane(ofType: .empty, in: rootPane) {
            empty.paneType = .infoPanel
            return
        }
        insertPane(.infoPanel, at: rootPane, direction: .horizontal, before: false,
                   preferredWidth: 300)
    }

    // FITS viewer splits the archive viewer vertically with FITS on top.
    // Falls back to an empty pane or a horizontal split of the AI pane.
    func showFITSViewer(url: URL) {
        fitsURL = url
        if findPane(ofType: .fitsViewer, in: rootPane) != nil { return }
        openFITSViewerPane()
    }

    func showFITSViewerIfVisible(url: URL) {
        guard isFITSViewerVisible else { return }
        fitsURL = url
    }

    func toggleFITSViewer() {
        if isFITSViewerVisible {
            closePane(ofType: .fitsViewer)
        } else {
            openFITSViewerPane()
        }
    }

    private func openFITSViewerPane() {
        if let archive = findPane(ofType: .archiveViewer, in: rootPane) {
            splitPane(archive, direction: .vertical, newPaneType: .fitsViewer, prepend: true)
        } else if let empty = findPane(ofType: .empty, in: rootPane) {
            empty.paneType = .fitsViewer
        } else if let ai = findPane(ofType: .aiAssistant, in: rootPane) {
            ai.preferredWidth = 300
            splitPane(ai, direction: .horizontal, newPaneType: .fitsViewer)
        }
    }

    private func findParent(of node: SplitPane, in pane: SplitPane) -> (SplitPane, Int)? {
        guard let children = pane.children else { return nil }
        for (index, child) in children.enumerated() {
            if child === node { return (pane, index) }
            if let result = findParent(of: node, in: child) { return result }
        }
        return nil
    }

    // Widest leaf: nil preferredWidth sorts last (treated as ∞ — takes remaining space).
    private func widestLeafPane(in pane: SplitPane) -> SplitPane? {
        if pane.isLeaf { return pane }
        return pane.children?
            .compactMap { widestLeafPane(in: $0) }
            .max { ($0.preferredWidth ?? .greatestFiniteMagnitude) < ($1.preferredWidth ?? .greatestFiniteMagnitude) }
    }

    // Tallest leaf: nil preferredHeight sorts last (treated as ∞ — takes remaining space).
    private func tallestLeafPane(in pane: SplitPane) -> SplitPane? {
        if pane.isLeaf { return pane }
        return pane.children?
            .compactMap { tallestLeafPane(in: $0) }
            .max { ($0.preferredHeight ?? .greatestFiniteMagnitude) < ($1.preferredHeight ?? .greatestFiniteMagnitude) }
    }
}

private struct ArchiveNavState {
    var content: ArchiveViewerContent?
    var filter: ArchiveFilter
}
