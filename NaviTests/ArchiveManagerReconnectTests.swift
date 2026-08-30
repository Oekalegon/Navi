//
//  ArchiveManagerReconnectTests.swift
//  NaviTests
//

import Testing
import Foundation
@testable import Navi

// NAVI-66: ArchiveManager self-observes SettingsManager.shared.archivePath so a Settings change
// reconnects the archive regardless of which panes are mounted -- previously this only happened
// inside AIAssistantView's .onAppear/.onChange, silently doing nothing if that pane wasn't open.
// Exercises the real withObservationTracking re-registration loop against real (throwaway,
// temp-directory) archive backends: Archive(configuration:) auto-creates any missing directory
// and its archive.db, so there's no lighter-weight seam to fake this through.
@MainActor
struct ArchiveManagerReconnectTests {

    @Test func reconnectsToANewPathAfterASettingsChange() async throws {
        let settings = SettingsManager.shared
        let originalPath = settings.archivePath
        let tempRoot = FileManager.default.temporaryDirectory
        let firstDir = tempRoot.appending(path: "NaviArchiveTest-\(UUID().uuidString)")
        let secondDir = tempRoot.appending(path: "NaviArchiveTest-\(UUID().uuidString)")
        defer {
            settings.archivePath = originalPath
            try? FileManager.default.removeItem(at: firstDir)
            try? FileManager.default.removeItem(at: secondDir)
        }

        settings.archivePath = firstDir.path
        try await waitUntil { FileManager.default.fileExists(atPath: firstDir.appendingPathComponent("archive.db").path) }
        #expect(ArchiveManager.shared.isConnected)

        // The re-registration loop must have fired again for this second change to take effect
        // -- if observeArchivePathChanges() forgot to re-arm itself inside onChange, this would
        // time out with secondDir's archive.db never appearing.
        settings.archivePath = secondDir.path
        try await waitUntil { FileManager.default.fileExists(atPath: secondDir.appendingPathComponent("archive.db").path) }
        #expect(ArchiveManager.shared.isConnected)
    }

    // withObservationTracking's onChange fires asynchronously relative to the mutation that
    // triggered it, so poll briefly rather than asserting immediately after setting archivePath.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { throw WaitTimeoutError() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private struct WaitTimeoutError: Error {}
}
