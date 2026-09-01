//
//  RigSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI
import SwiftData

/// The Settings "Rig pane" (§4.2): lists the local `RigProfile` library and shows `RigEditForm`
/// inline as detail content — a master-detail layout (NAVI-77), not a modal sheet. See
/// `ServerSettingsPane`'s doc comment for why this is a plain `HStack`, not `NavigationSplitView`
/// — the same window-toolbar-chrome conflict with the enclosing `TabView`.
/// Unlike `ObservatorySettingsPane`, `RigProfile` *is* a local SwiftData model (it tracks which
/// library entities compose the rig, §4.3) — so this list itself needs no connection; only saving
/// a rig (which pushes it via `saveRig`) does, enforced by `RigEditForm`.
///
/// NAVI-81: the sidebar is an `OutlineGroup` tree, not `Section`s — each rig is itself a
/// *selectable* row (showing `RigSection.overview`) with its own children (OTA/Focuser, Mount,
/// Imaging Train, Guide Scope, Power Hub, Flat Screen, Dew Heater, Observatory Control); Imaging
/// Train is in turn a selectable row (showing `RigSection.imagingTrain(nil)`, the "which
/// `ImagingTrainProfile`" picker) with its own four children (Camera/Filter Wheel/Rotator/
/// Off-Axis Guider — see `ImagingTrainPart`). `OutlineGroup` — not `Section`+`DisclosureGroup`,
/// tried first — is what makes a *parent* row itself selectable while still independently
/// expandable/collapsible via its own disclosure triangle; `DisclosureGroup` conflates the two
/// (tapping anywhere on it just toggles expansion), and `Section` headers aren't part of a
/// `List`'s selection model at all. Because the rig/Imaging-Train rows are themselves selectable,
/// there's no separate "Overview" or "Imaging Train" leaf row alongside their children — the
/// parent row *is* that page.
struct RigSettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RigProfile.name) private var rigs: [RigProfile]

    // `.new` shows a blank RigEditForm without inserting a draft RigProfile into the library —
    // it only gets inserted once the user actually saves (RigEditForm.upsertLocalRig). Keyed by
    // `.id(rig.persistentModelID)` only (not the section) in `detail` below, so switching *sections*
    // for the same rig re-renders RigEditForm in place instead of remounting it.
    private enum Selection: Hashable {
        case existing(PersistentIdentifier, RigSection)
        case new(RigSection)
    }
    @State private var selection: Selection?
    @State private var rigPendingDeletion: RigProfile?

    /// One row in the sidebar tree. `rig` is non-nil only for a real rig's own root row (carries
    /// the delete button + stale-library icon); the "New Rig" draft root and every other row
    /// (including the Imaging Train parent) render as a plain `Label`. Identity/equality is driven
    /// entirely by `selection`, since that's already unique per row across the whole tree.
    private struct SidebarNode: Identifiable, Hashable {
        let title: String
        let icon: String
        let selection: Selection
        var children: [SidebarNode]?
        var rig: RigProfile?

        var id: Selection { selection }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection }
        func hash(into hasher: inout Hasher) { hasher.combine(selection) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300, maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Delete “\(rigPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { rigPendingDeletion != nil },
                set: { if !$0 { rigPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let rig = rigPendingDeletion { delete(rig) }
                rigPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { rigPendingDeletion = nil }
        } message: {
            Text("This only removes the rig from Navi's local library — it stays saved on the server.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Rigs",
                addHelp: "Add Rig",
                onAdd: { selection = .new(.overview) }
            )
            Divider()
            if rigs.isEmpty && selection == nil {
                emptyState
            } else {
                List(selection: $selection) {
                    // A `.new` draft has no `RigProfile` yet, so it isn't among `rigs` below —
                    // without this, there'd be no sidebar row for any section but the one the "+"
                    // button lands on (.overview), making Mount/Imaging Train/etc. unreachable
                    // until *after* the first Save. Neither `.new` case applies `.id()` in
                    // `detail`, so switching between these rows re-renders the same `RigEditForm`
                    // instance — no state lost while composing.
                    if case .new = selection {
                        OutlineGroup([rigNode(title: "New Rig", rig: nil, makeSelection: { .new($0) })], children: \.children) { node in
                            row(for: node).tag(node.selection)
                        }
                    }
                    ForEach(rigs) { rig in
                        OutlineGroup([rigNode(title: rig.name, rig: rig, makeSelection: { .existing(rig.persistentModelID, $0) })], children: \.children) { node in
                            row(for: node).tag(node.selection)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func imagingTrainNode(makeSelection: @escaping (RigSection) -> Selection) -> SidebarNode {
        SidebarNode(
            title: RigSection.imagingTrain(nil).title,
            icon: RigSection.imagingTrain(nil).icon,
            selection: makeSelection(.imagingTrain(nil)),
            children: ImagingTrainPart.allCases.map { part in
                SidebarNode(title: part.title, icon: part.icon, selection: makeSelection(.imagingTrain(part)), children: nil)
            }
        )
    }

    private func rigNode(title: String, rig: RigProfile?, makeSelection: @escaping (RigSection) -> Selection) -> SidebarNode {
        SidebarNode(
            title: title,
            icon: "scope",
            selection: makeSelection(.overview),
            children: [
                SidebarNode(title: RigSection.opticalAssembly.title, icon: RigSection.opticalAssembly.icon, selection: makeSelection(.opticalAssembly), children: nil),
                SidebarNode(title: RigSection.mount.title, icon: RigSection.mount.icon, selection: makeSelection(.mount), children: nil),
                imagingTrainNode(makeSelection: makeSelection),
                SidebarNode(title: RigSection.guideScope.title, icon: RigSection.guideScope.icon, selection: makeSelection(.guideScope), children: nil),
                SidebarNode(title: RigSection.powerHub.title, icon: RigSection.powerHub.icon, selection: makeSelection(.powerHub), children: nil),
                SidebarNode(title: RigSection.flatScreen.title, icon: RigSection.flatScreen.icon, selection: makeSelection(.flatScreen), children: nil),
                SidebarNode(title: RigSection.dewHeater.title, icon: RigSection.dewHeater.icon, selection: makeSelection(.dewHeater), children: nil),
                SidebarNode(title: RigSection.observatoryControl.title, icon: RigSection.observatoryControl.icon, selection: makeSelection(.observatoryControl), children: nil),
            ],
            rig: rig
        )
    }

    @ViewBuilder
    private func row(for node: SidebarNode) -> some View {
        if let rig = node.rig {
            // A real rig's own root row: bold/larger to read as a group heading, plus the
            // stale-library icon and delete button that used to live in a separate, non-selectable
            // `Section` header.
            HStack {
                HStack(spacing: 6) {
                    Text(node.title)
                        .font(.title3)
                        .fontWeight(.bold)
                    if rig.hasStaleLibraryReferences {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                            .help("A referenced library entity changed since this rig was last saved to the server.")
                    }
                }
                Spacer()
                Button(action: { rigPendingDeletion = rig }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete Rig")
            }
        } else if node.children != nil && node.selection == .new(.overview) {
            // The "New Rig" draft root — same heading treatment, no delete button (nothing
            // persisted yet to delete).
            Text(node.title)
                .font(.title3)
                .fontWeight(.bold)
        } else {
            Label(node.title, systemImage: node.icon)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .existing(let id, let section):
            if let rig = rigs.first(where: { $0.persistentModelID == id }) {
                RigEditForm(
                    rig: rig,
                    visibleSection: section,
                    onSelectSection: { newSection in selection = .existing(id, newSection) },
                    onSaved: { saved in selection = .existing(saved.persistentModelID, section) },
                    onFinished: { selection = nil }
                )
                .id(id)
            } else {
                placeholder
            }
        case .new(let section):
            RigEditForm(
                rig: nil,
                visibleSection: section,
                onSelectSection: { newSection in selection = .new(newSection) },
                onSaved: { saved in selection = .existing(saved.persistentModelID, section) },
                onFinished: { selection = nil }
            )
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("Select a rig, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No rigs yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add your first rig from the equipment library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ rig: RigProfile) {
        // Local-library-only removal, matching `ObservatorySettingsPane.remove(_:)` — there's no
        // delete-rig call in INDIMCPKit, so the server-side `Rig` file is untouched.
        if case .existing(let id, _) = selection, id == rig.persistentModelID {
            selection = nil
        }
        modelContext.delete(rig)
        try? modelContext.save()
    }
}
