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

    /// Which kinds are showing their records. All of them by default — the point of the tree is
    /// seeing what you own.
    @State private var expandedKinds: Set<EquipmentKind> = Set(EquipmentKind.allCases)
    /// Selection *within* the type-overview list, independent of the sidebar's — it drives that
    /// list's own "−" so a record can be removed without leaving the overview.
    @State private var overviewSelection: PersistentIdentifier?

    /// One owned record's row data, independent of where it's rendered — the sidebar's children
    /// and the type overview's list are two views of the same array, which keeps them in step.
    private struct Instance {
        let id: PersistentIdentifier
        let name: String
    }

    /// The single per-kind lookup. A new equipment kind means one case here (plus its
    /// `EquipmentKind` case and a branch in `editor(for:)`, `insert(into:)` and `deleteRecord(_:)`).
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            // Built explicitly rather than with `OutlineGroup`. Two reasons: `OutlineGroup`
            // swallowed the first click on a parent row (selecting a kind while a record of that
            // kind was selected took two clicks, because the row's own disclosure handling consumed
            // one), and it only insets rows it considers expandable, so an empty kind sat at a
            // different indent from a populated one and the list shifted the moment the first
            // record was added. Owning the layout fixes both: the chevron's width is always
            // reserved, and a plain tagged row selects on a single click like any other List row.
            List(selection: $selection) {
                ForEach(EquipmentKind.allCases, id: \.self) { kind in
                    kindRow(for: kind)
                    if expandedKinds.contains(kind) {
                        ForEach(instances(for: kind), id: \.id) { instance in
                            instanceRow(for: instance)
                        }
                    }
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

    private func kindRow(for kind: EquipmentKind) -> some View {
        let hasRecords = !instances(for: kind).isEmpty
        return HStack(spacing: 4) {
            Button {
                if expandedKinds.contains(kind) {
                    expandedKinds.remove(kind)
                } else {
                    expandedKinds.insert(kind)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expandedKinds.contains(kind) ? 90 : 0))
            }
            .buttonStyle(.plain)
            // Width is reserved whether or not there's a chevron to draw, so every kind's title
            // lines up and nothing shifts when a kind gains its first record.
            .frame(width: 12)
            .opacity(hasRecords ? 1 : 0)
            .disabled(!hasRecords)

            Label(kind.title, systemImage: kind.icon)
            Spacer()
        }
        .tag(Selection.kind(kind))
    }

    private func instanceRow(for instance: Instance) -> some View {
        HStack {
            Text(instance.name)
                .padding(.leading, Self.instanceIndent)
            Spacer()
        }
        .tag(Selection.existing(instance.id))
    }

    /// Lines a record's name up with its kind's *title* rather than its icon: the chevron column
    /// (12) plus the row's spacing (4) plus the `Label`'s icon and its own internal spacing (~24).
    /// Sitting under the icon — which a smaller inset gives — leaves the two levels looking almost
    /// flush and the hierarchy hard to read.
    private static let instanceIndent: CGFloat = 40

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

    /// The "select Cameras, see a list of what you own" panel. Its "+"/"−" pair manages that
    /// kind's records in place: "−" acts on `overviewSelection`, this list's *own* selection, so a
    /// record can be removed without first navigating to it in the sidebar. Double-clicking a row
    /// opens it for editing (single click just selects, the macOS list convention).
    @ViewBuilder
    private func kindOverview(for kind: EquipmentKind) -> some View {
        let rows = instances(for: kind)
        VStack(alignment: .leading, spacing: 0) {
            SettingsPaneHeader(
                title: kind.title,
                addHelp: "Add \(kind.singularTitle)",
                onAdd: { insert(into: kind) },
                isRemoveDisabled: overviewSelection == nil,
                removeHelp: "Remove the selected \(kind.singularTitle.lowercased())",
                onRemove: { if let overviewSelection { confirmDelete(overviewSelection) } }
            )
            Divider()
            if rows.isEmpty {
                Text("None defined yet.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer()
            } else {
                List(rows, id: \.id, selection: $overviewSelection) { instance in
                    Text(instance.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // `simultaneousGesture`, not `onTapGesture`, so the List's own single-click
                        // selection still runs — a plain tap gesture would swallow it.
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            selection = .existing(instance.id)
                        })
                        .tag(instance.id)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        // Selecting a different kind starts that kind's list with nothing selected, rather than
        // carrying a stale id belonging to another kind into its "−".
        .onChange(of: kind) { overviewSelection = nil }
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
