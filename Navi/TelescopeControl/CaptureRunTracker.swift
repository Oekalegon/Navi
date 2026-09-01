//
//  CaptureRunTracker.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §5, I-2. `INDIMCPClient.listFrames(transferred: false)`
//  is the durable, server-side source of truth for what's still outstanding — but it has no
//  concept of which client requested a given capture, so it will happily return frames another
//  client (a second Navi instance, a test tool) left undelivered too. This is the only way Navi
//  knows "mine": a durable local record of every runId *this* Navi instance has started capturing
//  frames through. Must survive quit/relaunch — the whole point is catching up on frames that
//  finished while Navi was disconnected or not even running, possibly for hours.
//

import Foundation

enum CaptureRunTracker {
    private static let key = "navi.captureRunIDs"

    /// Records that this Navi instance started `runId` for `rigId` — call the moment any capture
    /// call (`Camera.captureFrame`/`captureXSequence`) succeeds, before waiting for it to finish.
    static func recordRunStarted(rigId: String, runId: String) {
        var all = load()
        var runs = all[rigId] ?? []
        guard !runs.contains(runId) else { return }
        runs.append(runId)
        all[rigId] = runs
        save(all)
    }

    /// Every runId this Navi instance has started for `rigId` and not yet forgotten.
    static func runIDs(forRig rigId: String) -> Set<String> {
        Set(load()[rigId] ?? [])
    }

    /// Stops tracking `runId` — call once it's fully reconciled (terminal status and no frames
    /// left outstanding), so this record doesn't grow forever. Clears both the run-id record and
    /// its imported-frame-id record independently: they're conceptually coupled (one run), but
    /// deliberately not gated on each other here, so this call is always a complete cleanup even
    /// if the two ever fell out of sync with one another.
    static func forgetRun(rigId: String, runId: String) {
        var all = load()
        if var runs = all[rigId] {
            runs.removeAll { $0 == runId }
            all[rigId] = runs.isEmpty ? nil : runs
            save(all)
        }
        forgetImportedFrames(rigId: rigId, runId: runId)
    }

    private static func load() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }

    private static func save(_ all: [String: [String]]) {
        UserDefaults.standard.set(all, forKey: key)
    }

    // MARK: - Imported frame ids per run
    //
    // A run's frames can be imported across multiple sessions — some tonight while Navi happens
    // to be connected, the rest tomorrow morning after the telescope finished unattended overnight
    // and Navi only just reconnected. CaptureImportManager needs the *complete* set of a run's
    // already-imported archive frame ids when it finally groups them into a frameset, and an
    // in-memory accumulator would lose everything imported in an earlier process — this is the
    // durable record that survives across those separate sessions.

    private static let framesKey = "navi.captureRunFrameIDs"

    /// Records that `frameID` (an `ArchivedFrame.id`) has been imported for `runId` — call right
    /// after each frame's import succeeds, not batched, so a mid-run quit loses nothing already
    /// imported.
    static func recordFrameImported(rigId: String, runId: String, frameID: UUID) {
        var all = loadFrames()
        var ids = all[compositeKey(rigId: rigId, runId: runId)] ?? []
        let idString = frameID.uuidString
        guard !ids.contains(idString) else { return }
        ids.append(idString)
        all[compositeKey(rigId: rigId, runId: runId)] = ids
        saveFrames(all)
    }

    /// Every archive frame id imported so far for `runId`, across however many sessions it took.
    static func importedFrameIDs(rigId: String, runId: String) -> [UUID] {
        (loadFrames()[compositeKey(rigId: rigId, runId: runId)] ?? []).compactMap(UUID.init(uuidString:))
    }

    private static func forgetImportedFrames(rigId: String, runId: String) {
        var all = loadFrames()
        all[compositeKey(rigId: rigId, runId: runId)] = nil
        saveFrames(all)
    }

    private static func compositeKey(rigId: String, runId: String) -> String { "\(rigId)|\(runId)" }

    private static func loadFrames() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: framesKey) as? [String: [String]] ?? [:]
    }

    private static func saveFrames(_ all: [String: [String]]) {
        UserDefaults.standard.set(all, forKey: framesKey)
    }
}
