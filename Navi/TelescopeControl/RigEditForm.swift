//
//  RigEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import AppKit
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
    /// Set by any edit, cleared by a successful push. Gates the flush so merely *viewing* a rig
    /// never re-pushes it to the server.
    @State private var isDirty = false

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
                    if !isConnected {
                        Label(
                            "Not connected — changes are saved in Navi and pushed to the server next time you edit this rig while connected.",
                            systemImage: "icloud.slash"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: name) { isDirty = true }
        .onChange(of: mount) { isDirty = true }
        .onChange(of: opticalAssembly) { isDirty = true }
        .onChange(of: guideOpticalAssembly) { isDirty = true }
        .onChange(of: imagingTrain) { isDirty = true }
        .onChange(of: guideCamera) { isDirty = true }
        .onChange(of: powerHub) { isDirty = true }
        .onChange(of: flatScreen) { isDirty = true }
        .onChange(of: dewHeater) { isDirty = true }
        .onChange(of: observatoryControl) { isDirty = true }
        .onChange(of: defaultObservatoryID) { isDirty = true }
        .onChange(of: defaultServer) { isDirty = true }
        // Pushed once, when this form goes away — selecting a different rig, switching tab, or
        // closing Settings all tear it down. See `ObservatoryEditForm.flush()` for why this is a
        // detached Task and what happens if the push never lands.
        .onDisappear { flush() }
        // Belt and braces. .onDisappear is dependable for a selection change or a tab switch, but
        // window close is exactly where SwiftUI is least reliable about tearing a view down — and
        // that's the case where a missed flush loses the push outright. flush() is dirty-gated and
        // idempotent, so firing from both is harmless; this notification also covers other windows
        // closing, which is simply an earlier, equally safe moment to sync.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            flush()
        }
        .task {
            load()
            await refreshObservatories()
        }
    }

    /// The shared header, not hand-rolled chrome — this form keeps its own body/footer layout (its
    /// footer carries a leading "Connect to save" hint that `SettingsDetailForm`'s doesn't model),
    /// but the title bar itself goes through `SettingsPaneHeader` like every other pane's so the
    /// heights can't drift apart. `trailingContent` carries the in-flight spinner.
    private var header: some View {
        SettingsPaneHeader(title: rig == nil ? "Add Rig" : "Edit Rig") {
            if isSaving {
                ProgressView().controlSize(.small)
            }
        }
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

    /// Local persistence and the server push are deliberately separate. Navi is the richer record
    /// — `RigProfile` names *which library entity* fills each role, while the server only ever sees
    /// the flattened `Component` list `makeRigComponents` produces, and the id is generated here by
    /// `IDSlug` and merely echoed back by `saveRig`. So the composition is always written locally,
    /// connected or not, and the push is a separate sync step that simply waits for a connection.
    ///
    /// (Making Navi the outright source of truth — deferred pushes with drift detection against
    /// another client's edits — is its own piece of work; this just stops offline edits being lost.)
    private func flush() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        // Components are computed *before* the decision but used only by the push. `buildComponents`
        // returning nil is not a reason to skip the local write — see `recordFlushOutcome`.
        let components = buildComponents()
        switch recordFlushOutcome(
            isDirty: isDirty,
            trimmedName: trimmedName,
            isConnected: isConnected,
            canProject: components != nil
        ) {
        case .skip:
            return
        case .persistOnly:
            let saved = persistLocally()
            onSaved(saved)
            isDirty = false
        case .persistAndPush:
            let saved = persistLocally()
            onSaved(saved)
            isDirty = false
            guard let components else { return }
            Task { await push(components: components, profile: saved) }
        }
    }

    /// Returns `nil` (having set `errorMessage`) if the composition can't be flattened — e.g. the
    /// optical-assembly/guide-optical-assembly focuser collision. Checked before writing anything.
    private func buildComponents() -> [Component]? {
        do {
            return try makeRigComponents(
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
            // Surfaced app-wide rather than on this view's own @State: `flush()` runs during
            // teardown, so anything written to `errorMessage` there is never rendered. While the
            // form is still on screen the same message is shown inline by `validationBanner`.
            let described = (error as? RigProfileTranslationError)?.description ?? "\(error)"
            errorMessage = described
            telescope.errorMessage = "\(name): \(described)"
            return nil
        }
    }

    @discardableResult
    private func persistLocally() -> RigProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = rig ?? {
            let created = RigProfile(serverRigID: IDSlug.make(from: trimmedName), name: trimmedName)
            modelContext.insert(created)
            return created
        }()
        target.name = trimmedName
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
        try? modelContext.save()
        return target
    }

    private func push(components: [Component], profile: RigProfile) async {
        errorMessage = nil
        let payload = Rig(id: profile.serverRigID, name: profile.name, components: components)
        let digest = PayloadDigest.of(payload)

        // Nothing to send: the server already has exactly this.
        if let digest, digest == profile.lastPushedDigest { return }

        // Drift check. Only meaningful once this rig has been pushed before — without a stored
        // digest there's nothing to compare against, and a first push is legitimately creating it.
        if let lastPushed = profile.lastPushedDigest {
            if let serverCopy = try? await telescope.getRig(id: profile.serverRigID),
               let serverDigest = PayloadDigest.of(serverCopy),
               serverDigest != lastPushed {
                telescope.errorMessage = """
                    \(profile.name) changed on the server since Navi last pushed it — \
                    your local edits were kept but not sent, so the server copy is untouched.
                    """
                return
            }
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await telescope.saveRig(payload, overwrite: true)
            // Only now is the server in step with the local record, which is what
            // `hasStaleLibraryReferences` compares against — so a rig edited offline correctly
            // shows as stale until the push actually lands.
            profile.lastResyncedAt = .now
            profile.lastPushedDigest = PayloadDigest.of(saved) ?? digest
            try? modelContext.save()
        } catch {
            // Same reasoning as `buildComponents`: this runs after teardown, so the toolbar's
            // TelescopeErrorIndicator is the only place the user can actually see it.
            let described = TelescopeSessionManager.describe(error)
            errorMessage = described
            telescope.errorMessage = "\(profile.name): \(described)"
        }
    }


}
