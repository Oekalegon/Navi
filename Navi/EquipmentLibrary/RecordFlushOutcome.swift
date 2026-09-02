//
//  RecordFlushOutcome.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation

/// What an edit form should do when it's torn down with pending edits.
///
/// Shared by `RigEditForm` and `ObservatoryEditForm`: both hold a record Navi owns, write it
/// locally, and push it to the server as a separate step that simply waits for a connection.
///
/// `nonisolated` on both this type and `recordFlushOutcome` because the project builds with
/// `InferIsolatedConformances`, which otherwise infers a main-actor-isolated `Equatable` here —
/// unusable from a nonisolated context, and a hard error under the Swift 6 language mode. Neither
/// touches actor state, so isolating them buys nothing.
nonisolated enum RecordFlushOutcome: Equatable {
    /// Nothing to write — no edits, or nothing worth identifying the rig by yet.
    case skip
    /// Write the composition to SwiftData, but don't push. Either there's no connection, or the
    /// composition can't currently be flattened into the server's `Component` list.
    case persistOnly
    /// Write locally and push to the server.
    case persistAndPush
}

/// Decides `RecordFlushOutcome` from the four things that gate it.
///
/// Extracted as a pure function because the *ordering* here was a real data-loss bug, and ordering
/// bugs inside a SwiftUI teardown path are close to untestable in place. `RigEditForm.flush()`
/// originally bailed out entirely when the composition couldn't be flattened — so a rig whose main
/// and guide optical assemblies both carry a focuser (they collide on the `.focuser` role, see
/// `RigProfileTranslationError.duplicateRole`) lost the user's whole edit, local write included,
/// with no feedback because the error was reported onto a view that was already going away.
///
/// The invariant that fixes it, and that `RecordFlushOutcomeTests` pins: **local persistence never
/// depends on `canProject`.** Navi holds the richer record — `RigProfile` names which library
/// entity fills each role, while the server only ever sees the flattened list — so the local write
/// must not be gated on whether that lossy projection currently succeeds. Failing to project is a
/// reason not to *push*, never a reason not to *save*.
nonisolated func recordFlushOutcome(
    isDirty: Bool,
    trimmedName: String,
    isConnected: Bool,
    /// Whether the record can currently be turned into whatever shape the server accepts. Only
    /// `RigEditForm` can fail this (its composition is flattened into a `Component` list, which can
    /// collide on a role); an Observatory has no such projection, hence the default.
    canProject: Bool = true
) -> RecordFlushOutcome {
    guard isDirty, !trimmedName.isEmpty else { return .skip }
    guard isConnected, canProject else { return .persistOnly }
    return .persistAndPush
}
