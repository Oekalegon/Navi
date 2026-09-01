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
    @Environment(\.modelContext) private var modelContext
    @State private var telescope = TelescopeSessionManager.shared
    let rig: RigProfile?
    /// NAVI-81: which single equipment-concern page to show in `mainContent`'s
    /// `switch visibleSection` — the caller (`RigSettingsPane`'s sidebar) owns this, not this form.
    /// Defaults to `.overview` — selecting the rig itself (rather than one of its subitems) shows a
    /// read-only summary of every role, not an editable page.
    var visibleSection: RigSection = .overview
    /// Called when the user taps a row's "open" button on the `.overview` page (NAVI-81) — the
    /// caller updates its own selection so the sidebar and `visibleSection` both move to that page.
    var onSelectSection: (RigSection) -> Void = { _ in }
    /// Called with the saved (inserted-or-mutated) rig after a successful Save. **Exclusive** with
    /// `onFinished` here — deliberately unlike `MountEditForm`/`OpticalAssemblyEditForm`/etc.,
    /// which call both together on success. Those small sub-editors always want to return to
    /// `RigEditForm.mainContent` regardless of outcome; `RigEditForm` itself, now that its caller
    /// has a real sidebar to stay on (NAVI-81), should keep the user on the same rig+section after
    /// Save rather than bouncing them back to the "select a rig" placeholder — so `onSaved` alone
    /// fires on Save, and `onFinished` alone fires on Cancel.
    var onSaved: (RigProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77) — called only on Cancel here (see
    /// `onSaved` above). Distinct from `activeSheet`, which governs this form's *own* nested
    /// sub-editor drill-in (see `body`) rather than this form's presentation by its caller.
    var onFinished: () -> Void = {}

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
    // Whether each role's toggle is on — deliberately independent of whether an entity is
    // actually selected. Deriving "included" purely from `mount != nil` (etc.) meant that on an
    // empty library (no MountProfile/OpticalAssemblyProfile/... created yet at all), turning a
    // role's toggle on immediately snapped back off — `mount ?? mounts.first` resolves to `nil`
    // when both are empty, so `isIncluded` was still false on the very next render — and since
    // the "New…"/"Edit…" buttons only render `if isIncluded`, there was no way to ever create a
    // role's first library entity from here at all. These track the toggle's own on/off state;
    // `save()`/`makeRigComponents` still only ever look at the underlying `mount`/etc. values.
    @State private var isMountIncluded = false
    @State private var isOpticalAssemblyIncluded = false
    @State private var isGuideOpticalAssemblyIncluded = false
    @State private var isImagingTrainIncluded = false
    @State private var isGuideCameraIncluded = false
    // Same independent-toggle-state reasoning as above, applied to the inline Filter Wheel/Rotator
    // pages (NAVI-81): binding the Toggle directly to `imagingTrain.hasFilterWheel` (computed from
    // whether make/model/deviceName are non-nil) meant clearing the last populated field — e.g. the
    // "Make" text field, while Model/Device are still empty — silently flipped the toggle off and
    // collapsed the whole section out from under the user's cursor mid-edit. Seeded from
    // `imagingTrain?.hasFilterWheel`/`hasRotator` in `load()` and re-seeded in the `imagingTrain`
    // `onChange` below whenever the selected library entity itself changes.
    @State private var includesImagingTrainFilterWheel = false
    @State private var includesImagingTrainRotator = false
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
        case server(ServerProfile?)

        var id: String {
            switch self {
            case .mount(let m): return "mount-\(m?.persistentModelID.hashValue ?? 0)"
            case .opticalAssembly(let o): return "oa-\(o?.persistentModelID.hashValue ?? 0)"
            case .guideOpticalAssembly(let o): return "goa-\(o?.persistentModelID.hashValue ?? 0)"
            case .imagingTrain(let t): return "train-\(t?.persistentModelID.hashValue ?? 0)"
            case .guideCamera(let g): return "guide-\(g?.persistentModelID.hashValue ?? 0)"
            case .server(let s): return "server-\(s?.persistentModelID.hashValue ?? 0)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    private var isConnected: Bool { telescope.state == .connected }
    private var mainOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .mainImaging } }
    private var guideOpticalAssemblies: [OpticalAssemblyProfile] { opticalAssemblies.filter { $0.purpose == .guideScope } }

    var body: some View {
        Group {
            if let activeSheet {
                subEditorView(for: activeSheet)
            } else {
                mainContent
            }
        }
        .task {
            load()
            await refreshObservatories()
            await refreshLiveDevices()
        }
        // Re-seed the Filter Wheel/Rotator toggle state whenever the *selected* ImagingTrainProfile
        // itself changes (picked a different one, or "New…"/"Edit…" swapped it via onSaved) — each
        // entity has its own hasFilterWheel/hasRotator, so the toggle must reflect the newly
        // selected entity's actual state, not linger from whichever was selected before.
        .onChange(of: imagingTrain) { _, newValue in
            includesImagingTrainFilterWheel = newValue?.hasFilterWheel ?? false
            includesImagingTrainRotator = newValue?.hasRotator ?? false
        }
    }

    @ViewBuilder
    private func subEditorView(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .mount(let m):
            MountEditForm(
                mount: m,
                onSaved: { mount = $0; isMountIncluded = true },
                onFinished: { activeSheet = nil }
            )
        case .opticalAssembly(let o):
            OpticalAssemblyEditForm(
                opticalAssembly: o,
                purpose: .mainImaging,
                onSaved: { opticalAssembly = $0; isOpticalAssemblyIncluded = true },
                onFinished: { activeSheet = nil }
            )
        case .guideOpticalAssembly(let o):
            OpticalAssemblyEditForm(
                opticalAssembly: o,
                purpose: .guideScope,
                onSaved: { guideOpticalAssembly = $0; isGuideOpticalAssemblyIncluded = true },
                onFinished: { activeSheet = nil }
            )
        case .imagingTrain(let t):
            ImagingTrainEditForm(
                imagingTrain: t,
                onSaved: { imagingTrain = $0; isImagingTrainIncluded = true },
                onFinished: { activeSheet = nil }
            )
        case .guideCamera(let g):
            GuideCameraEditForm(
                guideCamera: g,
                onSaved: { guideCamera = $0; isGuideCameraIncluded = true },
                onFinished: { activeSheet = nil }
            )
        case .server(let s):
            ServerEditForm(
                server: s,
                onSaved: { defaultServer = $0 },
                onFinished: { activeSheet = nil }
            )
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Always visible regardless of `visibleSection` — depends on state from both
                    // the Optical Assembly and Guide Scope pages (NAVI-81), so it must stay visible
                    // no matter which of those the user is currently looking at.
                    if opticalAssembly?.hasFocuser == true && guideOpticalAssembly?.hasFocuser == true {
                        Label(
                            "Both the optical assembly and guide optical assembly have a focuser — this rig can't be saved until one is removed (INDIMCP-138).",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }

                    Divider()

                    sectionContent

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
    }

    /// NAVI-81: exactly one equipment-concern page, chosen by the sidebar via `visibleSection`.
    /// Every case reuses the same `roleSection`/`standaloneRow` helper calls this form always had —
    /// this only changes *which* of them render at once, not their behavior.
    @ViewBuilder
    private var sectionContent: some View {
        switch visibleSection {
        case .overview:
            overviewContent

        case .mount:
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
                },
                onNew: { activeSheet = .mount(nil) },
                onEdit: mount.map { m in { activeSheet = .mount(m) } }
            )

        case .opticalAssembly:
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
                },
                onNew: { activeSheet = .opticalAssembly(nil) },
                onEdit: opticalAssembly.map { o in { activeSheet = .opticalAssembly(o) } }
            )

        case .imagingTrain(nil):
            roleSection(
                title: "Imaging Train",
                isIncluded: isImagingTrainIncluded,
                onToggle: { included in
                    isImagingTrainIncluded = included
                    imagingTrain = included ? (imagingTrain ?? imagingTrains.first) : nil
                },
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

        case .imagingTrain(.camera):
            imagingTrainCameraContent

        case .imagingTrain(.filterWheel):
            imagingTrainFilterWheelContent

        case .imagingTrain(.rotator):
            imagingTrainRotatorContent

        case .imagingTrain(.offAxisGuider):
            // Same underlying `guideCamera` relationship `guideScope` edits (see `RigSection`'s
            // doc comment) — reachable from either navigation spot.
            guideCameraRoleSection

        case .guideScope:
            // Bundles two relationships on one page (NAVI-81) — a guide scope and its camera are
            // physically one subsystem. Both `roleSection` calls are unchanged from before.
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
                },
                onNew: { activeSheet = .guideOpticalAssembly(nil) },
                onEdit: guideOpticalAssembly.map { o in { activeSheet = .guideOpticalAssembly(o) } }
            )
            guideCameraRoleSection

        case .powerHub:
            standaloneCaption
            standaloneRow(role: "powerHub", title: "Power Hub")

        case .flatScreen:
            standaloneCaption
            standaloneRow(role: "flatScreen", title: "Flat Screen")

        case .dewHeater:
            standaloneCaption
            standaloneRow(role: "dewHeater", title: "Dew Heater")

        case .observatoryControl:
            standaloneCaption
            standaloneRow(role: "observatoryControl", title: "Observatory Control (roof/dome)")
        }
    }

    /// Shown above every standalone-component page (NAVI-81) — explains why these roles have no
    /// Make/Model picker or reusable library the way Mount/Optical Assembly/etc. do.
    private var standaloneCaption: some View {
        Text("No reusable library entity — just a device binding for this rig (§4.3).")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Shared by `.guideScope` and `.imagingTrain(.offAxisGuider)` (NAVI-81) — both pages edit the
    /// exact same `guideCamera` relationship, just reachable from two navigation spots.
    private var guideCameraRoleSection: some View {
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
            },
            onNew: { activeSheet = .guideCamera(nil) },
            onEdit: guideCamera.map { g in { activeSheet = .guideCamera(g) } }
        )
    }

    // MARK: - Imaging Train inline field-group pages (NAVI-81)
    //
    // Unlike every other role above, these edit the *currently-selected* `ImagingTrainProfile`'s
    // fields directly and immediately — no separate Save step, since `ImagingTrainProfile` is a
    // SwiftData reference type already live-bound via `imagingTrain`. `imagingTrainStringBinding`/
    // `imagingTrainOptionalBinding` read/write straight through to it and persist on every change.

    private var noImagingTrainSelected: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Imaging Train selected yet.")
                .font(.caption)
                .foregroundStyle(.orange)
            Button("Select or create an Imaging Train…") { onSelectSection(.imagingTrain(nil)) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private func imagingTrainStringBinding(_ keyPath: ReferenceWritableKeyPath<ImagingTrainProfile, String?>) -> Binding<String> {
        Binding(
            get: { imagingTrain?[keyPath: keyPath] ?? "" },
            set: { newValue in
                imagingTrain?[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                imagingTrain?.modifiedAt = .now
                try? modelContext.save()
            }
        )
    }

    private func imagingTrainOptionalBinding<T>(_ keyPath: ReferenceWritableKeyPath<ImagingTrainProfile, T?>) -> Binding<T?> {
        Binding(
            get: { imagingTrain?[keyPath: keyPath] },
            set: { newValue in
                imagingTrain?[keyPath: keyPath] = newValue
                imagingTrain?.modifiedAt = .now
                try? modelContext.save()
            }
        )
    }

    private func imagingTrainBoolBinding(_ keyPath: ReferenceWritableKeyPath<ImagingTrainProfile, Bool?>, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { imagingTrain?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                imagingTrain?[keyPath: keyPath] = newValue
                imagingTrain?.modifiedAt = .now
                try? modelContext.save()
            }
        )
    }

    @ViewBuilder
    private var imagingTrainCameraContent: some View {
        if imagingTrain != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    LabeledField("Make") {
                        TextField("ZWO", text: imagingTrainStringBinding(\.cameraMake))
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Model") {
                        TextField("ASI2600MM Pro", text: imagingTrainStringBinding(\.cameraModel))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                DevicePickerField(
                    label: "Camera INDI Device",
                    deviceName: imagingTrainOptionalBinding(\.cameraDeviceName),
                    sharedDevices: liveDevices
                )
                Toggle("Cooled", isOn: imagingTrainBoolBinding(\.cameraCooled, default: false))
                HStack(spacing: 12) {
                    LabeledField("Pixels X") {
                        TextField("0", value: imagingTrainOptionalBinding(\.cameraPixelsX), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Pixels Y") {
                        TextField("0", value: imagingTrainOptionalBinding(\.cameraPixelsY), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                HStack(spacing: 12) {
                    LabeledField("Pixel Size (µm)") {
                        TextField("0", value: imagingTrainOptionalBinding(\.cameraPixelSizeMicron), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Bit Depth") {
                        TextField("0", value: imagingTrainOptionalBinding(\.cameraBitDepth), format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        } else {
            noImagingTrainSelected
        }
    }

    @ViewBuilder
    private var imagingTrainFilterWheelContent: some View {
        if let imagingTrain {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Has Filter Wheel", isOn: Binding(
                    get: { includesImagingTrainFilterWheel },
                    set: { included in
                        includesImagingTrainFilterWheel = included
                        if included {
                            if !imagingTrain.hasFilterWheel { imagingTrain.filterWheelMake = "" }
                        } else {
                            imagingTrain.filterWheelMake = nil
                            imagingTrain.filterWheelModel = nil
                            imagingTrain.filterWheelDeviceName = nil
                            imagingTrain.filterWheelSlots = nil
                        }
                        imagingTrain.modifiedAt = .now
                        try? modelContext.save()
                    }
                ))
                if includesImagingTrainFilterWheel {
                    HStack(spacing: 12) {
                        LabeledField("Make") {
                            TextField("ZWO", text: imagingTrainStringBinding(\.filterWheelMake))
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Model") {
                            TextField("EFW", text: imagingTrainStringBinding(\.filterWheelModel))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    DevicePickerField(
                        label: "Filter Wheel INDI Device",
                        deviceName: imagingTrainOptionalBinding(\.filterWheelDeviceName),
                        sharedDevices: liveDevices
                    )
                    imagingTrainFilterSlotsEditor(for: imagingTrain)
                }
            }
        } else {
            noImagingTrainSelected
        }
    }

    private func imagingTrainFilterSlotsEditor(for imagingTrain: ImagingTrainProfile) -> some View {
        let slots = imagingTrain.filterWheelSlots ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text("Filter Slots")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(slots.indices, id: \.self) { index in
                HStack {
                    TextField("Slot", value: Binding(
                        get: { slots[index].slot },
                        set: { newValue in
                            var updated = slots
                            updated[index].slot = newValue
                            imagingTrain.filterWheelSlots = updated
                            try? modelContext.save()
                        }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    TextField("Filter name", text: Binding(
                        get: { slots[index].name },
                        set: { newValue in
                            var updated = slots
                            updated[index].name = newValue
                            imagingTrain.filterWheelSlots = updated
                            try? modelContext.save()
                        }
                    ))
                        .textFieldStyle(.roundedBorder)
                    Button(action: {
                        var updated = slots
                        updated.remove(at: index)
                        imagingTrain.filterWheelSlots = updated
                        try? modelContext.save()
                    }) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: {
                let nextSlot = (slots.map(\.slot).max() ?? 0) + 1
                var updated = slots
                updated.append(FilterSlotEntry(slot: nextSlot, name: ""))
                imagingTrain.filterWheelSlots = updated
                try? modelContext.save()
            }) {
                Label("Add Slot", systemImage: "plus")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var imagingTrainRotatorContent: some View {
        if let imagingTrain {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Has Rotator", isOn: Binding(
                    get: { includesImagingTrainRotator },
                    set: { included in
                        includesImagingTrainRotator = included
                        if included {
                            if !imagingTrain.hasRotator { imagingTrain.rotatorMake = "" }
                        } else {
                            imagingTrain.rotatorMake = nil
                            imagingTrain.rotatorModel = nil
                            imagingTrain.rotatorDeviceName = nil
                        }
                        imagingTrain.modifiedAt = .now
                        try? modelContext.save()
                    }
                ))
                if includesImagingTrainRotator {
                    HStack(spacing: 12) {
                        LabeledField("Make") {
                            TextField("Pegasus", text: imagingTrainStringBinding(\.rotatorMake))
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Model") {
                            TextField("Falcon Rotator", text: imagingTrainStringBinding(\.rotatorModel))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    DevicePickerField(
                        label: "Rotator INDI Device",
                        deviceName: imagingTrainOptionalBinding(\.rotatorDeviceName),
                        sharedDevices: liveDevices
                    )
                }
            }
        } else {
            noImagingTrainSelected
        }
    }

    /// NAVI-81: a read-only summary of every role — shown when the rig itself is selected rather
    /// than a specific subitem. Each row's button calls `onSelectSection` to jump to that role's
    /// own editable page.
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Rig Name and the Default Observatory/Server pickers are rig-wide, not tied to any
            // one component — they used to sit in the always-visible header above every page
            // (NAVI-81's first pass), which looked like each component had its own default
            // server/observatory since the same two pickers reappeared on every page. Overview-only
            // now.
            LabeledField("Rig Name") {
                TextField("Backyard EQ6-R Rig", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
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
                HStack {
                    Button("New…") { activeSheet = .server(nil) }
                    if defaultServer != nil {
                        Button("Edit…") { activeSheet = .server(defaultServer) }
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Divider()

            overviewRow(section: .mount, summary: mount.map { roleSummary(name: $0.name, deviceName: $0.deviceName) } ?? "Not configured")
            overviewRow(section: .opticalAssembly, summary: opticalAssembly.map { roleSummary(name: $0.name, deviceName: $0.hasFocuser ? $0.focuserDeviceName : nil, deviceLabel: "Focuser") } ?? "Not configured")
            overviewRow(section: .imagingTrain(nil), summary: imagingTrain.map { roleSummary(name: $0.name, deviceName: $0.cameraDeviceName, deviceLabel: "Camera") } ?? "Not configured")
            overviewRow(section: .guideScope, summary: guideScopeSummary)
            Divider()
            overviewRow(section: .powerHub, summary: standaloneSummary(role: "powerHub"))
            overviewRow(section: .flatScreen, summary: standaloneSummary(role: "flatScreen"))
            overviewRow(section: .dewHeater, summary: standaloneSummary(role: "dewHeater"))
            overviewRow(section: .observatoryControl, summary: standaloneSummary(role: "observatoryControl"))
        }
    }

    private func overviewRow(section: RigSection, summary: String) -> some View {
        let isConfigured = summary != "Not configured"
        return HStack {
            Image(systemName: section.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(isConfigured ? Color.secondary : Color.orange)
            }
            Spacer()
            Button(action: { onSelectSection(section) }) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open \(section.title)")
        }
    }

    private var guideScopeSummary: String {
        switch (guideOpticalAssembly?.name, guideCamera?.name) {
        case (nil, nil): return "Not configured"
        case (let ota?, nil): return "\(ota) · No guide camera"
        case (nil, let camera?): return "No guide optical assembly · \(camera)"
        case (let ota?, let camera?): return "\(ota) · \(camera)"
        }
    }

    private func standaloneSummary(role: String) -> String {
        guard let entry = standaloneComponents.first(where: { $0.role == role }) else {
            return "Not configured"
        }
        return entry.deviceName.map { "Device: \($0)" } ?? "Device: blank"
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
                } else {
                    // Nothing selected yet — most commonly because the library for this role is
                    // still empty (nothing to pick from ?? .first would resolve to). Point
                    // explicitly at "New…" rather than leaving an unexplained blank picker.
                    Text("No \(title.lowercased()) yet — click New… to add one.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
        isMountIncluded = mount != nil
        opticalAssembly = rig?.opticalAssembly
        isOpticalAssemblyIncluded = opticalAssembly != nil
        guideOpticalAssembly = rig?.guideOpticalAssembly
        isGuideOpticalAssemblyIncluded = guideOpticalAssembly != nil
        imagingTrain = rig?.imagingTrain
        isImagingTrainIncluded = imagingTrain != nil
        includesImagingTrainFilterWheel = imagingTrain?.hasFilterWheel ?? false
        includesImagingTrainRotator = imagingTrain?.hasRotator ?? false
        guideCamera = rig?.guideCamera
        isGuideCameraIncluded = guideCamera != nil
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
        target.defaultObservatoryID = defaultObservatoryID
        target.defaultServer = defaultServer
        target.standaloneComponents = standaloneComponents
        target.lastResyncedAt = .now
        try? modelContext.save()
        return target
    }
}
