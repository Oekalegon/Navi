//
//  EquipmentSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import SwiftUI
import SwiftData

/// The Settings "Equipment pane" (§4.3, NAVI-85): every reusable equipment-library entity — Mount,
/// Optical Assembly (main and guide), Camera, Filter Wheel, Rotator, Guide Camera, and the four
/// standalone roles (Power Hub, Flat Screen, Dew Heater, Observatory Control) — gets its own
/// browsable/editable list here, independent of any Rig or Imaging Train. `RigEditForm`/
/// `ImagingTrainEditForm` only *pick* from what's defined here; neither creates or edits equipment
/// inline. Imaging Train itself isn't listed here — it's a *composition* of equipment (Camera/
/// Filter Wheel/Rotator), not a piece of equipment on its own, so it gets its own top-level
/// Settings tab (`ImagingTrainSettingsPane`) instead, the same way `RigProfile` composes equipment
/// without being equipment itself.
///
/// Deliberately a plain `HStack`, not `NavigationSplitView` — see `ServerSettingsPane`'s doc
/// comment for why (the same window-toolbar-chrome conflict with the enclosing `TabView`).
///
/// The sidebar is an `OutlineGroup`: each equipment *kind* is itself a selectable row (no per-row
/// "+"), showing a "list of what you own + Add" overview on the right when selected; its owned
/// instances render as indented, selectable children (name + delete only). `OutlineGroup` rather
/// than `DisclosureGroup` (whose header isn't independently selectable — it conflates expand with
/// select) or `Section` (whose headers aren't part of the selection model at all).
///
/// Both the sidebar's child rows and the type overview's list derive from `instances(for:)`, so
/// the two paths into the same `Selection` can't drift apart. See `sidebar` for the list-style
/// choice.
///
/// Optical Assembly is split into two fixed-purpose kinds (matching `RigEditForm`'s existing
/// `mainOpticalAssemblies`/`guideOpticalAssemblies` split) rather than exposing a raw `purpose`
/// picker — same reasoning `OpticalAssemblyEditForm`'s `purpose` parameter already encodes.
///
/// Every device-bearing field here is `DevicePickerField` only — picked from the live, *connected*
/// INDI device list (§4.2), never free text. There is deliberately no separate "preferred driver"
/// picker over the full INDI driver catalog: starting/stopping drivers is `DriverManagementSheet`'s
/// job, embedded in the Server pane (NAVI-62) — a driver is server-wide config, not a per-equipment
/// choice, and the full catalog is far too long a list to pick from once per piece of equipment.
struct EquipmentSettingsPane: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MountProfile.name) private var mounts: [MountProfile]
    @Query(sort: \OpticalAssemblyProfile.name) private var opticalAssemblies: [OpticalAssemblyProfile]
    @Query(sort: \CameraProfile.name) private var cameras: [CameraProfile]
    @Query(sort: \FilterWheelProfile.name) private var filterWheels: [FilterWheelProfile]
    @Query(sort: \RotatorProfile.name) private var rotators: [RotatorProfile]
    @Query(sort: \GuideCameraProfile.name) private var guideCameras: [GuideCameraProfile]
    @Query(sort: \StandaloneEquipmentProfile.name) private var standaloneEquipment: [StandaloneEquipmentProfile]

    private var mainOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .mainImaging } }
    private var guideOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .guideScope } }
    private func standaloneEquipment(for role: StandaloneEquipmentRole) -> [StandaloneEquipmentProfile] {
        standaloneEquipment.filter { $0.role == role }
    }

    private enum EquipmentKind: CaseIterable, Hashable {
        case mount, opticalAssembly, guideOpticalAssembly, camera, filterWheel, rotator, guideCamera
        case powerHub, flatScreen, dewHeater, observatoryControl

        var title: String {
            switch self {
            case .mount: return "Mounts"
            case .opticalAssembly: return "Optical Assemblies"
            case .guideOpticalAssembly: return "Guide Optical Assemblies"
            case .camera: return "Cameras"
            case .filterWheel: return "Filter Wheels"
            case .rotator: return "Rotators"
            case .guideCamera: return "Guide Cameras"
            case .powerHub: return "Power Hubs"
            case .flatScreen: return "Flat Screens"
            case .dewHeater: return "Dew Heaters"
            case .observatoryControl: return "Observatory Controls"
            }
        }

        /// Singular form, for the "+" button's tooltip ("Add Mount", not "Add Mounts") — matching
        /// how every other Settings pane phrases its own `addHelp`.
        var singularTitle: String {
            switch self {
            case .mount: return "Mount"
            case .opticalAssembly: return "Optical Assembly"
            case .guideOpticalAssembly: return "Guide Optical Assembly"
            case .camera: return "Camera"
            case .filterWheel: return "Filter Wheel"
            case .rotator: return "Rotator"
            case .guideCamera: return "Guide Camera"
            case .powerHub: return "Power Hub"
            case .flatScreen: return "Flat Screen"
            case .dewHeater: return "Dew Heater"
            case .observatoryControl: return "Observatory Control"
            }
        }

        var icon: String {
            switch self {
            case .mount: return "gyroscope"
            case .opticalAssembly, .guideOpticalAssembly: return "circle.dotted"
            case .camera: return "camera"
            case .filterWheel: return "circle.grid.3x3"
            case .rotator: return "rotate.right"
            case .guideCamera: return "camera.viewfinder"
            case .powerHub: return "bolt"
            case .flatScreen: return "rectangle.on.rectangle"
            case .dewHeater: return "flame"
            case .observatoryControl: return "building.columns"
            }
        }

        var standaloneRole: StandaloneEquipmentRole? {
            switch self {
            case .powerHub: return .powerHub
            case .flatScreen: return .flatScreen
            case .dewHeater: return .dewHeater
            case .observatoryControl: return .observatoryControl
            default: return nil
            }
        }
    }

    /// Just "a kind" or "one owned record" — the per-type `.existingCamera`/`.newCamera` cases are
    /// gone. `PersistentIdentifier` is unique across model types, so one case covers every kind, and
    /// "new" no longer needs representing at all: "+" inserts a blank record immediately and selects
    /// it (the macOS Settings convention), so there is no unsaved draft state to model.
    private enum Selection: Hashable {
        case kind(EquipmentKind)
        case existing(PersistentIdentifier)
    }
    @State private var selection: Selection?
    @State private var pendingDeletion: (name: String, action: () -> Void)?

    /// One row in the sidebar tree — a kind's own row, or one of its owned records. Identity and
    /// equality are driven entirely by `selection`.
    private struct SidebarNode: Identifiable, Hashable {
        let title: String
        let icon: String
        let selection: Selection
        var children: [SidebarNode]?

        var id: Selection { selection }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection }
        func hash(into hasher: inout Hasher) { hasher.combine(selection) }
    }

    /// One owned record's row data, independent of where it's rendered — the sidebar's children and
    /// the type overview's list are two views of the same array, which is what keeps them in step.
    private struct Instance {
        let id: PersistentIdentifier
        let name: String
    }

    /// The single per-kind lookup. A new equipment kind means one case here (plus its
    /// `EquipmentKind` case and a branch in `editor(for:)` and `insert(into:)`).
    private func instances(for kind: EquipmentKind) -> [Instance] {
        switch kind {
        case .mount:
            return mounts.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .opticalAssembly:
            return mainOpticalAssemblies.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .guideOpticalAssembly:
            return guideOpticalAssemblies.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .camera:
            return cameras.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .filterWheel:
            return filterWheels.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .rotator:
            return rotators.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .guideCamera:
            return guideCameras.map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        case .powerHub, .flatScreen, .dewHeater, .observatoryControl:
            guard let role = kind.standaloneRole else { return [] }
            return standaloneEquipment(for: role).map { Instance(id: $0.persistentModelID, name: $0.displayName) }
        }
    }

    private var topLevelNodes: [SidebarNode] {
        EquipmentKind.allCases.map { kind in
            // Always a non-nil children array, even when empty. `OutlineGroup` only insets a row for
            // the disclosure chevron when that row is expandable, and there's no API to reserve the
            // space otherwise — so passing `nil` for empty kinds (which does correctly suppress a
            // chevron revealing nothing) makes every *other* kind's title sit at a different x, and
            // the list visibly shifts the moment the first record of any kind is added.
            SidebarNode(
                title: kind.title,
                icon: kind.icon,
                selection: .kind(kind),
                children: instances(for: kind).map {
                    SidebarNode(title: $0.name, icon: kind.icon, selection: .existing($0.id), children: nil)
                }
            )
        }
    }

    /// Which kind the "+" would add to: the selected kind, or the kind owning the selected record.
    private var activeKind: EquipmentKind? {
        switch selection {
        case .kind(let kind): return kind
        case .existing(let id): return EquipmentKind.allCases.first { instances(for: $0).contains { $0.id == id } }
        case nil: return nil
        }
    }

    private var selectedInstanceID: PersistentIdentifier? {
        if case .existing(let id) = selection { return id }
        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 320, maxHeight: .infinity)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDeletion?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                pendingDeletion?.action()
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Any rig or imaging train using this will have that role cleared, not deleted.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsPaneHeader(
                title: "Equipment",
                isAddDisabled: activeKind == nil,
                addHelp: activeKind.map { "Add \($0.singularTitle)" } ?? "Select a category first",
                onAdd: { if let activeKind { insert(into: activeKind) } },
                isRemoveDisabled: selectedInstanceID == nil,
                removeHelp: "Remove the selected item",
                onRemove: { if let selectedInstanceID { confirmDelete(selectedInstanceID) } }
            )
            Divider()
            List(selection: $selection) {
                OutlineGroup(topLevelNodes, children: \.children) { node in
                    row(for: node).tag(node.selection)
                }
            }
            // `.sidebar`, not `.plain` — this is what gives rows the native inset *rounded*
            // selection capsule; `.plain` draws selection as a full-width rectangle, and also draws
            // a separator hairline between rows. `.scrollContentBackground(.hidden)` suppresses only
            // the sidebar background material (designed to sit against `NavigationSplitView` window
            // chrome, which this plain `HStack` isn't).
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func row(for node: SidebarNode) -> some View {
        if case .kind = node.selection {
            Label(node.title, systemImage: node.icon)
        } else {
            Text(node.title)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .kind(let kind):
            kindOverview(for: kind)
        case .existing(let id):
            editor(for: id)
        case nil:
            placeholder
        }
    }

    /// Resolves a selected id to whichever kind of record owns it. `.id(id)` on each editor forces a
    /// fresh view when the selection moves between records of the same type.
    @ViewBuilder
    private func editor(for id: PersistentIdentifier) -> some View {
        if let mount = mounts.first(where: { $0.persistentModelID == id }) {
            MountEditForm(mount: mount).id(id)
        } else if let assembly = opticalAssemblies.first(where: { $0.persistentModelID == id }) {
            OpticalAssemblyEditForm(opticalAssembly: assembly).id(id)
        } else if let camera = cameras.first(where: { $0.persistentModelID == id }) {
            CameraEditForm(camera: camera).id(id)
        } else if let filterWheel = filterWheels.first(where: { $0.persistentModelID == id }) {
            FilterWheelEditForm(filterWheel: filterWheel).id(id)
        } else if let rotator = rotators.first(where: { $0.persistentModelID == id }) {
            RotatorEditForm(rotator: rotator).id(id)
        } else if let guideCamera = guideCameras.first(where: { $0.persistentModelID == id }) {
            GuideCameraEditForm(guideCamera: guideCamera).id(id)
        } else if let equipment = standaloneEquipment.first(where: { $0.persistentModelID == id }) {
            StandaloneEquipmentEditForm(equipment: equipment).id(id)
        } else {
            placeholder
        }
    }

    /// The "select Cameras, see a list of what you own" panel. Its "+" adds to this kind, matching
    /// the sidebar header's.
    @ViewBuilder
    private func kindOverview(for kind: EquipmentKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPaneHeader(
                title: kind.title,
                addHelp: "Add \(kind.singularTitle)",
                onAdd: { insert(into: kind) }
            )
            Divider()
            let rows = instances(for: kind)
            if rows.isEmpty {
                Text("None defined yet.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer()
            } else {
                List(rows, id: \.id) { instance in
                    Button(action: { selection = .existing(instance.id) }) {
                        Text(instance.name)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var placeholder: some View {
        Text("Select a piece of equipment, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Inserts a blank record and selects it, so the detail pane becomes its editor immediately —
    /// there is no separate "new, unsaved" state. A blank record is valid: `displayName` falls back
    /// to make/model and then to a placeholder, so nothing forces the user to name it first.
    private func insert(into kind: EquipmentKind) {
        let inserted: any PersistentModel
        switch kind {
        case .mount:
            let new = MountProfile(name: ""); modelContext.insert(new); inserted = new
        case .opticalAssembly:
            let new = OpticalAssemblyProfile(name: "", purpose: .mainImaging); modelContext.insert(new); inserted = new
        case .guideOpticalAssembly:
            let new = OpticalAssemblyProfile(name: "", purpose: .guideScope); modelContext.insert(new); inserted = new
        case .camera:
            let new = CameraProfile(name: ""); modelContext.insert(new); inserted = new
        case .filterWheel:
            let new = FilterWheelProfile(name: ""); modelContext.insert(new); inserted = new
        case .rotator:
            let new = RotatorProfile(name: ""); modelContext.insert(new); inserted = new
        case .guideCamera:
            let new = GuideCameraProfile(name: ""); modelContext.insert(new); inserted = new
        case .powerHub, .flatScreen, .dewHeater, .observatoryControl:
            guard let role = kind.standaloneRole else { return }
            let new = StandaloneEquipmentProfile(name: "", role: role); modelContext.insert(new); inserted = new
        }
        try? modelContext.save()
        selection = .existing(inserted.persistentModelID)
    }

    private func confirmDelete(_ id: PersistentIdentifier) {
        let owningKind = activeKind
        let name = owningKind.flatMap { kind in instances(for: kind).first { $0.id == id }?.name } ?? "this item"
        pendingDeletion = (name, {
            deleteRecord(id)
            selection = owningKind.map { Selection.kind($0) }
        })
    }

    /// Resolved against the concrete `@Query` arrays rather than `ModelContext.registeredModel(for:)`,
    /// whose `any PersistentModel` result can't be passed to `delete(_:)`.
    private func deleteRecord(_ id: PersistentIdentifier) {
        if let mount = mounts.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(mount)
        } else if let assembly = opticalAssemblies.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(assembly)
        } else if let camera = cameras.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(camera)
        } else if let filterWheel = filterWheels.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(filterWheel)
        } else if let rotator = rotators.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(rotator)
        } else if let guideCamera = guideCameras.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(guideCamera)
        } else if let equipment = standaloneEquipment.first(where: { $0.persistentModelID == id }) {
            modelContext.delete(equipment)
        }
        try? modelContext.save()
    }
}
