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

    private enum Selection: Hashable {
        case kind(EquipmentKind)
        case existingMount(PersistentIdentifier)
        case newMount
        case existingOpticalAssembly(PersistentIdentifier)
        case newOpticalAssembly(OpticalAssemblyPurpose)
        case existingCamera(PersistentIdentifier)
        case newCamera
        case existingFilterWheel(PersistentIdentifier)
        case newFilterWheel
        case existingRotator(PersistentIdentifier)
        case newRotator
        case existingGuideCamera(PersistentIdentifier)
        case newGuideCamera
        case existingStandalone(PersistentIdentifier)
        case newStandalone(StandaloneEquipmentRole)
    }
    @State private var selection: Selection?
    @State private var pendingDeletion: (name: String, action: () -> Void)?

    /// One row in the sidebar tree — a kind's own row (`instanceSelection == nil`) or one of its
    /// owned instances (`instanceSelection` is that instance's own selection, driving the delete
    /// button). Identity/equality driven entirely by `selection`, matching the same pattern used
    /// for the Rig sidebar's `SidebarNode`.
    private struct SidebarNode: Identifiable, Hashable {
        let title: String
        let icon: String
        let selection: Selection
        var children: [SidebarNode]?
        var onDelete: (() -> Void)?

        var id: Selection { selection }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.selection == rhs.selection }
        func hash(into hasher: inout Hasher) { hasher.combine(selection) }
    }

    /// One row's worth of data for a single owned entity, independent of where it's rendered —
    /// the sidebar's child rows and the type overview's list are two views of the same thing, and
    /// deriving both from `instances(for:)` is what keeps them from drifting. `delete` closes over
    /// the entity so the seven near-identical `delete(_:)` overloads this replaced aren't needed.
    private struct Instance {
        let id: PersistentIdentifier
        let name: String
        let selection: Selection
        let delete: () -> Void
    }

    /// The single per-kind lookup. Adding a new equipment kind means adding one case here (plus
    /// its `EquipmentKind`/`Selection` cases and its detail branch) rather than touching three
    /// parallel switches and a delete overload, which is what this file used to require.
    private func instances(for kind: EquipmentKind) -> [Instance] {
        switch kind {
        case .mount:
            return mounts.map { instance($0, name: $0.name, kind: kind, selection: .existingMount($0.persistentModelID)) }
        case .opticalAssembly:
            return mainOpticalAssemblies.map { instance($0, name: $0.name, kind: kind, selection: .existingOpticalAssembly($0.persistentModelID)) }
        case .guideOpticalAssembly:
            return guideOpticalAssemblies.map { instance($0, name: $0.name, kind: kind, selection: .existingOpticalAssembly($0.persistentModelID)) }
        case .camera:
            return cameras.map { instance($0, name: $0.name, kind: kind, selection: .existingCamera($0.persistentModelID)) }
        case .filterWheel:
            return filterWheels.map { instance($0, name: $0.name, kind: kind, selection: .existingFilterWheel($0.persistentModelID)) }
        case .rotator:
            return rotators.map { instance($0, name: $0.name, kind: kind, selection: .existingRotator($0.persistentModelID)) }
        case .guideCamera:
            return guideCameras.map { instance($0, name: $0.name, kind: kind, selection: .existingGuideCamera($0.persistentModelID)) }
        case .powerHub, .flatScreen, .dewHeater, .observatoryControl:
            guard let role = kind.standaloneRole else { return [] }
            return standaloneEquipment(for: role).map { instance($0, name: $0.name, kind: kind, selection: .existingStandalone($0.persistentModelID)) }
        }
    }

    /// Builds one `Instance`, including the confirm-then-delete closure. Deleting the currently
    /// selected entity resets selection to its kind's overview rather than leaving a dangling
    /// selection pointing at a deleted `PersistentIdentifier`.
    private func instance<T: PersistentModel>(
        _ entity: T,
        name: String,
        kind: EquipmentKind,
        selection rowSelection: Selection
    ) -> Instance {
        Instance(
            id: entity.persistentModelID,
            name: name,
            selection: rowSelection,
            delete: {
                pendingDeletion = (name, {
                    if selection == rowSelection { selection = .kind(kind) }
                    modelContext.delete(entity)
                    try? modelContext.save()
                })
            }
        )
    }

    private var topLevelNodes: [SidebarNode] {
        EquipmentKind.allCases.map { kind in
            kindNode(kind, children: instances(for: kind).map { row in
                childNode(name: row.name, icon: kind.icon, selection: row.selection, onDelete: row.delete)
            })
        }
    }
    private func kindNode(_ kind: EquipmentKind, children: [SidebarNode]) -> SidebarNode {
        // `nil`, not `[]`, when a kind owns nothing: `OutlineGroup` treats an empty-but-non-nil
        // children array as "expandable, currently empty" and draws a disclosure chevron that
        // reveals nothing — which on a fresh library would be every row.
        SidebarNode(
            title: kind.title,
            icon: kind.icon,
            selection: .kind(kind),
            children: children.isEmpty ? nil : children
        )
    }

    private func childNode(name: String, icon: String, selection: Selection, onDelete: @escaping () -> Void) -> SidebarNode {
        SidebarNode(title: name, icon: icon, selection: selection, children: nil, onDelete: onDelete)
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
            "Delete “\(pendingDeletion?.name ?? "")”?",
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
        List(selection: $selection) {
            OutlineGroup(topLevelNodes, children: \.children) { node in
                row(for: node).tag(node.selection)
            }
        }
        // `.sidebar`, not `.plain` — this is what gives rows the native inset *rounded* selection
        // capsule; `.plain` draws selection as a rectangle spanning the full width, which reads as
        // a table, not a source list. `.sidebar` also omits row separators on its own, so the
        // explicit `.listRowSeparator(.hidden)` this used to need is gone.
        //
        // `.scrollContentBackground(.hidden)` suppresses only the sidebar *background material*
        // (designed to sit against a `NavigationSplitView`'s window chrome, which this plain
        // `HStack` isn't — it renders as an opaque box here) while keeping the row metrics and
        // selection styling that are the reason for choosing `.sidebar`.
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func row(for node: SidebarNode) -> some View {
        if let onDelete = node.onDelete {
            HStack {
                Text(node.title)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        } else {
            Label(node.title, systemImage: node.icon)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .kind(let kind):
            kindOverview(for: kind)
        case .existingMount(let id):
            if let mount = mounts.first(where: { $0.persistentModelID == id }) {
                MountEditForm(mount: mount, onSaved: { selection = .existingMount($0.persistentModelID) }, onFinished: { selection = .kind(.mount) })
                    .id(id)
            } else { placeholder }
        case .newMount:
            MountEditForm(mount: nil, onSaved: { selection = .existingMount($0.persistentModelID) }, onFinished: { selection = .kind(.mount) })
        case .existingOpticalAssembly(let id):
            if let assembly = opticalAssemblies.first(where: { $0.persistentModelID == id }) {
                OpticalAssemblyEditForm(opticalAssembly: assembly, purpose: assembly.purpose, onSaved: { selection = .existingOpticalAssembly($0.persistentModelID) }, onFinished: { selection = .kind(assembly.purpose == .mainImaging ? .opticalAssembly : .guideOpticalAssembly) })
                    .id(id)
            } else { placeholder }
        case .newOpticalAssembly(let purpose):
            OpticalAssemblyEditForm(opticalAssembly: nil, purpose: purpose, onSaved: { selection = .existingOpticalAssembly($0.persistentModelID) }, onFinished: { selection = .kind(purpose == .mainImaging ? .opticalAssembly : .guideOpticalAssembly) })
        case .existingCamera(let id):
            if let camera = cameras.first(where: { $0.persistentModelID == id }) {
                CameraEditForm(camera: camera, onSaved: { selection = .existingCamera($0.persistentModelID) }, onFinished: { selection = .kind(.camera) })
                    .id(id)
            } else { placeholder }
        case .newCamera:
            CameraEditForm(camera: nil, onSaved: { selection = .existingCamera($0.persistentModelID) }, onFinished: { selection = .kind(.camera) })
        case .existingFilterWheel(let id):
            if let filterWheel = filterWheels.first(where: { $0.persistentModelID == id }) {
                FilterWheelEditForm(filterWheel: filterWheel, onSaved: { selection = .existingFilterWheel($0.persistentModelID) }, onFinished: { selection = .kind(.filterWheel) })
                    .id(id)
            } else { placeholder }
        case .newFilterWheel:
            FilterWheelEditForm(filterWheel: nil, onSaved: { selection = .existingFilterWheel($0.persistentModelID) }, onFinished: { selection = .kind(.filterWheel) })
        case .existingRotator(let id):
            if let rotator = rotators.first(where: { $0.persistentModelID == id }) {
                RotatorEditForm(rotator: rotator, onSaved: { selection = .existingRotator($0.persistentModelID) }, onFinished: { selection = .kind(.rotator) })
                    .id(id)
            } else { placeholder }
        case .newRotator:
            RotatorEditForm(rotator: nil, onSaved: { selection = .existingRotator($0.persistentModelID) }, onFinished: { selection = .kind(.rotator) })
        case .existingGuideCamera(let id):
            if let camera = guideCameras.first(where: { $0.persistentModelID == id }) {
                GuideCameraEditForm(guideCamera: camera, onSaved: { selection = .existingGuideCamera($0.persistentModelID) }, onFinished: { selection = .kind(.guideCamera) })
                    .id(id)
            } else { placeholder }
        case .newGuideCamera:
            GuideCameraEditForm(guideCamera: nil, onSaved: { selection = .existingGuideCamera($0.persistentModelID) }, onFinished: { selection = .kind(.guideCamera) })
        case .existingStandalone(let id):
            if let equipment = standaloneEquipment.first(where: { $0.persistentModelID == id }) {
                StandaloneEquipmentEditForm(equipment: equipment, role: equipment.role, onSaved: { selection = .existingStandalone($0.persistentModelID) }, onFinished: { selection = .kind(kind(for: equipment.role)) })
                    .id(id)
            } else { placeholder }
        case .newStandalone(let role):
            StandaloneEquipmentEditForm(equipment: nil, role: role, onSaved: { selection = .existingStandalone($0.persistentModelID) }, onFinished: { selection = .kind(kind(for: role)) })
        case nil:
            placeholder
        }
    }

    private func kind(for role: StandaloneEquipmentRole) -> EquipmentKind {
        switch role {
        case .powerHub: return .powerHub
        case .flatScreen: return .flatScreen
        case .dewHeater: return .dewHeater
        case .observatoryControl: return .observatoryControl
        }
    }

    /// The "select Cameras, see a list of cameras you own with a plus button" panel — reachable
    /// either from here or by expanding the sidebar's own children, both converging on the same
    /// `Selection` cases.
    @ViewBuilder
    private func kindOverview(for kind: EquipmentKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // The shared header, not hand-rolled chrome — keeps this pane's "+" identical in
            // styling and height to every other Settings pane's (borderless glyph, 12pt vertical
            // padding); an inline `Label("Add", systemImage:)` in a default-styled Button rendered
            // as a bordered "+ Add" and made this header taller than its siblings'.
            SettingsPaneHeader(
                title: kind.title,
                addHelp: "Add \(kind.singularTitle)",
                onAdd: { selection = newSelection(for: kind) }
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
                    Button(action: { selection = instance.selection }) {
                        Text(instance.name)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func newSelection(for kind: EquipmentKind) -> Selection {
        switch kind {
        case .mount: return .newMount
        case .opticalAssembly: return .newOpticalAssembly(.mainImaging)
        case .guideOpticalAssembly: return .newOpticalAssembly(.guideScope)
        case .camera: return .newCamera
        case .filterWheel: return .newFilterWheel
        case .rotator: return .newRotator
        case .guideCamera: return .newGuideCamera
        case .powerHub, .flatScreen, .dewHeater, .observatoryControl:
            return .newStandalone(kind.standaloneRole!)
        }
    }

    private var placeholder: some View {
        Text("Select a piece of equipment, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
