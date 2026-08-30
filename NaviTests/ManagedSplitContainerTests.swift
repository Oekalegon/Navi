//
//  ManagedSplitContainerTests.swift
//  NaviTests
//

import Testing
import AppKit
@testable import Navi

// NAVI-65: moving a pane to sit beside its own current sibling flips that group's `direction` on
// the SAME SplitPane object (its id doesn't change) -- SwiftUI therefore reuses the existing
// ManagedSplitContainer NSView rather than tearing it down via makeNSView, so `updateNSView` (and
// the updateOrientation(isHorizontal:) it now calls) is the only place left to apply the new
// axis. Before the fix, updateNSView was a no-op: the model's `direction` flipped correctly but
// the underlying NSSplitView silently kept its old orientation forever, so "Left of X" visually
// stacked panes vertically instead of placing them side by side.
@MainActor
struct ManagedSplitContainerTests {

    @Test func initialOrientationMatchesConstructorArgument() {
        let pane = SplitPane(type: .archiveViewer)
        let container = ManagedSplitContainer(pane: pane, paneManager: PaneManager(), isHorizontal: true)
        #expect(container.splitView.isVertical == true)
    }

    @Test func updateOrientationFlipsTheUnderlyingSplitView() {
        let pane = SplitPane(type: .archiveViewer)
        let container = ManagedSplitContainer(pane: pane, paneManager: PaneManager(), isHorizontal: false)
        #expect(container.splitView.isVertical == false)

        container.updateOrientation(isHorizontal: true)
        #expect(container.splitView.isVertical == true)

        container.updateOrientation(isHorizontal: false)
        #expect(container.splitView.isVertical == false)
    }

    @Test func updateOrientationWithTheSameValueIsANoOp() {
        let pane = SplitPane(type: .archiveViewer)
        let container = ManagedSplitContainer(pane: pane, paneManager: PaneManager(), isHorizontal: true)
        container.updateOrientation(isHorizontal: true)
        #expect(container.splitView.isVertical == true)
    }
}
