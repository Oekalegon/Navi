//
//  EquipmentSettingsPane.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import SwiftUI
import SwiftData
import INDIMCPKit

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
/// The sidebar is an `OutlineGroup` (the same pattern built for the Rig sidebar earlier this
/// session): each equipment *kind* is itself a selectable row (no per-row "+"), showing a "list of
/// what you own + Add" overview on the right when selected; its owned instances render as indented,
/// selectable children (name + delete only). `.listStyle(.plain)`, not `.sidebar` — the `.sidebar`
/// vibrancy background is designed for `NavigationSplitView`, not this plain `HStack` sidebar, and
/// renders as an unwanted opaque box outside that context; `.plain` is also what removes the row
/// separator line between items.
///
/// Optical Assembly is split into two fixed-purpose kinds (matching `RigEditForm`'s existing
/// `mainOpticalAssemblies`/`guideOpticalAssemblies` split) rather than exposing a raw `purpose`
/// picker — same reasoning `OpticalAssemblyEditForm`'s `purpose` parameter already encodes.
///
/// Fetches `telescope.driverCatalog()` once and shares it with whichever edit form is active via
/// `sharedDrivers:`, mirroring how `RigEditForm` already shares `liveDevices` across its device
/// pickers.
struct EquipmentSettingsPane: View {
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared

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
    @State private var driverCatalog: [DriverInfo] = []

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

    private var topLevelNodes: [SidebarNode] {
        var mountChildren: [SidebarNode] = []
        for mount in mounts {
            mountChildren.append(childNode(name: mount.name, icon: EquipmentKind.mount.icon, selection: .existingMount(mount.persistentModelID), onDelete: { self.delete(mount) }))
        }
        var opticalAssemblyChildren: [SidebarNode] = []
        for assembly in mainOpticalAssemblies {
            opticalAssemblyChildren.append(childNode(name: assembly.name, icon: EquipmentKind.opticalAssembly.icon, selection: .existingOpticalAssembly(assembly.persistentModelID), onDelete: { self.delete(assembly) }))
        }
        var guideOpticalAssemblyChildren: [SidebarNode] = []
        for assembly in guideOpticalAssemblies {
            guideOpticalAssemblyChildren.append(childNode(name: assembly.name, icon: EquipmentKind.guideOpticalAssembly.icon, selection: .existingOpticalAssembly(assembly.persistentModelID), onDelete: { self.delete(assembly) }))
        }
        var cameraChildren: [SidebarNode] = []
        for camera in cameras {
            cameraChildren.append(childNode(name: camera.name, icon: EquipmentKind.camera.icon, selection: .existingCamera(camera.persistentModelID), onDelete: { self.delete(camera) }))
        }
        var filterWheelChildren: [SidebarNode] = []
        for filterWheel in filterWheels {
            filterWheelChildren.append(childNode(name: filterWheel.name, icon: EquipmentKind.filterWheel.icon, selection: .existingFilterWheel(filterWheel.persistentModelID), onDelete: { self.delete(filterWheel) }))
        }
        var rotatorChildren: [SidebarNode] = []
        for rotator in rotators {
            rotatorChildren.append(childNode(name: rotator.name, icon: EquipmentKind.rotator.icon, selection: .existingRotator(rotator.persistentModelID), onDelete: { self.delete(rotator) }))
        }
        var guideCameraChildren: [SidebarNode] = []
        for camera in guideCameras {
            guideCameraChildren.append(childNode(name: camera.name, icon: EquipmentKind.guideCamera.icon, selection: .existingGuideCamera(camera.persistentModelID), onDelete: { self.delete(camera) }))
        }
        var powerHubChildren: [SidebarNode] = []
        for equipment in standaloneEquipment(for: .powerHub) {
            powerHubChildren.append(childNode(name: equipment.name, icon: EquipmentKind.powerHub.icon, selection: .existingStandalone(equipment.persistentModelID), onDelete: { self.delete(equipment) }))
        }
        var flatScreenChildren: [SidebarNode] = []
        for equipment in standaloneEquipment(for: .flatScreen) {
            flatScreenChildren.append(childNode(name: equipment.name, icon: EquipmentKind.flatScreen.icon, selection: .existingStandalone(equipment.persistentModelID), onDelete: { self.delete(equipment) }))
        }
        var dewHeaterChildren: [SidebarNode] = []
        for equipment in standaloneEquipment(for: .dewHeater) {
            dewHeaterChildren.append(childNode(name: equipment.name, icon: EquipmentKind.dewHeater.icon, selection: .existingStandalone(equipment.persistentModelID), onDelete: { self.delete(equipment) }))
        }
        var observatoryControlChildren: [SidebarNode] = []
        for equipment in standaloneEquipment(for: .observatoryControl) {
            observatoryControlChildren.append(childNode(name: equipment.name, icon: EquipmentKind.observatoryControl.icon, selection: .existingStandalone(equipment.persistentModelID), onDelete: { self.delete(equipment) }))
        }

        return [
            kindNode(.mount, children: mountChildren),
            kindNode(.opticalAssembly, children: opticalAssemblyChildren),
            kindNode(.guideOpticalAssembly, children: guideOpticalAssemblyChildren),
            kindNode(.camera, children: cameraChildren),
            kindNode(.filterWheel, children: filterWheelChildren),
            kindNode(.rotator, children: rotatorChildren),
            kindNode(.guideCamera, children: guideCameraChildren),
            kindNode(.powerHub, children: powerHubChildren),
            kindNode(.flatScreen, children: flatScreenChildren),
            kindNode(.dewHeater, children: dewHeaterChildren),
            kindNode(.observatoryControl, children: observatoryControlChildren),
        ]
    }

    private func kindNode(_ kind: EquipmentKind, children: [SidebarNode]) -> SidebarNode {
        SidebarNode(title: kind.title, icon: kind.icon, selection: .kind(kind), children: children)
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
        .task(id: telescope.state) {
            // Keyed on `telescope.state`, not a plain `.task { }` — this pane's `.id(Tab.equipment)`
            // keeps it alive across tab switches (it isn't recreated), so a plain one-shot `.task`
            // would leave every `DriverPickerField`'s `sharedDrivers` permanently empty if the user
            // opens Settings before connecting and only connects afterward.
            guard telescope.state == .connected else { return }
            driverCatalog = (try? await telescope.driverCatalog()) ?? []
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
        .listStyle(.plain)
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
                MountEditForm(mount: mount, sharedDrivers: driverCatalog, onSaved: { selection = .existingMount($0.persistentModelID) }, onFinished: { selection = .kind(.mount) })
                    .id(id)
            } else { placeholder }
        case .newMount:
            MountEditForm(mount: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingMount($0.persistentModelID) }, onFinished: { selection = .kind(.mount) })
        case .existingOpticalAssembly(let id):
            if let assembly = opticalAssemblies.first(where: { $0.persistentModelID == id }) {
                OpticalAssemblyEditForm(opticalAssembly: assembly, purpose: assembly.purpose, sharedDrivers: driverCatalog, onSaved: { selection = .existingOpticalAssembly($0.persistentModelID) }, onFinished: { selection = .kind(assembly.purpose == .mainImaging ? .opticalAssembly : .guideOpticalAssembly) })
                    .id(id)
            } else { placeholder }
        case .newOpticalAssembly(let purpose):
            OpticalAssemblyEditForm(opticalAssembly: nil, purpose: purpose, sharedDrivers: driverCatalog, onSaved: { selection = .existingOpticalAssembly($0.persistentModelID) }, onFinished: { selection = .kind(purpose == .mainImaging ? .opticalAssembly : .guideOpticalAssembly) })
        case .existingCamera(let id):
            if let camera = cameras.first(where: { $0.persistentModelID == id }) {
                CameraEditForm(camera: camera, sharedDrivers: driverCatalog, onSaved: { selection = .existingCamera($0.persistentModelID) }, onFinished: { selection = .kind(.camera) })
                    .id(id)
            } else { placeholder }
        case .newCamera:
            CameraEditForm(camera: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingCamera($0.persistentModelID) }, onFinished: { selection = .kind(.camera) })
        case .existingFilterWheel(let id):
            if let filterWheel = filterWheels.first(where: { $0.persistentModelID == id }) {
                FilterWheelEditForm(filterWheel: filterWheel, sharedDrivers: driverCatalog, onSaved: { selection = .existingFilterWheel($0.persistentModelID) }, onFinished: { selection = .kind(.filterWheel) })
                    .id(id)
            } else { placeholder }
        case .newFilterWheel:
            FilterWheelEditForm(filterWheel: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingFilterWheel($0.persistentModelID) }, onFinished: { selection = .kind(.filterWheel) })
        case .existingRotator(let id):
            if let rotator = rotators.first(where: { $0.persistentModelID == id }) {
                RotatorEditForm(rotator: rotator, sharedDrivers: driverCatalog, onSaved: { selection = .existingRotator($0.persistentModelID) }, onFinished: { selection = .kind(.rotator) })
                    .id(id)
            } else { placeholder }
        case .newRotator:
            RotatorEditForm(rotator: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingRotator($0.persistentModelID) }, onFinished: { selection = .kind(.rotator) })
        case .existingGuideCamera(let id):
            if let camera = guideCameras.first(where: { $0.persistentModelID == id }) {
                GuideCameraEditForm(guideCamera: camera, sharedDrivers: driverCatalog, onSaved: { selection = .existingGuideCamera($0.persistentModelID) }, onFinished: { selection = .kind(.guideCamera) })
                    .id(id)
            } else { placeholder }
        case .newGuideCamera:
            GuideCameraEditForm(guideCamera: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingGuideCamera($0.persistentModelID) }, onFinished: { selection = .kind(.guideCamera) })
        case .existingStandalone(let id):
            if let equipment = standaloneEquipment.first(where: { $0.persistentModelID == id }) {
                StandaloneEquipmentEditForm(equipment: equipment, role: equipment.role, sharedDrivers: driverCatalog, onSaved: { selection = .existingStandalone($0.persistentModelID) }, onFinished: { selection = .kind(kind(for: equipment.role)) })
                    .id(id)
            } else { placeholder }
        case .newStandalone(let role):
            StandaloneEquipmentEditForm(equipment: nil, role: role, sharedDrivers: driverCatalog, onSaved: { selection = .existingStandalone($0.persistentModelID) }, onFinished: { selection = .kind(kind(for: role)) })
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
            HStack {
                Text(kind.title)
                    .font(.headline)
                Spacer()
                Button(action: { selection = newSelection(for: kind) }) {
                    Label("Add", systemImage: "plus")
                }
            }
            .padding(16)
            Divider()
            let rows = instanceRows(for: kind)
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
                .listStyle(.plain)
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

    private func instanceRows(for kind: EquipmentKind) -> [(id: PersistentIdentifier, name: String, selection: Selection)] {
        switch kind {
        case .mount:
            return mounts.map { ($0.persistentModelID, $0.name, .existingMount($0.persistentModelID)) }
        case .opticalAssembly:
            return mainOpticalAssemblies.map { ($0.persistentModelID, $0.name, .existingOpticalAssembly($0.persistentModelID)) }
        case .guideOpticalAssembly:
            return guideOpticalAssemblies.map { ($0.persistentModelID, $0.name, .existingOpticalAssembly($0.persistentModelID)) }
        case .camera:
            return cameras.map { ($0.persistentModelID, $0.name, .existingCamera($0.persistentModelID)) }
        case .filterWheel:
            return filterWheels.map { ($0.persistentModelID, $0.name, .existingFilterWheel($0.persistentModelID)) }
        case .rotator:
            return rotators.map { ($0.persistentModelID, $0.name, .existingRotator($0.persistentModelID)) }
        case .guideCamera:
            return guideCameras.map { ($0.persistentModelID, $0.name, .existingGuideCamera($0.persistentModelID)) }
        case .powerHub, .flatScreen, .dewHeater, .observatoryControl:
            return standaloneEquipment(for: kind.standaloneRole!).map { ($0.persistentModelID, $0.name, .existingStandalone($0.persistentModelID)) }
        }
    }

    private var placeholder: some View {
        Text("Select a piece of equipment, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ mount: MountProfile) {
        pendingDeletion = (mount.name, {
            if selection == .existingMount(mount.persistentModelID) { selection = .kind(.mount) }
            modelContext.delete(mount)
            try? modelContext.save()
        })
    }

    private func delete(_ assembly: OpticalAssemblyProfile) {
        let kind: EquipmentKind = assembly.purpose == .mainImaging ? .opticalAssembly : .guideOpticalAssembly
        pendingDeletion = (assembly.name, {
            if selection == .existingOpticalAssembly(assembly.persistentModelID) { selection = .kind(kind) }
            modelContext.delete(assembly)
            try? modelContext.save()
        })
    }

    private func delete(_ camera: CameraProfile) {
        pendingDeletion = (camera.name, {
            if selection == .existingCamera(camera.persistentModelID) { selection = .kind(.camera) }
            modelContext.delete(camera)
            try? modelContext.save()
        })
    }

    private func delete(_ filterWheel: FilterWheelProfile) {
        pendingDeletion = (filterWheel.name, {
            if selection == .existingFilterWheel(filterWheel.persistentModelID) { selection = .kind(.filterWheel) }
            modelContext.delete(filterWheel)
            try? modelContext.save()
        })
    }

    private func delete(_ rotator: RotatorProfile) {
        pendingDeletion = (rotator.name, {
            if selection == .existingRotator(rotator.persistentModelID) { selection = .kind(.rotator) }
            modelContext.delete(rotator)
            try? modelContext.save()
        })
    }

    private func delete(_ camera: GuideCameraProfile) {
        pendingDeletion = (camera.name, {
            if selection == .existingGuideCamera(camera.persistentModelID) { selection = .kind(.guideCamera) }
            modelContext.delete(camera)
            try? modelContext.save()
        })
    }

    private func delete(_ equipment: StandaloneEquipmentProfile) {
        let kind = kind(for: equipment.role)
        pendingDeletion = (equipment.name, {
            if selection == .existingStandalone(equipment.persistentModelID) { selection = .kind(kind) }
            modelContext.delete(equipment)
            try? modelContext.save()
        })
    }
}
