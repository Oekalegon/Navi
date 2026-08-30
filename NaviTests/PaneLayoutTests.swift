//
//  PaneLayoutTests.swift
//  NaviTests
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import Testing
import Foundation
import CoreGraphics
@testable import Navi

// The worked example from NAVI-9: a horizontal split with Y (preferred width,
// like the AI pane) on the left third and the right two thirds split
// vertically into X1 over X2. Moving Y must offer 2 swaps and 5 new positions.
struct PaneLayoutTests {

    private struct Fixture {
        let manager: PaneManager
        let y: SplitPane
        let x1: SplitPane
        let x2: SplitPane
        let s: SplitPane
        let frames: [UUID: CGRect]
    }

    private func makeFixture() -> Fixture {
        let manager = PaneManager()
        let y = SplitPane(type: .aiAssistant)
        y.preferredWidth = 300
        let x1 = SplitPane(type: .fitsViewer)
        let x2 = SplitPane(type: .archiveViewer)
        let s = SplitPane(type: .empty)
        s.direction = .vertical
        s.children = [x1, x2]
        let root = SplitPane(type: .empty)
        root.direction = .horizontal
        root.children = [y, s]
        manager.rootPane = root
        // Window coordinates are y-up: X1 is the TOP-right pane.
        let frames: [UUID: CGRect] = [
            y.id: CGRect(x: 0, y: 0, width: 100, height: 300),
            x1.id: CGRect(x: 100, y: 150, width: 200, height: 150),
            x2.id: CGRect(x: 100, y: 0, width: 200, height: 150),
        ]
        return Fixture(manager: manager, y: y, x1: x1, x2: x2, s: s, frames: frames)
    }

    private func rectsEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.001) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    @Test func ticketExampleOffersTwoSwapsAndFiveInserts() throws {
        let f = makeFixture()
        let options = try #require(paneMoveOptions(for: f.y, root: f.manager.rootPane,
                                                   frames: f.frames))
        #expect(options.swaps.count == 2)
        #expect(options.inserts.count == 5)
        let titles = Set(options.inserts.map(\.title))
        #expect(titles == ["Left of FITS Viewer", "Right of FITS Viewer",
                           "Left of Archive", "Right of Archive", "Right of Window"])
        // The current position (left of the window) must not be offered.
        #expect(!titles.contains("Left of Window"))
    }

    @Test func snapshotNormalizesAndFlipsFrames() throws {
        let f = makeFixture()
        let options = try #require(paneMoveOptions(for: f.y, root: f.manager.rootPane,
                                                   frames: f.frames))
        // Y occupies the left third at full height.
        #expect(rectsEqual(options.currentRect, CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)))
        // X1 sits at the TOP in the y-down snapshot despite y-up window coords.
        // Swap icons show the current layout with both positions marked.
        let swapX1 = try #require(options.swaps.first { $0.title == "Swap with FITS Viewer" })
        #expect(rectsEqual(swapX1.destinationRect,
                           CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 0.5)))
        #expect(rectsEqual(try #require(swapX1.sourceRect), options.currentRect))
        // Insert icons preview the layout AFTER the move: Y's column is gone,
        // the X1/X2 group fills the window, and Y lands in the right half.
        let rightOfWindow = try #require(options.inserts.first { $0.title == "Right of Window" })
        #expect(rightOfWindow.sourceRect == nil)
        #expect(rectsEqual(rightOfWindow.destinationRect,
                           CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        #expect(rightOfWindow.leafRects.count == 3)
        // X1 is compressed into the top-left quarter of the post-move layout.
        #expect(rightOfWindow.leafRects.contains {
            rectsEqual($0, CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        })
    }

    @Test func paneWithoutPreferredSizeOffersBothDirections() throws {
        let f = makeFixture()
        f.y.preferredWidth = nil
        let options = try #require(paneMoveOptions(for: f.y, root: f.manager.rootPane,
                                                   frames: f.frames))
        // X1 and X2 contribute 4 sides each, the sibling group 3 (its left
        // side recreates the current position).
        #expect(options.inserts.count == 11)
    }

    @Test func missingFramesFallBackToEqualSplits() throws {
        let f = makeFixture()
        let options = try #require(paneMoveOptions(for: f.y, root: f.manager.rootPane,
                                                   frames: [:]))
        #expect(rectsEqual(options.currentRect, CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        #expect(options.swaps.count == 2)
        #expect(options.inserts.count == 5)
    }

    @Test func rootLeafHasNoMoveOptions() {
        let manager = PaneManager()
        manager.rootPane = SplitPane(type: .fitsViewer)
        #expect(paneMoveOptions(for: manager.rootPane, root: manager.rootPane,
                                frames: [:]) == nil)
    }

    // NAVI-39: AI/Info panes are added via direct N-ary append to rootPane.children
    // when the root is already a horizontal split. paneMoveOptions must not return
    // nil for panes whose parent has 3+ children.
    @Test func naryParentExposesMovePaneOptions() throws {
        let manager = PaneManager()
        let ai = SplitPane(type: .aiAssistant)
        ai.preferredWidth = 400
        let archive = SplitPane(type: .archiveViewer)
        let info = SplitPane(type: .infoPanel)
        info.preferredWidth = 400
        let root = manager.rootPane
        root.direction = .horizontal
        root.children = [ai, archive, info]

        // AI pane (index 0 of 3) must have move options.
        let aiOptions = try #require(paneMoveOptions(for: ai, root: root, frames: [:]))
        #expect(aiOptions.swaps.count == 2)
        let aiTitles = Set(aiOptions.inserts.map(\.title))
        #expect(!aiTitles.contains("Left of Archive"))   // current position — must be absent
        #expect(aiTitles.contains("Right of Archive"))
        #expect(aiTitles.contains("Left of Info"))

        // Info pane (index 2 of 3) must also have move options.
        let infoOptions = try #require(paneMoveOptions(for: info, root: root, frames: [:]))
        #expect(infoOptions.swaps.count == 2)
        let infoTitles = Set(infoOptions.inserts.map(\.title))
        #expect(!infoTitles.contains("Right of Archive"))  // current position — must be absent
        #expect(infoTitles.contains("Left of Archive"))
        #expect(infoTitles.contains("Left of AI Assistant"))
    }

    @Test func swapExchangesContentAndFocusFollows() {
        let f = makeFixture()
        f.manager.focusedPaneID = f.y.id
        f.manager.swapPanes(f.y, f.x2)
        #expect(f.y.paneType == .archiveViewer)
        #expect(f.x2.paneType == .aiAssistant)
        #expect(f.manager.focusedPaneID == f.x2.id)
    }

    @Test func movePaneToLeafSplitsTheLeaf() {
        let f = makeFixture()
        f.manager.movePane(f.y, toTarget: f.x2.id, direction: .horizontal, before: false)
        // Y removed: the root absorbs the vertical group; X2 then splits.
        let root = f.manager.rootPane
        #expect(root.direction == .vertical)
        #expect(root.children?.first === f.x1)
        #expect(f.x2.isLeaf == false)
        #expect(f.x2.direction == .horizontal)
        #expect(f.x2.children?[0].paneType == .archiveViewer)
        #expect(f.x2.children?[1].paneType == .aiAssistant)
        #expect(f.x2.children?[1].preferredWidth == 300)
        #expect(f.manager.focusedPaneID == f.x2.children?[1].id)
    }

    @Test func movePaneToAbsorbedSiblingRetargetsTheParent() {
        let f = makeFixture()
        f.manager.movePane(f.y, toTarget: f.s.id, direction: .horizontal, before: false)
        // The sibling group was absorbed into the root, so the move wraps the
        // whole remaining tree with Y on the right.
        let root = f.manager.rootPane
        #expect(root.direction == .horizontal)
        #expect(root.children?[0].direction == .vertical)
        #expect(root.children?[0].children?.first === f.x1)
        #expect(root.children?[1].paneType == .aiAssistant)
    }

    // NAVI-65: X1 and X2 are already siblings under S (vertical); moving X2 to be "Left of" X1
    // targets X1, which IS x2's sibling in a 2-child binary parent — the same
    // absorbed-sibling-retargets-the-parent redirect as the test above, but here the redirected
    // target (S) flips direction on the SAME SplitPane object rather than being freshly wrapped,
    // which is exactly the case that exposed the ManagedSplitContainer rendering bug (see
    // ManagedSplitContainerTests). This asserts the *model* was already correct even before that
    // fix — the bug was purely in the NSSplitView sync, never in this layout math.
    @Test func movePaneBesideItsOwnSiblingFlipsTheSharedGroupDirection() {
        let f = makeFixture()
        f.manager.movePane(f.x2, toTarget: f.x1.id, direction: .horizontal, before: true)
        // S is reused in place (same object, same id) — now a horizontal split with X2 first.
        #expect(f.s.direction == .horizontal)
        #expect(f.s.children?[0] === f.x2)
        #expect(f.s.children?[1].paneType == .fitsViewer)
        // Root's own shape (Y beside S) is untouched.
        #expect(f.manager.rootPane.direction == .horizontal)
        #expect(f.manager.rootPane.children?[0] === f.y)
        #expect(f.manager.rootPane.children?[1] === f.s)
    }

    @Test func closePaneStillCollapsesToSibling() {
        let manager = PaneManager()
        manager.closePane(ofType: .aiAssistant)
        #expect(manager.rootPane.isLeaf)
        #expect(manager.rootPane.paneType == .empty)
    }
}
