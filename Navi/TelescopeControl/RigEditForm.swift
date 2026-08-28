//
//  RigEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// Add/edit form for one `RigProfile` (§4.2's Rig pane) — the full CRUD editor built on the
/// equipment library (§4.3). Every role (mount, optical assembly, guide optical assembly,
/// imaging train, guide camera) is individually selectable/deselectable: pick an existing library
/// entity, create a new one inline, or edit the selected one — all via the small per-entity edit
/// forms (`MountEditForm`, `OpticalAssemblyEditForm`, `ImagingTrainEditForm`,
/// `GuideCameraEditForm`), which own their own local scratch state the same way
/// `ServerEditForm`/`ObservatoryEditForm` do. Non-device fields on those entities are editable
/// offline; only the `device` bindings (surfaced there via `DevicePickerField`) require a live
/// connection.
///
/// `rig == nil` means "creating a new one." Saving here does two things in order: flattens the
/// current selection into `[Component]` via `RigProfile.makeComponents()` (surfacing
/// `RigProfileTranslationError.duplicateRole` inline rather than crashing — §4.2's duplicate-role
/// guard), then pushes it with `saveRig` — which needs a live connection, unlike the library-entity
/// sub-editors above. `lastResyncedAt` is stamped on success, matching the resync-staleness
/// contract in `RigProfile`'s own doc comment.
struct RigEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    let rig: RigProfile?

    @Query(sort: \MountProfile.name) private var mounts: [MountProfile]
    @Query(sort: \OpticalAssemblyProfile.name) private var opticalAssemblies: [OpticalAssemblyProfile]
    @Query(sort: \ImagingTrainProfile.name) private var imagingTrains: [ImagingTrainProfile]
    @Query(sort: \GuideCameraProfile.name) private var guideCameras: [GuideCameraProfile]
    @Query(sort: \ServerProfile.name) private var servers: [ServerProfile]
    @Query(sort: \ObservatoryProfile.name) private var cachedObservatories: [ObservatoryProfile]

    @State private var name = ""
    @State private var mount: MountProfile?
    @State private var opticalAssembly: OpticalAssemblyProfile?
    @State private var guideOpticalAssembly: OpticalAssemblyProfile?
    @State private var imagingTrain: ImagingTrainProfile?
    @State private var guideCamera: GuideCameraProfile?
    @State private var defaultObservatoryID: String?
    @State private var defaultServer: ServerProfile?
    @State private var standaloneComponents: [StandaloneComponentEntry] = []

    @State private var liveObservatories: [ObservatorySummary] = []
    // Fetched once here rather than letting each standalone-component row's DevicePickerField
    // independently re-issue the same liveDeviceNames() call — see DevicePickerField.sharedDevices.
    @State private var liveDevices: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    // ActiveSheet covers every sub-editor this form can present — one optional instead of ten
    // separate `showingX`/`showingY` booleans, since exactly one can be open at a time.
    private enum ActiveSheet: Identifiable {
        case mount(MountProfile?)
        case opticalAssembly(OpticalAssemblyProfile?)
        case guideOpticalAssembly(OpticalAssemblyProfile?)
        case imagingTrain(ImagingTrainProfile?)
        case guideCamera(GuideCameraProfile?)

        var id: String {
            switch self {
            case .mount(let m): return "mount-\(m?.persistentModelID.hashValue ?? 0)"
            case .opticalAssembly(let o): return "oa-\(o?.persistentModelID.hashValue ?? 0)"
            case .guideOpticalAssembly(let o): return "goa-\(o?.persistentModelID.hashValue ?? 0)"
            case .imagingTrain(let t): return "train-\(t?.persistentModelID.hashValue ?? 0)"
            case .guideCamera(let g): return "guide-\(g?.persistentModelID.hashValue ?? 0)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    private var isConnected: Bool { telescope.state == .connected }
    private var mainOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .mainImaging } }
    private var guideOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .guideScope } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LabeledField("Rig Name") {
                        TextField("Backyard EQ6-R Rig", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    roleSection(
                        title: "Mount",
                        isIncluded: mount != nil,
                        onToggle: { included in mount = included ? (mount ?? mounts.first) : nil },
                        summary: mount.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Mount", selection: $mount) {
                                Text("None").tag(MountProfile?.none)
                                ForEach(mounts) { Text($0.name).tag(MountProfile?.some($0)) }
                            }
                            .labelsHidden()
                        },
                        onNew: { activeSheet = .mount(nil) },
                        onEdit: mount.map { m in { activeSheet = .mount(m) } }
                    )

                    roleSection(
                        title: "Optical Assembly",
                        isIncluded: opticalAssembly != nil,
                        onToggle: { included in opticalAssembly = included ? (opticalAssembly ?? mainOpticalAssemblies.first) : nil },
                        summary: opticalAssembly.map { roleSummary(name: $0.name, deviceName: $0.hasFocuser ? $0.focuserDeviceName : nil, deviceLabel: "Focuser") },
                        picker: {
                            Picker("Optical Assembly", selection: $opticalAssembly) {
                                Text("None").tag(OpticalAssemblyProfile?.none)
                                ForEach(mainOpticalAssemblies) { Text($0.name).tag(OpticalAssemblyProfile?.some($0)) }
                            }
                            .labelsHidden()
                        },
                        onNew: { activeSheet = .opticalAssembly(nil) },
                        onEdit: opticalAssembly.map { o in { activeSheet = .opticalAssembly(o) } }
                    )

                    roleSection(
                        title: "Guide Optical Assembly",
                        isIncluded: guideOpticalAssembly != nil,
                        onToggle: { included in guideOpticalAssembly = included ? (guideOpticalAssembly ?? guideOpticalAssemblies.first) : nil },
                        summary: guideOpticalAssembly.map { roleSummary(name: $0.name, deviceName: $0.hasFocuser ? $0.focuserDeviceName : nil, deviceLabel: "Focuser") },
                        picker: {
                            Picker("Guide Optical Assembly", selection: $guideOpticalAssembly) {
                                Text("None").tag(OpticalAssemblyProfile?.none)
                                ForEach(guideOpticalAssemblies) { Text($0.name).tag(OpticalAssemblyProfile?.some($0)) }
                            }
                            .labelsHidden()
                        },
                        onNew: { activeSheet = .guideOpticalAssembly(nil) },
                        onEdit: guideOpticalAssembly.map { o in { activeSheet = .guideOpticalAssembly(o) } }
                    )
                    if opticalAssembly?.hasFocuser == true && guideOpticalAssembly?.hasFocuser == true {
                        Label(
                            "Both the optical assembly and guide optical assembly have a focuser — this rig can't be saved until one is removed (INDIMCP-138).",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    roleSection(
                        title: "Imaging Train",
                        isIncluded: imagingTrain != nil,
                        onToggle: { included in imagingTrain = included ? (imagingTrain ?? imagingTrains.first) : nil },
                        summary: imagingTrain.map { roleSummary(name: $0.name, deviceName: $0.cameraDeviceName, deviceLabel: "Camera") },
                        picker: {
                            Picker("Imaging Train", selection: $imagingTrain) {
                                Text("None").tag(ImagingTrainProfile?.none)
                                ForEach(imagingTrains) { Text($0.name).tag(ImagingTrainProfile?.some($0)) }
                            }
                            .labelsHidden()
                        },
                        onNew: { activeSheet = .imagingTrain(nil) },
                        onEdit: imagingTrain.map { t in { activeSheet = .imagingTrain(t) } }
                    )

                    roleSection(
                        title: "Guide Camera",
                        isIncluded: guideCamera != nil,
                        onToggle: { included in guideCamera = included ? (guideCamera ?? guideCameras.first) : nil },
                        summary: guideCamera.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Guide Camera", selection: $guideCamera) {
                                Text("None").tag(GuideCameraProfile?.none)
                                ForEach(guideCameras) { Text($0.name).tag(GuideCameraProfile?.some($0)) }
                            }
                            .labelsHidden()
                        },
                        onNew: { activeSheet = .guideCamera(nil) },
                        onEdit: guideCamera.map { g in { activeSheet = .guideCamera(g) } }
                    )

                    Divider()
                    Text("Standalone Components").font(.subheadline).fontWeight(.semibold)
                    Text("No reusable library entity — just a device binding for this rig (§4.3).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    standaloneRow(role: "powerHub", title: "Power Hub")
                    standaloneRow(role: "observatoryControl", title: "Observatory Control (roof/dome)")
                    standaloneRow(role: "flatScreen", title: "Flat Screen")
                    standaloneRow(role: "dewHeater", title: "Dew Heater")

                    Divider()
                    LabeledField("Default Observatory") {
                        Picker("Default Observatory", selection: $defaultObservatoryID) {
                            Text("None").tag(String?.none)
                            ForEach(observatoryOptions, id: \.id) { observatory in
                                Text(observatory.name).tag(String?.some(observatory.id))
                            }
                        }
                        .labelsHidden()
                    }
                    LabeledField("Default Server") {
                        Picker("Default Server", selection: $defaultServer) {
                            Text("None").tag(ServerProfile?.none)
                            ForEach(servers) { Text($0.name).tag(ServerProfile?.some($0)) }
                        }
                        .labelsHidden()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
        .task {
            load()
            await refreshObservatories()
            await refreshLiveDevices()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .mount(let m):
                MountEditForm(mount: m) { mount = $0 }
            case .opticalAssembly(let o):
                OpticalAssemblyEditForm(opticalAssembly: o, purpose: .mainImaging) { opticalAssembly = $0 }
            case .guideOpticalAssembly(let o):
                OpticalAssemblyEditForm(opticalAssembly: o, purpose: .guideScope) { guideOpticalAssembly = $0 }
            case .imagingTrain(let t):
                ImagingTrainEditForm(imagingTrain: t) { imagingTrain = $0 }
            case .guideCamera(let g):
                GuideCameraEditForm(guideCamera: g) { guideCamera = $0 }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(rig == nil ? "Add Rig" : "Edit Rig")
                .font(.headline)
            Spacer()
            if isSaving {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            if !isConnected {
                Text("Connect to save this rig to the server")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { Task { await save() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected || name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var observatoryOptions: [ObservatorySummary] {
        if !liveObservatories.isEmpty { return liveObservatories }
        // Offline fallback: the local cache (§4.1) — may be stale/incomplete, expected per
        // `ObservatoryProfile`'s own doc comment.
        return cachedObservatories.map { ObservatorySummary(id: $0.serverObservatoryID, name: $0.name) }
    }

    private func roleSummary(name: String, deviceName: String?, deviceLabel: String = "Device") -> String {
        if let deviceName {
            return "\(name) · \(deviceLabel): \(deviceName)"
        }
        return "\(name) · \(deviceLabel): blank"
    }

    @ViewBuilder
    private func roleSection(
        title: String,
        isIncluded: Bool,
        onToggle: @escaping (Bool) -> Void,
        summary: String?,
        @ViewBuilder picker: () -> some View,
        onNew: @escaping () -> Void,
        onEdit: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: Binding(get: { isIncluded }, set: onToggle))
                .font(.subheadline)
                .fontWeight(.semibold)
            if isIncluded {
                picker()
                if let summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(summary.hasSuffix("blank") ? .orange : .secondary)
                }
                HStack {
                    Button("New…", action: onNew)
                    if let onEdit {
                        Button("Edit…", action: onEdit)
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func standaloneRow(role: String, title: String) -> some View {
        let index = standaloneComponents.firstIndex { $0.role == role }
        let isIncluded = index != nil
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: Binding(
                get: { isIncluded },
                set: { included in
                    if included {
                        guard standaloneComponents.firstIndex(where: { $0.role == role }) == nil else { return }
                        standaloneComponents.append(StandaloneComponentEntry(id: role, role: role))
                    } else {
                        standaloneComponents.removeAll { $0.role == role }
                    }
                }
            ))
            if let index {
                DevicePickerField(
                    label: "\(title) INDI Device",
                    deviceName: Binding(
                        get: { standaloneComponents[index].deviceName },
                        set: { standaloneComponents[index].deviceName = $0 }
                    ),
                    sharedDevices: liveDevices
                )
            }
        }
    }

    private func load() {
        name = rig?.name ?? ""
        mount = rig?.mount
        opticalAssembly = rig?.opticalAssembly
        guideOpticalAssembly = rig?.guideOpticalAssembly
        imagingTrain = rig?.imagingTrain
        guideCamera = rig?.guideCamera
        defaultObservatoryID = rig?.defaultObservatoryID
        defaultServer = rig?.defaultServer
        standaloneComponents = rig?.standaloneComponents ?? []
    }

    private func refreshObservatories() async {
        guard isConnected else { return }
        liveObservatories = (try? await telescope.listObservatories()) ?? []
    }

    private func refreshLiveDevices() async {
        guard isConnected else { return }
        liveDevices = (try? await telescope.liveDeviceNames()) ?? []
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        errorMessage = nil

        let serverRigID = rig?.serverRigID ?? IDSlug.make(from: trimmedName)

        // Build the flattened component list first — surfaces `RigProfileTranslationError`
        // (e.g. the guide-optical-assembly/optical-assembly focuser collision) before touching
        // SwiftData or the network at all. Computed directly from this form's own @State, not a
        // throwaway RigProfile — none of these picks are persisted yet while composing a new rig.
        let components: [Component]
        do {
            components = try makeRigComponents(
                mount: mount,
                opticalAssembly: opticalAssembly,
                guideOpticalAssembly: guideOpticalAssembly,
                imagingTrain: imagingTrain,
                guideCamera: guideCamera,
                standaloneComponents: standaloneComponents
            )
        } catch {
            errorMessage = (error as? RigProfileTranslationError)?.description ?? "\(error)"
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await telescope.saveRig(
                Rig(id: serverRigID, name: trimmedName, components: components),
                overwrite: rig != nil
            )
            upsertLocalRig(with: saved)
            dismiss()
        } catch {
            errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func upsertLocalRig(with savedRig: Rig) {
        let target = rig ?? {
            let created = RigProfile(serverRigID: savedRig.id, name: savedRig.name)
            modelContext.insert(created)
            return created
        }()
        target.name = savedRig.name
        target.mount = mount
        target.opticalAssembly = opticalAssembly
        target.guideOpticalAssembly = guideOpticalAssembly
        target.imagingTrain = imagingTrain
        target.guideCamera = guideCamera
        target.defaultObservatoryID = defaultObservatoryID
        target.defaultServer = defaultServer
        target.standaloneComponents = standaloneComponents
        target.lastResyncedAt = .now
        try? modelContext.save()
    }
}
