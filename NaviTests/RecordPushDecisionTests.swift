//
//  RecordPushDecisionTests.swift
//  NaviTests
//

import Testing
@testable import Navi

/// Pins NAVI-86's drift-detection decision — the one piece of logic the whole "Navi as source of
/// truth" feature depends on, and the riskiest to get wrong: a `.push` where `.conflict` belongs
/// silently overwrites a change made elsewhere; a `.conflict` where `.push` belongs blocks a
/// legitimate save. Extracted from four near-identical hand-written copies (`RigEditForm.push`,
/// `ObservatoryEditForm.save`, and `PendingPushSync`'s two loops) specifically so this could be
/// pinned in one place instead of four.
struct RecordPushDecisionTests {

    // MARK: - Nothing to send

    @Test func identicalCurrentAndLastPushedDigestsSkip() {
        #expect(
            recordPushDecision(currentDigest: "abc", lastPushedDigest: "abc", serverDigest: nil)
                == .nothingToSend
        )
    }

    @Test func nothingToSendWinsEvenIfTheServerHasDrifted() {
        // Doesn't matter what the server looks like if there's nothing new to tell it — this is
        // the same reasoning every call site already uses to skip the round-trip entirely.
        #expect(
            recordPushDecision(currentDigest: "abc", lastPushedDigest: "abc", serverDigest: "different")
                == .nothingToSend
        )
    }

    // MARK: - First push (no prior digest to drift-check against)

    @Test func aRecordNeverPushedFromThisInstallPushes() {
        #expect(
            recordPushDecision(currentDigest: "abc", lastPushedDigest: nil, serverDigest: nil)
                == .push
        )
    }

    @Test func aRecordNeverPushedPushesEvenIfAServerDigestSomehowExists() {
        // Shouldn't happen in practice (nothing to have drift-checked against), but the decision
        // is defined purely by whether `lastPushedDigest` exists — not by whether a server digest
        // happens to be present.
        #expect(
            recordPushDecision(currentDigest: "abc", lastPushedDigest: nil, serverDigest: "server")
                == .push
        )
    }

    // MARK: - Drift check

    @Test func theServerMatchingTheLastPushDoesNotDriftAndSoPushes() {
        #expect(
            recordPushDecision(currentDigest: "new", lastPushedDigest: "old", serverDigest: "old")
                == .push
        )
    }

    @Test func theServerDivergingFromTheLastPushConflicts() {
        #expect(
            recordPushDecision(currentDigest: "new", lastPushedDigest: "old", serverDigest: "somethingElse")
                == .conflict
        )
    }

    // MARK: - A failed/skipped server fetch never blocks a push

    @Test func aMissingServerDigestFallsThroughToPushRatherThanBlocking() {
        // `serverDigest == nil` covers both "offline, never fetched" and "the fetch itself threw" —
        // every pre-extraction call site treated a failed fetch as "no information," not as "no
        // conflict found," so it proceeds to push rather than silently stalling on a transient
        // failure.
        #expect(
            recordPushDecision(currentDigest: "new", lastPushedDigest: "old", serverDigest: nil)
                == .push
        )
    }

    // MARK: - A nil current digest never claims "nothing to send"

    @Test func aNilCurrentDigestNeverSkipsEvenIfLastPushedIsAlsoNil() {
        // A `nil` current digest means the payload couldn't be encoded at all — never the same
        // thing as "matches what was last pushed," even when both sides happen to be `nil`.
        #expect(
            recordPushDecision(currentDigest: nil, lastPushedDigest: nil, serverDigest: nil)
                == .push
        )
    }
}
