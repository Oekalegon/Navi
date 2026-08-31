//
//  WindowRegistryTests.swift
//  NaviTests
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import Testing
import Foundation
@testable import Navi

// NAVI-10: detaching panes into new windows and routing archive selections
// across windows (windows without an archive pane follow the primary archive;
// ambiguous FITS destinations are returned for the user to pick).
@MainActor
struct WindowRegistryTests {

    // A manager whose root splits horizontally into one leaf per type.
    private func makeManager(_ types: [PaneType]) -> PaneManager {
        let manager = PaneManager(rootType: types[0])
        for type in types.dropFirst() {
            manager.insertPane(type, at: manager.rootPane, direction: .horizontal, before: false)
        }
        return manager
    }

    @discardableResult
    private func register(_ manager: PaneManager, in registry: WindowRegistry) -> WindowToken {
        let token = registry.stage(manager)
        _ = registry.adopt(token)
        return token
    }

    private let frameURL = URL(fileURLWithPath: "/tmp/frame.fits")

    // MARK: Detach

    @Test func detachCarriesFITSContentAndCollapsesTree() {
        let manager = makeManager([.aiAssistant, .fitsViewer])
        manager.fitsURL = frameURL
        manager.fitsFrameRejected = true
        let fits = manager.findPane(ofType: .fitsViewer, in: manager.rootPane)!

        let detached = manager.detachPaneManager(for: fits)

        #expect(detached != nil)
        #expect(detached?.rootPane.isLeaf == true)
        #expect(detached?.rootPane.paneType == .fitsViewer)
        #expect(detached?.fitsURL == frameURL)
        #expect(detached?.fitsFrameRejected == true)
        #expect(manager.isFITSViewerVisible == false)
        #expect(manager.rootPane.isLeaf && manager.rootPane.paneType == .aiAssistant)
    }

    @Test func detachCarriesArchiveContent() {
        let manager = makeManager([.aiAssistant, .archiveViewer])
        var filter = ArchiveFilter()
        filter.types = ["light"]
        manager.archiveFilter = filter
        let archive = manager.findPane(ofType: .archiveViewer, in: manager.rootPane)!

        let detached = manager.detachPaneManager(for: archive)

        #expect(detached?.rootPane.paneType == .archiveViewer)
        #expect(detached?.archiveFilter == filter)
    }

    @Test func lastPaneCannotDetach() {
        let manager = makeManager([.aiAssistant])
        #expect(manager.detachPaneManager(for: manager.rootPane) == nil)
    }

    // MARK: Selection routing

    @Test func selectionStaysWithinSelfContainedWindow() {
        let registry = WindowRegistry()
        let main = makeManager([.archiveViewer, .fitsViewer, .infoPanel])
        register(main, in: registry)

        let candidates = registry.showFrame(url: frameURL, from: main)

        #expect(candidates.isEmpty)
        #expect(main.fitsURL == frameURL)
        #expect(main.infoURL == frameURL)
    }

    @Test func windowWithoutArchiveFollowsPrimaryArchive() {
        let registry = WindowRegistry()
        let main = makeManager([.aiAssistant, .archiveViewer])
        let detachedViewer = makeManager([.fitsViewer, .infoPanel])
        register(main, in: registry)
        register(detachedViewer, in: registry)

        let candidates = registry.showFrame(url: frameURL, from: main)

        #expect(candidates.isEmpty)
        #expect(detachedViewer.fitsURL == frameURL)
        #expect(detachedViewer.infoURL == frameURL)
    }

    @Test func windowWithOwnArchiveDoesNotFollowMain() {
        let registry = WindowRegistry()
        let main = makeManager([.archiveViewer, .fitsViewer])
        let other = makeManager([.archiveViewer, .fitsViewer])
        register(main, in: registry)
        register(other, in: registry)

        _ = registry.showFrame(url: frameURL, from: main)
        #expect(main.fitsURL == frameURL)
        #expect(other.fitsURL == nil)

        // The other window's own archive pane drives its viewer, even though
        // it is not the primary archive.
        let otherURL = URL(fileURLWithPath: "/tmp/other.fits")
        let candidates = registry.showFrame(url: otherURL, from: other)
        #expect(candidates.isEmpty)
        #expect(other.fitsURL == otherURL)
        #expect(main.fitsURL == frameURL)
    }

    @Test func ambiguousFITSDestinationsAreReturnedUnshown() {
        let registry = WindowRegistry()
        let main = makeManager([.archiveViewer, .fitsViewer])
        let detachedViewer = makeManager([.fitsViewer])
        register(main, in: registry)
        register(detachedViewer, in: registry)

        let candidates = registry.showFrame(url: frameURL, from: main)

        #expect(candidates.count == 2)
        #expect(candidates.first?.title == "This Window")
        #expect(candidates.last?.title == "Window 2")
        #expect(main.fitsURL == nil)
        #expect(detachedViewer.fitsURL == nil)
    }

    // MARK: Window lifecycle

    @Test func releasedWindowStopsReceivingRoutedFrames() {
        let registry = WindowRegistry()
        let main = makeManager([.aiAssistant, .archiveViewer])
        let follower = makeManager([.fitsViewer])
        register(main, in: registry)
        let followerID = register(follower, in: registry)

        registry.release(followerID.id)
        let candidates = registry.showFrame(url: frameURL, from: main)

        #expect(candidates.isEmpty)
        #expect(follower.fitsURL == nil)
    }

    // A root view re-initialized during window teardown must not resurrect the
    // window as a zombie routing destination.
    @Test func releasedIDCannotBeReAdopted() {
        let registry = WindowRegistry()
        let manager = makeManager([.fitsViewer])
        let token = register(manager, in: registry)
        registry.release(token.id)

        let readopted = registry.adopt(token)

        #expect(readopted !== manager)
        #expect(registry.entries.isEmpty)
    }

    // After the main window closes, the oldest remaining window takes over
    // main-window behaviour, so destination titles must call it "Main Window"
    // (not its original "Window N").
    @Test func oldestRemainingWindowIsTitledMainAfterMainCloses() {
        let registry = WindowRegistry()
        let original = makeManager([.archiveViewer, .fitsViewer])
        let viewer = makeManager([.fitsViewer])
        let archive = makeManager([.archiveViewer, .fitsViewer])
        let originalToken = register(original, in: registry)
        register(viewer, in: registry)
        register(archive, in: registry)

        registry.release(originalToken.id)
        // The third window now holds the primary archive; the second is the
        // oldest remaining window and follows it.
        let candidates = registry.showFrame(url: frameURL, from: archive)

        #expect(candidates.count == 2)
        #expect(candidates.first?.title == "This Window")
        #expect(candidates.last?.title == "Main Window")
    }

    // Window restoration after relaunch: the staged manager is gone, but the
    // token's root pane type survives, so a detached FITS-viewer window
    // reopens as a FITS viewer instead of a default AI-assistant window.
    @Test func restoredTokenFallsBackToRootType() {
        let registry = WindowRegistry()
        let restored = WindowToken(id: UUID(), rootType: .fitsViewer)

        let manager = registry.adopt(restored)

        #expect(manager.rootPane.isLeaf)
        #expect(manager.rootPane.paneType == .fitsViewer)
    }

    @Test func stagedTokenCarriesDetachedPaneType() {
        let manager = makeManager([.aiAssistant, .infoPanel])
        let info = manager.findPane(ofType: .infoPanel, in: manager.rootPane)!
        let detached = manager.detachPaneManager(for: info)!

        let token = WindowRegistry().stage(detached)

        #expect(token.rootType == .infoPanel)
    }

    @Test func rejectionSyncsToAllWindowsShowingTheFrame() {
        let registry = WindowRegistry()
        let main = makeManager([.archiveViewer, .fitsViewer])
        let follower = makeManager([.fitsViewer])
        let unrelated = makeManager([.fitsViewer])
        register(main, in: registry)
        register(follower, in: registry)
        register(unrelated, in: registry)
        main.fitsURL = frameURL
        follower.fitsURL = frameURL
        unrelated.fitsURL = URL(fileURLWithPath: "/tmp/other.fits")

        registry.frameRejectionChanged(path: frameURL.path, rejected: true)

        #expect(main.fitsFrameRejected == true)
        #expect(follower.fitsFrameRejected == true)
        #expect(unrelated.fitsFrameRejected == false)
    }

    @Test func mainWindowLosesArchiveToDetachedWindow() {
        let registry = WindowRegistry()
        let main = makeManager([.aiAssistant, .archiveViewer, .fitsViewer])
        register(main, in: registry)
        let archive = main.findPane(ofType: .archiveViewer, in: main.rootPane)!
        let detached = main.detachPaneManager(for: archive)!
        register(detached, in: registry)

        // The detached archive is now the primary one; the main window has no
        // archive pane of its own, so its FITS viewer follows the detached one.
        #expect(registry.primaryArchiveManager === detached)
        let candidates = registry.showFrame(url: frameURL, from: detached)
        #expect(candidates.isEmpty)
        #expect(main.fitsURL == frameURL)
    }

    // MARK: Window-level tab tracking (NAVI-70)

    @Test func adoptWindowIsIdempotent() {
        let registry = WindowRegistry()
        let group = WindowTabGroup.blank(name: "A")

        let first = registry.adoptWindow(group)
        let second = registry.adoptWindow(group)

        #expect(first === second)
    }

    @Test func otherWindowsExcludesSelfAndLabelsTheOldestMain() {
        let registry = WindowRegistry()
        let main = WindowTabGroup.blank(name: "Telescope Control")
        let secondary = WindowTabGroup.blank(name: "Post-Processing")
        _ = registry.adoptWindow(main)
        _ = registry.adoptWindow(secondary)

        let fromMain = registry.otherWindows(excluding: main.id)
        let fromSecondary = registry.otherWindows(excluding: secondary.id)

        #expect(fromMain.map(\.title) == ["Post-Processing"])
        #expect(fromSecondary.map(\.title) == ["Main Window"])
    }

    @Test func moveTabRelocatesBetweenWindowsAndSelectsItThere() {
        let registry = WindowRegistry()
        var sourceGroup = WindowTabGroup.blank(name: "A")
        let movingTabID = sourceGroup.addingTab(name: "B")
        let destGroup = WindowTabGroup.blank(name: "C")
        let source = registry.adoptWindow(sourceGroup)
        let destination = registry.adoptWindow(destGroup)

        let moved = registry.moveTab(TabDescriptor(id: movingTabID, name: "B"), toWindow: destGroup.id)

        #expect(moved)
        #expect(source.group.tabs.map(\.id) == [sourceGroup.tabs[0].id])
        #expect(destination.group.tabs.map(\.id) == [destGroup.tabs[0].id, movingTabID])
        #expect(destination.group.selectedTabID == movingTabID)
    }

    @Test func moveTabRefusesToEmptyAWindowsLastTab() {
        let registry = WindowRegistry()
        let sourceGroup = WindowTabGroup.blank(name: "Only")
        let destGroup = WindowTabGroup.blank(name: "Other")
        let source = registry.adoptWindow(sourceGroup)
        let destination = registry.adoptWindow(destGroup)

        let moved = registry.moveTab(sourceGroup.tabs[0], toWindow: destGroup.id)

        #expect(!moved)
        #expect(source.group.tabs.count == 1)
        #expect(destination.group.tabs.map(\.id) == [destGroup.tabs[0].id])
    }

    @Test func moveTabRefusesAnUnknownDestination() {
        let registry = WindowRegistry()
        var sourceGroup = WindowTabGroup.blank(name: "A")
        let movingTabID = sourceGroup.addingTab(name: "B")
        let source = registry.adoptWindow(sourceGroup)

        let moved = registry.moveTab(TabDescriptor(id: movingTabID, name: "B"), toWindow: UUID())

        #expect(!moved)
        #expect(source.group.tabs.count == 2)
    }

    @Test func releaseWindowRemovesItFromOtherWindows() {
        let registry = WindowRegistry()
        let main = WindowTabGroup.blank(name: "A")
        let secondary = WindowTabGroup.blank(name: "B")
        _ = registry.adoptWindow(main)
        _ = registry.adoptWindow(secondary)

        registry.releaseWindow(secondary.id)

        #expect(registry.otherWindows(excluding: main.id).isEmpty)
    }

    @Test func launchWindowRestorationGateFiresOnlyOnce() {
        let registry = WindowRegistry()

        #expect(registry.beginLaunchWindowRestorationIfNeeded())
        #expect(!registry.beginLaunchWindowRestorationIfNeeded())
    }
}
