//
//  CaptureRunTrackerTests.swift
//  NaviTests
//
//  CaptureRunTracker is the only mechanism that keeps NAVI-52's frame auto-import scoped to
//  frames Navi itself captured — touches the real UserDefaults key (no injectable store exists),
//  so the previous value is saved and restored around each test.
//

import Testing
import Foundation
@testable import Navi

@Suite(.serialized)
struct CaptureRunTrackerTests {
    private static let key = "navi.captureRunIDs"
    private static let framesKey = "navi.captureRunFrameIDs"

    private func withCleanState(_ body: () throws -> Void) rethrows {
        let previousRuns = UserDefaults.standard.dictionary(forKey: Self.key)
        let previousFrames = UserDefaults.standard.dictionary(forKey: Self.framesKey)
        defer {
            if let previousRuns {
                UserDefaults.standard.set(previousRuns, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
            if let previousFrames {
                UserDefaults.standard.set(previousFrames, forKey: Self.framesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.framesKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.key)
        UserDefaults.standard.removeObject(forKey: Self.framesKey)
        try body()
    }

    @Test func recordedRunIsReturnedForItsOwnRig() throws {
        try withCleanState {
            CaptureRunTracker.recordRunStarted(rigId: "rig-a", runId: "run-1")

            #expect(CaptureRunTracker.runIDs(forRig: "rig-a") == ["run-1"])
            #expect(CaptureRunTracker.runIDs(forRig: "rig-b").isEmpty)
        }
    }

    @Test func recordingTheSameRunTwiceDoesNotDuplicate() throws {
        try withCleanState {
            CaptureRunTracker.recordRunStarted(rigId: "rig-a", runId: "run-1")
            CaptureRunTracker.recordRunStarted(rigId: "rig-a", runId: "run-1")

            #expect(CaptureRunTracker.runIDs(forRig: "rig-a") == ["run-1"])
        }
    }

    @Test func forgettingARunRemovesOnlyThatRun() throws {
        try withCleanState {
            CaptureRunTracker.recordRunStarted(rigId: "rig-a", runId: "run-1")
            CaptureRunTracker.recordRunStarted(rigId: "rig-a", runId: "run-2")

            CaptureRunTracker.forgetRun(rigId: "rig-a", runId: "run-1")

            #expect(CaptureRunTracker.runIDs(forRig: "rig-a") == ["run-2"])
        }
    }

    @Test func forgettingTheLastRunLeavesAnEmptySet() throws {
        try withCleanState {
            CaptureRunTracker.recordRunStarted(rigId: "rig-a", runId: "run-1")

            CaptureRunTracker.forgetRun(rigId: "rig-a", runId: "run-1")

            #expect(CaptureRunTracker.runIDs(forRig: "rig-a").isEmpty)
        }
    }

    @Test func forgettingAnUntrackedRunIsANoOp() throws {
        try withCleanState {
            CaptureRunTracker.forgetRun(rigId: "rig-a", runId: "run-1")

            #expect(CaptureRunTracker.runIDs(forRig: "rig-a").isEmpty)
        }
    }

    // Regression coverage for the "imports spanning two separate app sessions" case: the durable
    // frame-id record must survive independent of the in-memory state of whichever process wrote
    // it, since that's the whole point of tracking it here rather than in a local accumulator.

    @Test func importedFrameIDsAccumulateAcrossSeparateRecordCalls() throws {
        try withCleanState {
            let a = UUID(), b = UUID()
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-1", frameID: a)
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-1", frameID: b)

            #expect(Set(CaptureRunTracker.importedFrameIDs(rigId: "rig-a", runId: "run-1")) == [a, b])
        }
    }

    @Test func recordingTheSameFrameTwiceDoesNotDuplicate() throws {
        try withCleanState {
            let a = UUID()
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-1", frameID: a)
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-1", frameID: a)

            #expect(CaptureRunTracker.importedFrameIDs(rigId: "rig-a", runId: "run-1") == [a])
        }
    }

    @Test func differentRunsKeepIndependentFrameLists() throws {
        try withCleanState {
            let a = UUID(), b = UUID()
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-1", frameID: a)
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-2", frameID: b)

            #expect(CaptureRunTracker.importedFrameIDs(rigId: "rig-a", runId: "run-1") == [a])
            #expect(CaptureRunTracker.importedFrameIDs(rigId: "rig-a", runId: "run-2") == [b])
        }
    }

    @Test func forgettingARunClearsItsImportedFrameIDs() throws {
        try withCleanState {
            CaptureRunTracker.recordFrameImported(rigId: "rig-a", runId: "run-1", frameID: UUID())

            CaptureRunTracker.forgetRun(rigId: "rig-a", runId: "run-1")

            #expect(CaptureRunTracker.importedFrameIDs(rigId: "rig-a", runId: "run-1").isEmpty)
        }
    }
}
