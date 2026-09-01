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
/// Optical Assembly (main and guide), Imaging Train, Guide Camera, and the four standalone roles
/// (Power Hub, Flat Screen, Dew Heater, Observatory Control) — gets its own browsable/editable
/// section here, independent of any Rig. `RigEditForm` only *picks* from what's defined here; it no
/// longer creates or edits equipment inline (NAVI-85 superseded that).
///
/// Deliberately a plain `HStack`, not `NavigationSplitView` — see `ServerSettingsPane`'s doc
/// comment for why (the same window-toolbar-chrome conflict with the enclosing `TabView`).
///
/// Optical Assembly is split into two fixed-purpose sections (matching `RigEditForm`'s existing
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
    @Query(sort: \ImagingTrainProfile.name) private var imagingTrains: [ImagingTrainProfile]
    @Query(sort: \GuideCameraProfile.name) private var guideCameras: [GuideCameraProfile]
    @Query(sort: \StandaloneEquipmentProfile.name) private var standaloneEquipment: [StandaloneEquipmentProfile]

    private var mainOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .mainImaging } }
    private var guideOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .guideScope } }
    private func standaloneEquipment(for role: StandaloneEquipmentRole) -> [StandaloneEquipmentProfile] {
        standaloneEquipment.filter { $0.role == role }
    }

    private enum Selection: Hashable {
        case existingMount(PersistentIdentifier)
        case newMount
        case existingOpticalAssembly(PersistentIdentifier)
        case newOpticalAssembly(OpticalAssemblyPurpose)
        case existingImagingTrain(PersistentIdentifier)
        case newImagingTrain
        case existingGuideCamera(PersistentIdentifier)
        case newGuideCamera
        case existingStandalone(PersistentIdentifier)
        case newStandalone(StandaloneEquipmentRole)
    }
    @State private var selection: Selection?
    @State private var pendingDeletion: (name: String, action: () -> Void)?
    @State private var driverCatalog: [DriverInfo] = []

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
            // opens Settings before connecting and only connects afterward. Re-fetches whenever the
            // connection state changes, matching how the connected/disconnected transition is
            // already the trigger elsewhere (e.g. `ServerSettingsPane`'s `DriverManagementSheet`).
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
            Text("Any rig using this will have that role cleared, not deleted, before it can connect again.")
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            librarySection(title: "Mounts", onAdd: { selection = .newMount }) {
                ForEach(mounts) { mount in
                    row(name: mount.name, onDelete: { delete(mount) })
                        .tag(Selection.existingMount(mount.persistentModelID))
                }
            }
            librarySection(title: "Optical Assemblies", onAdd: { selection = .newOpticalAssembly(.mainImaging) }) {
                ForEach(mainOpticalAssemblies) { assembly in
                    row(name: assembly.name, onDelete: { delete(assembly) })
                        .tag(Selection.existingOpticalAssembly(assembly.persistentModelID))
                }
            }
            librarySection(title: "Guide Optical Assemblies", onAdd: { selection = .newOpticalAssembly(.guideScope) }) {
                ForEach(guideOpticalAssemblies) { assembly in
                    row(name: assembly.name, onDelete: { delete(assembly) })
                        .tag(Selection.existingOpticalAssembly(assembly.persistentModelID))
                }
            }
            librarySection(title: "Imaging Trains", onAdd: { selection = .newImagingTrain }) {
                ForEach(imagingTrains) { train in
                    row(name: train.name, onDelete: { delete(train) })
                        .tag(Selection.existingImagingTrain(train.persistentModelID))
                }
            }
            librarySection(title: "Guide Cameras", onAdd: { selection = .newGuideCamera }) {
                ForEach(guideCameras) { camera in
                    row(name: camera.name, onDelete: { delete(camera) })
                        .tag(Selection.existingGuideCamera(camera.persistentModelID))
                }
            }
            ForEach(StandaloneEquipmentRole.allCases, id: \.self) { role in
                librarySection(title: "\(role.title)s", onAdd: { selection = .newStandalone(role) }) {
                    ForEach(standaloneEquipment(for: role)) { equipment in
                        row(name: equipment.name, onDelete: { delete(equipment) })
                            .tag(Selection.existingStandalone(equipment.persistentModelID))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func librarySection(title: String, onAdd: @escaping () -> Void, @ViewBuilder rows: () -> some View) -> some View {
        Section {
            rows()
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Add \(title.hasSuffix("s") ? String(title.dropLast()) : title)")
            }
        }
    }

    private func row(name: String, onDelete: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .existingMount(let id):
            if let mount = mounts.first(where: { $0.persistentModelID == id }) {
                MountEditForm(mount: mount, sharedDrivers: driverCatalog, onSaved: { selection = .existingMount($0.persistentModelID) }, onFinished: { selection = nil })
                    .id(id)
            } else { placeholder }
        case .newMount:
            MountEditForm(mount: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingMount($0.persistentModelID) }, onFinished: { selection = nil })
        case .existingOpticalAssembly(let id):
            if let assembly = opticalAssemblies.first(where: { $0.persistentModelID == id }) {
                OpticalAssemblyEditForm(opticalAssembly: assembly, purpose: assembly.purpose, sharedDrivers: driverCatalog, onSaved: { selection = .existingOpticalAssembly($0.persistentModelID) }, onFinished: { selection = nil })
                    .id(id)
            } else { placeholder }
        case .newOpticalAssembly(let purpose):
            OpticalAssemblyEditForm(opticalAssembly: nil, purpose: purpose, sharedDrivers: driverCatalog, onSaved: { selection = .existingOpticalAssembly($0.persistentModelID) }, onFinished: { selection = nil })
        case .existingImagingTrain(let id):
            if let train = imagingTrains.first(where: { $0.persistentModelID == id }) {
                ImagingTrainEditForm(imagingTrain: train, sharedDrivers: driverCatalog, onSaved: { selection = .existingImagingTrain($0.persistentModelID) }, onFinished: { selection = nil })
                    .id(id)
            } else { placeholder }
        case .newImagingTrain:
            ImagingTrainEditForm(imagingTrain: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingImagingTrain($0.persistentModelID) }, onFinished: { selection = nil })
        case .existingGuideCamera(let id):
            if let camera = guideCameras.first(where: { $0.persistentModelID == id }) {
                GuideCameraEditForm(guideCamera: camera, sharedDrivers: driverCatalog, onSaved: { selection = .existingGuideCamera($0.persistentModelID) }, onFinished: { selection = nil })
                    .id(id)
            } else { placeholder }
        case .newGuideCamera:
            GuideCameraEditForm(guideCamera: nil, sharedDrivers: driverCatalog, onSaved: { selection = .existingGuideCamera($0.persistentModelID) }, onFinished: { selection = nil })
        case .existingStandalone(let id):
            if let equipment = standaloneEquipment.first(where: { $0.persistentModelID == id }) {
                StandaloneEquipmentEditForm(equipment: equipment, role: equipment.role, sharedDrivers: driverCatalog, onSaved: { selection = .existingStandalone($0.persistentModelID) }, onFinished: { selection = nil })
                    .id(id)
            } else { placeholder }
        case .newStandalone(let role):
            StandaloneEquipmentEditForm(equipment: nil, role: role, sharedDrivers: driverCatalog, onSaved: { selection = .existingStandalone($0.persistentModelID) }, onFinished: { selection = nil })
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        Text("Select a piece of equipment, or add a new one.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ mount: MountProfile) {
        pendingDeletion = (mount.name, {
            if selection == .existingMount(mount.persistentModelID) { selection = nil }
            modelContext.delete(mount)
            try? modelContext.save()
        })
    }

    private func delete(_ assembly: OpticalAssemblyProfile) {
        pendingDeletion = (assembly.name, {
            if selection == .existingOpticalAssembly(assembly.persistentModelID) { selection = nil }
            modelContext.delete(assembly)
            try? modelContext.save()
        })
    }

    private func delete(_ train: ImagingTrainProfile) {
        pendingDeletion = (train.name, {
            if selection == .existingImagingTrain(train.persistentModelID) { selection = nil }
            modelContext.delete(train)
            try? modelContext.save()
        })
    }

    private func delete(_ camera: GuideCameraProfile) {
        pendingDeletion = (camera.name, {
            if selection == .existingGuideCamera(camera.persistentModelID) { selection = nil }
            modelContext.delete(camera)
            try? modelContext.save()
        })
    }

    private func delete(_ equipment: StandaloneEquipmentProfile) {
        pendingDeletion = (equipment.name, {
            if selection == .existingStandalone(equipment.persistentModelID) { selection = nil }
            modelContext.delete(equipment)
            try? modelContext.save()
        })
    }
}
