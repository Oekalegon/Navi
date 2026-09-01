//
//  RigEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// Add/edit form for one `RigProfile` (§4.2's Rig pane). NAVI-85: a rig is pure *composition* —
/// for each role, pick which already-defined `EquipmentSettingsPane` library entity this rig uses.
/// There's no inline creation/editing here anymore (that used to drill into `MountEditForm` etc.
/// directly from this form); an empty role's library points the user at the Equipment tab instead
/// (see `selectSettingsTab` in the environment).
///
/// `rig == nil` means "creating a new one." Saving here does two things in order: flattens the
/// current selection into `[Component]` via `RigProfile.makeComponents()` (surfacing
/// `RigProfileTranslationError.duplicateRole` inline rather than crashing — §4.2's duplicate-role
/// guard), then pushes it with `saveRig` — which needs a live connection. `lastResyncedAt` is
/// stamped on success, matching the resync-staleness contract in `RigProfile`'s own doc comment.
struct RigEditForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectSettingsTab) private var selectSettingsTab
    @State private var telescope = TelescopeSessionManager.shared
    let rig: RigProfile?
    /// Called with the saved (inserted-or-mutated) rig after a successful Save, so the caller can
    /// adopt it as the current selection right away.
    var onSaved: (RigProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77) — called on Cancel and after a
    /// successful Save.
    var onFinished: () -> Void = {}

    @Query(sort: \MountProfile.name) private var mounts: [MountProfile]
    @Query(sort: \OpticalAssemblyProfile.name) private var opticalAssemblies: [OpticalAssemblyProfile]
    @Query(sort: \ImagingTrainProfile.name) private var imagingTrains: [ImagingTrainProfile]
    @Query(sort: \GuideCameraProfile.name) private var guideCameras: [GuideCameraProfile]
    @Query(sort: \StandaloneEquipmentProfile.name) private var standaloneEquipment: [StandaloneEquipmentProfile]
    @Query(sort: \ServerProfile.name) private var servers: [ServerProfile]
    @Query(sort: \ObservatoryProfile.name) private var cachedObservatories: [ObservatoryProfile]

    @State private var name = ""
    @State private var mount: MountProfile?
    @State private var opticalAssembly: OpticalAssemblyProfile?
    @State private var guideOpticalAssembly: OpticalAssemblyProfile?
    @State private var imagingTrain: ImagingTrainProfile?
    @State private var guideCamera: GuideCameraProfile?
    @State private var powerHub: StandaloneEquipmentProfile?
    @State private var flatScreen: StandaloneEquipmentProfile?
    @State private var dewHeater: StandaloneEquipmentProfile?
    @State private var observatoryControl: StandaloneEquipmentProfile?
    // Whether each role's toggle is on — deliberately independent of whether an entity is
    // actually selected. Deriving "included" purely from `mount != nil` (etc.) meant that on an
    // empty library, turning a role's toggle on immediately snapped back off — `mount ?? mounts
    // .first` resolves to `nil` when both are empty, so `isIncluded` was still false on the very
    // next render. These track the toggle's own on/off state; `save()`/`makeRigComponents` still
    // only ever look at the underlying `mount`/etc. values.
    @State private var isMountIncluded = false
    @State private var isOpticalAssemblyIncluded = false
    @State private var isGuideOpticalAssemblyIncluded = false
    @State private var isImagingTrainIncluded = false
    @State private var isGuideCameraIncluded = false
    @State private var isPowerHubIncluded = false
    @State private var isFlatScreenIncluded = false
    @State private var isDewHeaterIncluded = false
    @State private var isObservatoryControlIncluded = false
    @State private var defaultObservatoryID: String?
    @State private var defaultServer: ServerProfile?

    @State private var liveObservatories: [ObservatorySummary] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isConnected: Bool { telescope.state == .connected }
    private var mainOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .mainImaging } }
    private var guideOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .guideScope } }
    private func standaloneEquipment(for role: StandaloneEquipmentRole) -> [StandaloneEquipmentProfile] {
        standaloneEquipment.filter { $0.role == role }
    }

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
                        isIncluded: isMountIncluded,
                        onToggle: { included in
                            isMountIncluded = included
                            mount = included ? (mount ?? mounts.first) : nil
                        },
                        summary: mount.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Mount", selection: $mount) {
                                Text("None").tag(MountProfile?.none)
                                ForEach(mounts) { Text($0.name).tag(MountProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Optical Assembly",
                        isIncluded: isOpticalAssemblyIncluded,
                        onToggle: { included in
                            isOpticalAssemblyIncluded = included
                            opticalAssembly = included ? (opticalAssembly ?? mainOpticalAssemblies.first) : nil
                        },
                        summary: opticalAssembly.map { roleSummary(name: $0.name, deviceName: $0.hasFocuser ? $0.focuserDeviceName : nil, deviceLabel: "Focuser") },
                        picker: {
                            Picker("Optical Assembly", selection: $opticalAssembly) {
                                Text("None").tag(OpticalAssemblyProfile?.none)
                                ForEach(mainOpticalAssemblies) { Text($0.name).tag(OpticalAssemblyProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Guide Optical Assembly",
                        isIncluded: isGuideOpticalAssemblyIncluded,
                        onToggle: { included in
                            isGuideOpticalAssemblyIncluded = included
                            guideOpticalAssembly = included ? (guideOpticalAssembly ?? guideOpticalAssemblies.first) : nil
                        },
                        summary: guideOpticalAssembly.map { roleSummary(name: $0.name, deviceName: $0.hasFocuser ? $0.focuserDeviceName : nil, deviceLabel: "Focuser") },
                        picker: {
                            Picker("Guide Optical Assembly", selection: $guideOpticalAssembly) {
                                Text("None").tag(OpticalAssemblyProfile?.none)
                                ForEach(guideOpticalAssemblies) { Text($0.name).tag(OpticalAssemblyProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
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
                        isIncluded: isImagingTrainIncluded,
                        onToggle: { included in
                            isImagingTrainIncluded = included
                            imagingTrain = included ? (imagingTrain ?? imagingTrains.first) : nil
                        },
                        summary: imagingTrain.map { roleSummary(name: $0.name, deviceName: $0.camera?.deviceName, deviceLabel: "Camera") },
                        picker: {
                            Picker("Imaging Train", selection: $imagingTrain) {
                                Text("None").tag(ImagingTrainProfile?.none)
                                ForEach(imagingTrains) { Text($0.name).tag(ImagingTrainProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Guide Camera",
                        isIncluded: isGuideCameraIncluded,
                        onToggle: { included in
                            isGuideCameraIncluded = included
                            guideCamera = included ? (guideCamera ?? guideCameras.first) : nil
                        },
                        summary: guideCamera.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Guide Camera", selection: $guideCamera) {
                                Text("None").tag(GuideCameraProfile?.none)
                                ForEach(guideCameras) { Text($0.name).tag(GuideCameraProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    Divider()

                    roleSection(
                        title: "Power Hub",
                        isIncluded: isPowerHubIncluded,
                        onToggle: { included in
                            isPowerHubIncluded = included
                            powerHub = included ? (powerHub ?? standaloneEquipment(for: .powerHub).first) : nil
                        },
                        summary: powerHub.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Power Hub", selection: $powerHub) {
                                Text("None").tag(StandaloneEquipmentProfile?.none)
                                ForEach(standaloneEquipment(for: .powerHub)) { Text($0.name).tag(StandaloneEquipmentProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Flat Screen",
                        isIncluded: isFlatScreenIncluded,
                        onToggle: { included in
                            isFlatScreenIncluded = included
                            flatScreen = included ? (flatScreen ?? standaloneEquipment(for: .flatScreen).first) : nil
                        },
                        summary: flatScreen.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Flat Screen", selection: $flatScreen) {
                                Text("None").tag(StandaloneEquipmentProfile?.none)
                                ForEach(standaloneEquipment(for: .flatScreen)) { Text($0.name).tag(StandaloneEquipmentProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Dew Heater",
                        isIncluded: isDewHeaterIncluded,
                        onToggle: { included in
                            isDewHeaterIncluded = included
                            dewHeater = included ? (dewHeater ?? standaloneEquipment(for: .dewHeater).first) : nil
                        },
                        summary: dewHeater.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Dew Heater", selection: $dewHeater) {
                                Text("None").tag(StandaloneEquipmentProfile?.none)
                                ForEach(standaloneEquipment(for: .dewHeater)) { Text($0.name).tag(StandaloneEquipmentProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Observatory Control",
                        isIncluded: isObservatoryControlIncluded,
                        onToggle: { included in
                            isObservatoryControlIncluded = included
                            observatoryControl = included ? (observatoryControl ?? standaloneEquipment(for: .observatoryControl).first) : nil
                        },
                        summary: observatoryControl.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Observatory Control", selection: $observatoryControl) {
                                Text("None").tag(StandaloneEquipmentProfile?.none)
                                ForEach(standaloneEquipment(for: .observatoryControl)) { Text($0.name).tag(StandaloneEquipmentProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            load()
            await refreshObservatories()
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
            Button("Cancel") { onFinished() }
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

    /// NAVI-85: pure picking, no "New…"/"Edit…" — an empty library points the user at the
    /// Equipment tab (`selectSettingsTab`) instead of drilling into a sub-editor from here.
    @ViewBuilder
    private func roleSection(
        title: String,
        isIncluded: Bool,
        onToggle: @escaping (Bool) -> Void,
        summary: String?,
        @ViewBuilder picker: () -> some View
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
                } else {
                    HStack(spacing: 4) {
                        Text("No \(title.lowercased()) defined yet —")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("go to Equipment…") { selectSettingsTab(.equipment) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func load() {
        name = rig?.name ?? ""
        mount = rig?.mount
        isMountIncluded = mount != nil
        opticalAssembly = rig?.opticalAssembly
        isOpticalAssemblyIncluded = opticalAssembly != nil
        guideOpticalAssembly = rig?.guideOpticalAssembly
        isGuideOpticalAssemblyIncluded = guideOpticalAssembly != nil
        imagingTrain = rig?.imagingTrain
        isImagingTrainIncluded = imagingTrain != nil
        guideCamera = rig?.guideCamera
        isGuideCameraIncluded = guideCamera != nil
        powerHub = rig?.powerHub
        isPowerHubIncluded = powerHub != nil
        flatScreen = rig?.flatScreen
        isFlatScreenIncluded = flatScreen != nil
        dewHeater = rig?.dewHeater
        isDewHeaterIncluded = dewHeater != nil
        observatoryControl = rig?.observatoryControl
        isObservatoryControlIncluded = observatoryControl != nil
        defaultObservatoryID = rig?.defaultObservatoryID
        defaultServer = rig?.defaultServer
    }

    private func refreshObservatories() async {
        guard isConnected else { return }
        liveObservatories = (try? await telescope.listObservatories()) ?? []
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
                powerHub: powerHub,
                flatScreen: flatScreen,
                dewHeater: dewHeater,
                observatoryControl: observatoryControl
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
            onSaved(upsertLocalRig(with: saved))
        } catch {
            errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    @discardableResult
    private func upsertLocalRig(with savedRig: Rig) -> RigProfile {
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
        target.powerHub = powerHub
        target.flatScreen = flatScreen
        target.dewHeater = dewHeater
        target.observatoryControl = observatoryControl
        target.defaultObservatoryID = defaultObservatoryID
        target.defaultServer = defaultServer
        target.lastResyncedAt = .now
        try? modelContext.save()
        return target
    }
}
