//
//  ImagingTrainEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// Add/edit form for one `ImagingTrainProfile` — pure composition, mirroring `RigEditForm`'s own
/// shape: for each role (Camera, Filter Wheel, Rotator), just *pick* which already-defined
/// `EquipmentSettingsPane` library entity this train uses. No inline creation/editing here — an
/// empty role's library points at the Equipment tab instead (`selectSettingsTab` in the
/// environment). Unlike `RigProfile`, an `ImagingTrainProfile` is purely local (no server push), so
/// saving here is a plain, synchronous SwiftData save — no connection required.
struct ImagingTrainEditForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectSettingsTab) private var selectSettingsTab
    let imagingTrain: ImagingTrainProfile?
    /// Called with the saved (inserted-or-mutated) train after a successful Save, so the caller can
    /// adopt it as the current selection right away.
    var onSaved: (ImagingTrainProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @Query(sort: \CameraProfile.name) private var cameras: [CameraProfile]
    @Query(sort: \FilterWheelProfile.name) private var filterWheels: [FilterWheelProfile]
    @Query(sort: \RotatorProfile.name) private var rotators: [RotatorProfile]

    @State private var name = ""
    @State private var camera: CameraProfile?
    @State private var filterWheel: FilterWheelProfile?
    @State private var rotator: RotatorProfile?
    // See `RigEditForm`'s identical `isMountIncluded`-style state for why this is tracked
    // separately from `camera != nil` — an empty library must not silently snap the toggle back
    // off before the user can even reach a picker.
    @State private var isCameraIncluded = false
    @State private var isFilterWheelIncluded = false
    @State private var isRotatorIncluded = false
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LabeledField("Imaging Train Name") {
                        TextField("ASI2600MM Train", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    roleSection(
                        title: "Camera",
                        isIncluded: isCameraIncluded,
                        onToggle: { included in
                            isCameraIncluded = included
                            camera = included ? (camera ?? cameras.first) : nil
                        },
                        summary: camera.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Camera", selection: $camera) {
                                Text("None").tag(CameraProfile?.none)
                                ForEach(cameras) { Text($0.name).tag(CameraProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Filter Wheel",
                        isIncluded: isFilterWheelIncluded,
                        onToggle: { included in
                            isFilterWheelIncluded = included
                            filterWheel = included ? (filterWheel ?? filterWheels.first) : nil
                        },
                        summary: filterWheel.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Filter Wheel", selection: $filterWheel) {
                                Text("None").tag(FilterWheelProfile?.none)
                                ForEach(filterWheels) { Text($0.name).tag(FilterWheelProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    roleSection(
                        title: "Rotator",
                        isIncluded: isRotatorIncluded,
                        onToggle: { included in
                            isRotatorIncluded = included
                            rotator = included ? (rotator ?? rotators.first) : nil
                        },
                        summary: rotator.map { roleSummary(name: $0.name, deviceName: $0.deviceName) },
                        picker: {
                            Picker("Rotator", selection: $rotator) {
                                Text("None").tag(RotatorProfile?.none)
                                ForEach(rotators) { Text($0.name).tag(RotatorProfile?.some($0)) }
                            }
                            .labelsHidden()
                        }
                    )

                    if let validationError {
                        Text(validationError)
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
        .onAppear { load() }
    }

    private var header: some View {
        HStack {
            Text(imagingTrain == nil ? "Add Imaging Train" : "Edit Imaging Train")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { onFinished() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func roleSummary(name: String, deviceName: String?) -> String {
        if let deviceName {
            return "\(name) · Device: \(deviceName)"
        }
        return "\(name) · Device: blank"
    }

    /// See `RigEditForm.roleSection`'s doc comment — identical pattern, duplicated rather than
    /// shared since it's the only piece these two otherwise-unrelated composition forms have in
    /// common.
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
        name = imagingTrain?.name ?? ""
        camera = imagingTrain?.camera
        isCameraIncluded = camera != nil
        filterWheel = imagingTrain?.filterWheel
        isFilterWheelIncluded = filterWheel != nil
        rotator = imagingTrain?.rotator
        isRotatorIncluded = rotator != nil
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }

        let saved: ImagingTrainProfile
        if let imagingTrain {
            imagingTrain.name = trimmedName
            imagingTrain.camera = camera
            imagingTrain.filterWheel = filterWheel
            imagingTrain.rotator = rotator
            imagingTrain.modifiedAt = .now
            saved = imagingTrain
        } else {
            let created = ImagingTrainProfile(name: trimmedName, camera: camera, filterWheel: filterWheel, rotator: rotator)
            modelContext.insert(created)
            saved = created
        }
        try? modelContext.save()
        onSaved(saved)
    }
}
