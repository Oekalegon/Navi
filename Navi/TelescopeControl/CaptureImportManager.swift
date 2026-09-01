//
//  CaptureImportManager.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §5, I-2. Downloads, verifies, and imports frames
//  Navi itself captured (CaptureRunTracker), grouping each run's frames into a frameset once
//  complete. Triggered on every successful connect and periodically while connected — never
//  relying on Navi having been online when a frame actually finished capturing, since the
//  telescope keeps shooting long after the user (and often Navi itself) has gone to sleep.
//
//  Owned once, the same way ArchiveManager/TelescopeSessionManager are.
//

import Foundation
import AstrophotoArchiveKit
import INDIMCPKit

@MainActor
final class CaptureImportManager {
    static let shared = CaptureImportManager()
    private init() {}

    // Being @MainActor only serializes access to actor state between await points — it does not
    // stop two calls to this same async method from interleaving while both are suspended on
    // network/disk I/O. Without this guard, the connect-triggered pass and the periodic 60s timer
    // (TelescopeSessionManager) could overlap on a slow download and race on downloading/importing
    // the same frame twice concurrently.
    private var isReconciling = false

    /// Catches up on every frame Navi is owed for `rig`: for each of its camera devices, asks the
    /// server what's still outstanding (`listFrames(transferred: false)` — durable, works
    /// regardless of whether Navi was connected when the frame finished), narrows that to frames
    /// this Navi instance actually captured (`CaptureImportPlanning.relevantFrames`), imports each,
    /// then finalizes any run that's now fully reconciled.
    func reconcile(rig: Rig, client: INDIMCPClient) async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let myRunIDs = CaptureRunTracker.runIDs(forRig: rig.id)
        guard !myRunIDs.isEmpty else { return }
        let cameraDevices = Set(rig.components.filter { $0.role == .camera }.compactMap(\.device))
        guard !cameraDevices.isEmpty else { return }

        for device in cameraDevices {
            let outstanding: [FrameMetadataResponse]
            do {
                outstanding = try await client.listFrames(device: device, transferred: false)
            } catch {
                TelescopeSessionManager.shared.errorMessage =
                    "Couldn't check for outstanding captured frames: \(TelescopeSessionManager.describe(error))"
                continue
            }
            for frame in CaptureImportPlanning.relevantFrames(outstanding, myRunIDs: myRunIDs) {
                await importFrame(frame, rigId: rig.id, client: client)
            }
        }

        for runId in myRunIDs {
            await finalizeRunIfComplete(runId: runId, rigId: rig.id, client: client)
        }
    }

    // Download → verify → import → confirm, in that order. `confirmFrameTransfer` only ever runs
    // after the archive import itself succeeds (I-2) — a checksum-verified download that then
    // fails to import must not be confirmed/purged server-side, or the frame becomes unrecoverable.
    // Any failure surfaces via TelescopeSessionManager.errorMessage (I-4's single error channel)
    // and simply leaves this frame's transferred state untouched, so the next reconcile() retries
    // it — it never blocks the rest of the batch. The imported frame's archive id is recorded
    // durably (CaptureRunTracker), not just held in memory: a run's frames can be imported across
    // several separate sessions (some tonight, the rest after tomorrow's reconnect), and only a
    // durable record survives the process restart in between.
    private func importFrame(_ frame: FrameMetadataResponse, rigId: String, client: INDIMCPClient) async {
        let destination = CaptureImportPlanning.localDestination(
            for: frame, archiveRoot: URL(fileURLWithPath: SettingsManager.shared.archivePath))
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await client.downloadFrame(frame, to: destination)

            switch try frame.verifyChecksum(ofFileAt: destination) {
            case .matched:
                break
            case .noChecksumAvailable:
                let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                guard (attributes[.size] as? Int) == frame.sizeBytes else {
                    try? FileManager.default.removeItem(at: destination)
                    throw CaptureImportError.sizeMismatch(frameId: frame.frameId)
                }
            case .mismatched(let expected, let actual):
                try? FileManager.default.removeItem(at: destination)
                throw CaptureImportError.checksumMismatch(frameId: frame.frameId, expected: expected, actual: actual)
            }

            let archivedFrame = try await ArchiveManager.shared.importCapturedFrame(at: destination)
            try await client.confirmFrameTransfer(frameId: frame.frameId)
            if let runId = frame.runId {
                CaptureRunTracker.recordFrameImported(rigId: rigId, runId: runId, frameID: archivedFrame.id)
            }
        } catch {
            TelescopeSessionManager.shared.errorMessage =
                "Failed to import captured frame \(frame.frameId): \(error.localizedDescription)"
        }
    }

    // A run is done once its status is terminal and nothing of it remains undelivered — only then
    // do we know CaptureRunTracker's durable record holds every frame the run produced (possibly
    // accumulated across several sessions), safe to group into a frameset and stop tracking.
    // forgetRun() only ever runs once the frameset step has actually succeeded (or there was
    // nothing to group) — a status/listFrames failure, or a failure partway through
    // createFrameSet's create→add→remove dance, leaves the run tracked so the next reconcile()
    // retries it, rather than silently and permanently giving up on grouping its frames.
    private func finalizeRunIfComplete(runId: String, rigId: String, client: INDIMCPClient) async {
        do {
            guard try await client.getScriptStatus(runId: runId).isTerminal else { return }
            guard try await client.listFrames(runId: runId, transferred: false).isEmpty else { return }
        } catch {
            TelescopeSessionManager.shared.errorMessage =
                "Couldn't confirm a completed capture run is ready to finalize: \(TelescopeSessionManager.describe(error))"
            return
        }

        let frameIDs = CaptureRunTracker.importedFrameIDs(rigId: rigId, runId: runId)
        var frames: [ArchivedFrame] = []
        for frameID in frameIDs {
            if let frame = await ArchiveManager.shared.archivedFrame(id: frameID) {
                frames.append(frame)
            }
        }
        if !frames.isEmpty {
            guard await createFrameSet(for: frames) else { return }
        }
        CaptureRunTracker.forgetRun(rigId: rigId, runId: runId)
    }

    // Best-effort query create, then force-reconcile membership to the exact accumulated ids —
    // see CaptureImportPlanning.frameSetQuery's doc comment for why the query doesn't need to be
    // precise. Returns whether it succeeded, so the caller knows whether it's safe to stop
    // tracking this run. Note: if createFrameSet itself succeeds but a later step (addFrames/
    // members/removeFrames) fails, the retry on the next reconcile() pass calls createFrameSet
    // again and will create a second, separate frameset rather than resuming the first — accepted
    // as a rare edge case (create succeeding immediately followed by a later step failing) rather
    // than adding a "remember which frameset id a still-incomplete run already has" mechanism for
    // it.
    @discardableResult
    private func createFrameSet(for frames: [ArchivedFrame]) async -> Bool {
        guard let first = frames.first, let query = CaptureImportPlanning.frameSetQuery(for: frames) else { return true }
        do {
            let frameSet = try await ArchiveManager.shared.createFrameSet(
                name: CaptureImportPlanning.frameSetName(for: first), query: query, force: true)
            let exactIDs = Set(frames.map(\.id))
            try await ArchiveManager.shared.addFrames(toFrameSet: frameSet.id, frameIDs: Array(exactIDs), force: true)

            let members = try await ArchiveManager.shared.members(inFrameSet: frameSet.id)
            let extraIDs = CaptureImportPlanning.extraMemberIDs(current: members.map { $0.frame.id }, exact: exactIDs)
            if !extraIDs.isEmpty {
                try await ArchiveManager.shared.removeFrames(fromFrameSet: frameSet.id, frameIDs: extraIDs)
            }
            return true
        } catch {
            TelescopeSessionManager.shared.errorMessage =
                "Failed to group captured frames into a set: \(error.localizedDescription)"
            return false
        }
    }
}

enum CaptureImportError: LocalizedError {
    case checksumMismatch(frameId: String, expected: String, actual: String)
    case sizeMismatch(frameId: String)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let frameId, let expected, let actual):
            return "Checksum mismatch for frame \(frameId): expected \(expected), got \(actual)."
        case .sizeMismatch(let frameId):
            return "Size mismatch for frame \(frameId) — no checksum available to verify against."
        }
    }
}
