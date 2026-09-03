//
//  ObservatoryCacheRefresher.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import Foundation
import SwiftData
import INDIMCPKit

/// Refreshes the local `ObservatoryProfile` cache from the server's summary list
/// (`listObservatories`). Shared by `TelescopeSelectionSheet` and `ObservatorySettingsPane` —
/// previously only the former ever called this, so Settings → Observatories showed nothing until
/// the toolbar's picker had been opened at least once while connected. A local store reset (which
/// this schema has needed more than once during development) made that gap obvious: the cache was
/// empty and nothing in Settings itself would ever repopulate it.
///
/// Only writes `serverObservatoryID`/`name`/`cachedAt` — `listObservatories` returns summaries, not
/// full definitions, so coordinates are deliberately left untouched here. Full coordinates only
/// ever arrive via `getObservatory` (`ObservatoryEditForm.load()`), which also sets
/// `detailsFetchedAt` — the marker NAVI-86 added so a summary-only record can't be mistaken for one
/// genuinely sitting at 0/0/0.
enum ObservatoryCacheRefresher {
    @MainActor
    @discardableResult
    static func refresh(telescope: TelescopeSessionManager, modelContext: ModelContext) async -> Bool {
        do {
            let summaries = try await telescope.listObservatories()
            let existing = (try? modelContext.fetch(FetchDescriptor<ObservatoryProfile>())) ?? []
            for summary in summaries {
                if let match = existing.first(where: { $0.serverObservatoryID == summary.id }) {
                    match.name = summary.name
                    match.cachedAt = .now
                } else {
                    modelContext.insert(ObservatoryProfile(serverObservatoryID: summary.id, name: summary.name))
                }
            }
            try modelContext.save()
            return true
        } catch {
            // I-4: funnel into TelescopeSessionManager's one error-surfacing property rather than
            // dropping this silently — a failed background refresh should still be visible.
            telescope.errorMessage = "Couldn't refresh the observatory list: \(TelescopeSessionManager.describe(error))"
            return false
        }
    }
}
