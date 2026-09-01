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
/// NAVI-81: the sidebar is a nested list — each rig is a `Section` whose 9 `RigSection` subitems
/// (Overview, Mount, OTA/Focuser, Imaging Train, Guide Scope, Power Hub, Flat Screen, Dew Heater,
/// Observatory Control) let the user jump straight to one equipment concern instead of scrolling
/// through `RigEditForm`'s whole form. Tapping the rig's own name/row (the `Section` header) isn't
/// itself selectable — it navigates to the read-only Overview subitem, and each Overview row has
/// its own "open" button to jump into that role's editable page from there.
/// `.listStyle(.sidebar)` is what gives `Section` its collapsible chevron and bold-header rendering
/// here — a plain `List` row-styling modifier, unrelated to the `NavigationSplitView`
/// toolbar-chrome conflict noted above; it does not reintroduce that bug.
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
                    // button lands on (.opticalAssembly), making Mount/Imaging Train/etc.
                    // unreachable until *after* the first Save. Neither `.new` case applies `.id()`
                    // in `detail`, so switching between these rows re-renders the same
                    // `RigEditForm` instance — no state lost while composing.
                    if case .new = selection {
                        Section {
                            ForEach(RigSection.allCases) { section in
                                Label(section.title, systemImage: section.icon)
                                    .tag(Selection.new(section))
                            }
                        } header: {
                            Text("New Rig")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(rigs) { rig in
                        Section {
                            ForEach(RigSection.allCases) { section in
                                Label(section.title, systemImage: section.icon)
                                    .tag(Selection.existing(rig.persistentModelID, section))
                            }
                        } header: {
                            rigHeaderRow(for: rig)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
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

    private func rigHeaderRow(for rig: RigProfile) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(rig.name)
                    .font(.body)
                if rig.hasStaleLibraryReferences {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .help("A referenced library entity changed since this rig was last saved to the server.")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = .existing(rig.persistentModelID, .overview) }
            Spacer()
            Button(action: { rigPendingDeletion = rig }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete Rig")
        }
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
