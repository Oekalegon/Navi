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
    var focusedPaneID: UUID? = nil

    init() {
        let aiPane = SplitPane(type: .aiAssistant)
        aiPane.preferredWidth = 300

        let emptyPane = SplitPane(type: .empty)

        self.rootPane = SplitPane(type: .empty)
        self.rootPane.direction = .horizontal
        self.rootPane.children = [aiPane, emptyPane]
    }

    func findPane(ofType type: PaneType, in pane: SplitPane) -> SplitPane? {
        if pane.isLeaf { return pane.paneType == type ? pane : nil }
        return pane.children?.compactMap { findPane(ofType: type, in: $0) }.first
    }

    func splitPane(_ pane: SplitPane, direction: SplitDirection,
                   newPaneType: PaneType,
                   newPanePreferredWidth: CGFloat? = nil,
                   newPanePreferredHeight: CGFloat? = nil,
                   prepend: Bool = false) {
        guard pane.children == nil else { return }
        pane.direction = direction
        let existing = SplitPane(type: pane.paneType)
        existing.preferredWidth = pane.preferredWidth
        existing.preferredHeight = pane.preferredHeight
        let newPane = SplitPane(type: newPaneType)
        newPane.preferredWidth = newPanePreferredWidth
        newPane.preferredHeight = newPanePreferredHeight
        pane.children = prepend ? [newPane, existing] : [existing, newPane]
        pane.paneType = .empty
        pane.preferredWidth = nil
        pane.preferredHeight = nil
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
            removeFITSViewer()
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
            splitPane(ai, direction: .horizontal, newPaneType: .fitsViewer)
        }
    }

    private func removeFITSViewer() {
        if rootPane.isLeaf && rootPane.paneType == .fitsViewer {
            rootPane.paneType = .empty
            return
        }
        guard let (parent, index) = findParentOf(type: .fitsViewer, in: rootPane),
              let children = parent.children, children.count == 2 else { return }
        let sibling = children[1 - index]
        parent.paneType = sibling.paneType
        parent.direction = sibling.direction
        parent.children = sibling.children
        parent.preferredWidth = sibling.preferredWidth
        parent.preferredHeight = sibling.preferredHeight
    }

    private func findParentOf(type: PaneType, in pane: SplitPane) -> (SplitPane, Int)? {
        guard let children = pane.children else { return nil }
        for (index, child) in children.enumerated() {
            if child.isLeaf && child.paneType == type { return (pane, index) }
            if let result = findParentOf(type: type, in: child) { return result }
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
