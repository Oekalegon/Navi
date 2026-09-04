//
//  RecordPushDecision.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation

/// What a Rig/Observatory push should do, given the local record's digest against what's actually
/// pushed and what the server currently holds.
///
/// Shared by `RigEditForm.push`, `ObservatoryEditForm.save`, and `PendingPushSync`'s two loops —
/// all four hand-wrote this exact "skip if nothing changed, raise a conflict if the server drifted,
/// otherwise push" sequence independently before this was extracted, each with its own slightly
/// different `if let` ordering. Pulling it out as a pure function makes the one piece of logic
/// NAVI-86's whole drift-detection feature depends on directly testable, the same reasoning
/// `RecordFlushOutcome` already established for the sibling "should this even flush" decision.
///
/// `nonisolated`, matching `RecordFlushOutcome`'s own doc comment on why.
nonisolated enum RecordPushDecision: Equatable {
    /// The server already has exactly this payload — nothing to send.
    case nothingToSend
    /// The server changed since Navi last pushed this record — raise a conflict instead of
    /// silently overwriting it.
    case conflict
    /// Safe to push: either this is the first push ever (nothing to drift against), or the
    /// server's copy still matches what Navi last pushed.
    case push
}

/// Decides `RecordPushDecision` from the three digests a push has to reconcile.
nonisolated func recordPushDecision(
    currentDigest: String?,
    /// The digest Navi last successfully pushed for this record, or `nil` if it's never been
    /// pushed from this install. `nil` means there's nothing to drift-check against — a first push
    /// is legitimately creating (or adopting) the server-side record.
    lastPushedDigest: String?,
    /// The server's current digest, or `nil` if it couldn't be fetched (offline, or the fetch
    /// itself failed) — in which case the drift check is simply skipped, matching every call site's
    /// pre-extraction behavior: a failed fetch isn't treated as "no conflict," it's treated as "no
    /// information," so the push proceeds rather than silently blocking on a transient failure.
    serverDigest: String?
) -> RecordPushDecision {
    if let currentDigest, currentDigest == lastPushedDigest {
        return .nothingToSend
    }
    if let lastPushedDigest, let serverDigest, serverDigest != lastPushedDigest {
        return .conflict
    }
    return .push
}
