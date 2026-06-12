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

    private func register(_ manager: PaneManager, in registry: WindowRegistry) {
        _ = registry.adopt(registry.stage(manager))
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
}
