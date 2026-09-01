//
//  CaptureImportPlanning.swift
//  Navi
//
//  Pure logic for NAVI-52's frame download/archive-import pipeline, kept separate from
//  CaptureImportManager's async orchestration so it's unit-testable without a live server —
//  same "extract the pure logic, test it directly" convention as TelescopeMessageFilter/
//  WindowTabGroup. See docs/design/INDI-MCP-Integration.md §5, I-2.
//

import Foundation
import AstrophotoArchiveKit
import INDIMCPKit

enum CaptureImportPlanning {
    /// Frames Navi itself is responsible for: `listFrames(transferred: false)` returns every
    /// outstanding frame on the server regardless of which client requested it, so this is the
    /// one place that narrows it down to `myRunIDs` — frames Navi's own `CaptureRunTracker`
    /// recorded starting. A frame with no `runId` (never run through a script) is never Navi's.
    static func relevantFrames(_ frames: [FrameMetadataResponse], myRunIDs: Set<String>) -> [FrameMetadataResponse] {
        frames.filter { frame in
            guard let runId = frame.runId else { return false }
            return myRunIDs.contains(runId)
        }
    }

    /// Where a downloaded frame lands under the archive root: grouped by local capture date, so a
    /// night's captures sit together the way most astro tools organize by night. Falls back to
    /// `"unknown-date"` rather than throwing if `capturedAt` doesn't parse — a naming detail, not
    /// a reason to fail the whole download.
    static func localDestination(for frame: FrameMetadataResponse, archiveRoot: URL) -> URL {
        let dateFolder = ISO8601DateFormatter().date(from: frame.capturedAt).map(Self.dayFolderFormatter.string(from:))
            ?? "unknown-date"
        return archiveRoot
            .appendingPathComponent("Captures", isDirectory: true)
            .appendingPathComponent(dateFolder, isDirectory: true)
            .appendingPathComponent(frame.suggestedLocalFilename)
    }

    /// The best-effort query used to seed a new frameset for one capture run's frames — narrow
    /// enough to very likely match nothing but this run in practice (frame type + camera + a
    /// tight window around the run's own capturedAt span), but doesn't need to be exact: the
    /// caller reconciles final membership to the exact accumulated frame ids afterward regardless
    /// (`archive_frameset_add`'s explicit `frame_ids` list + removing anything extra), so an
    /// over-matching query here is harmless, not a correctness risk.
    static func frameSetQuery(for frames: [ArchivedFrame]) -> FrameQuery? {
        guard let first = frames.first else { return nil }
        var query = FrameQuery()
        query.frameTypes = [first.frameType]
        query.camera = first.camera
        let timestamps = frames.compactMap(\.timestamp)
        if let earliest = timestamps.min(), let latest = timestamps.max() {
            query.dateRange = DateInterval(start: earliest.addingTimeInterval(-1), end: latest.addingTimeInterval(1))
        }
        return query
    }

    /// A readable frameset name derived from the run's own frames — object name + frame type +
    /// capture date, whatever's actually available.
    static func frameSetName(for frame: ArchivedFrame) -> String {
        let dateText = frame.timestamp.map(Self.displayDateFormatter.string(from:))
        let parts = [frame.objectName, frame.frameType, dateText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Capture" : parts.joined(separator: " ")
    }

    /// Members `archive_frameset_create`'s best-effort query pulled in that aren't actually part
    /// of this run's exact frame set — reconciled away by the caller via `removeFrames`.
    static func extraMemberIDs(current: [UUID], exact: Set<UUID>) -> [UUID] {
        current.filter { !exact.contains($0) }
    }

    private static let dayFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
