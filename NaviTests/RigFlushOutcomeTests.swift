//
//  RigFlushOutcomeTests.swift
//  NaviTests
//

import Testing
@testable import Navi

/// Pins the ordering invariant behind `RigEditForm.flush()`. The bug these exist for: flush()
/// bailed out entirely when the composition couldn't be flattened into the server's `Component`
/// list, so a rig whose main and guide optical assemblies both carry a focuser (they collide on
/// `.focuser`) silently lost the user's whole edit — the local write included — with no feedback,
/// because the error was reported onto a view that was already being torn down.
struct RigFlushOutcomeTests {

    // MARK: - The invariant that was broken

    @Test func aCompositionThatCannotBeProjectedStillPersistsLocally() {
        // The regression case. Navi holds the richer record; failing to flatten it for the server
        // is a reason not to push, never a reason not to save.
        #expect(
            rigFlushOutcome(isDirty: true, trimmedName: "Backyard Rig", isConnected: true, canProject: false)
                == .persistOnly
        )
    }

    @Test func beingDisconnectedStillPersistsLocally() {
        #expect(
            rigFlushOutcome(isDirty: true, trimmedName: "Backyard Rig", isConnected: false, canProject: true)
                == .persistOnly
        )
    }

    @Test func neitherConnectedNorProjectableStillPersistsLocally() {
        #expect(
            rigFlushOutcome(isDirty: true, trimmedName: "Backyard Rig", isConnected: false, canProject: false)
                == .persistOnly
        )
    }

    // MARK: - The one case that pushes

    @Test func dirtyNamedConnectedAndProjectablePushes() {
        #expect(
            rigFlushOutcome(isDirty: true, trimmedName: "Backyard Rig", isConnected: true, canProject: true)
                == .persistAndPush
        )
    }

    // MARK: - Skipping

    @Test func aCleanFormWritesNothing() {
        // Merely *viewing* a rig must never re-push it, whatever else is true.
        #expect(
            rigFlushOutcome(isDirty: false, trimmedName: "Backyard Rig", isConnected: true, canProject: true)
                == .skip
        )
    }

    @Test func anUnnamedRigWritesNothing() {
        // serverRigID is slugified from the name, so a blank name has nothing stable to key on.
        #expect(
            rigFlushOutcome(isDirty: true, trimmedName: "", isConnected: true, canProject: true)
                == .skip
        )
    }

    @Test func skippingBeatsEveryOtherGate() {
        // Ordering: the dirty/name guards run first, so a clean form never persists even when the
        // remaining conditions would otherwise say push.
        for isConnected in [true, false] {
            for canProject in [true, false] {
                #expect(
                    rigFlushOutcome(isDirty: false, trimmedName: "Rig", isConnected: isConnected, canProject: canProject)
                        == .skip
                )
                #expect(
                    rigFlushOutcome(isDirty: true, trimmedName: "", isConnected: isConnected, canProject: canProject)
                        == .skip
                )
            }
        }
    }

    @Test func everyDirtyNamedFormWritesLocallyRegardlessOfTheRest() {
        // The invariant stated positively across the whole matrix: once there's something to save
        // and something to key it on, local persistence always happens.
        for isConnected in [true, false] {
            for canProject in [true, false] {
                let outcome = rigFlushOutcome(
                    isDirty: true, trimmedName: "Rig", isConnected: isConnected, canProject: canProject
                )
                #expect(outcome != .skip)
            }
        }
    }
}
