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
    var fitsURL: URL?

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
                   newPaneType: PaneType, newPanePreferredWidth: CGFloat? = nil) {
        guard pane.children == nil else { return }
        pane.direction = direction
        let existing = SplitPane(type: pane.paneType)
        existing.preferredWidth = pane.preferredWidth
        let newPane = SplitPane(type: newPaneType)
        newPane.preferredWidth = newPanePreferredWidth
        pane.children = [existing, newPane]
        pane.paneType = .empty
        pane.preferredWidth = nil
    }

    func showContent(type: PaneType, splitFrom sourcePane: SplitPane, direction: SplitDirection) {
        if let existing = findPane(ofType: type, in: rootPane) {
            existing.paneType = type
        } else {
            splitPane(sourcePane, direction: direction, newPaneType: type)
        }
    }

    func showArchiveViewer(content: ArchiveViewerContent) {
        archiveContent = content
        if findPane(ofType: .archiveViewer, in: rootPane) != nil { return }
        if let empty = findPane(ofType: .empty, in: rootPane) {
            empty.paneType = .archiveViewer
            empty.preferredWidth = 500
        } else if let ai = findPane(ofType: .aiAssistant, in: rootPane) {
            splitPane(ai, direction: .horizontal, newPaneType: .archiveViewer, newPanePreferredWidth: 500)
        }
    }

    func showFITSViewer(url: URL) {
        fitsURL = url
        if findPane(ofType: .fitsViewer, in: rootPane) != nil { return }
        if let empty = findPane(ofType: .empty, in: rootPane) {
            empty.paneType = .fitsViewer
        } else if let ai = findPane(ofType: .aiAssistant, in: rootPane) {
            splitPane(ai, direction: .horizontal, newPaneType: .fitsViewer)
        }
    }
}
