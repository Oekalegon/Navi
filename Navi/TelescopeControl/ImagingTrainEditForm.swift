//
//  ImagingTrainEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// Editor for one `ImagingTrainProfile` — pure composition, mirroring `RigEditForm`'s shape: for
/// each role (Camera, Filter Wheel, Rotator), just *pick* which already-defined
/// `EquipmentSettingsPane` library entity this train uses. No inline creation here — an empty role's
/// library points at the Equipment tab instead. See `MountEditForm` for the no-Save-button
/// convention; an `ImagingTrainProfile` is purely local, so edits need no connection.
struct ImagingTrainEditForm: View {
    @Environment(\.selectSettingsTab) private var selectSettingsTab
    @Bindable var imagingTrain: ImagingTrainProfile

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    @Query(sort: \CameraProfile.name) private var cameras: [CameraProfile]
    @Query(sort: \FilterWheelProfile.name) private var filterWheels: [FilterWheelProfile]
    @Query(sort: \RotatorProfile.name) private var rotators: [RotatorProfile]

    // Tracked separately from `camera != nil` so an empty library doesn't snap the toggle back off
    // before the user can reach a picker (the NAVI-62 precedent).
    @State private var isCameraIncluded = false
    @State private var isFilterWheelIncluded = false
    @State private var isRotatorIncluded = false

    var body: some View {
        SettingsDetailForm(title: imagingTrain.displayName) {
            LabeledField("Imaging Train Name") {
                TextField("ASI2600MM Train", text: $imagingTrain.name)
                        .focused($isNameFocused)
                    .textFieldStyle(.roundedBorder)
            }

            roleSection(
                title: "Camera",
                isIncluded: isCameraIncluded,
                onToggle: { included in
                    isCameraIncluded = included
                    imagingTrain.camera = included ? (imagingTrain.camera ?? cameras.first) : nil
                    touch()
                },
                summary: imagingTrain.camera.map { roleSummary(name: $0.displayName, deviceName: $0.deviceName) },
                picker: {
                    Picker("Camera", selection: $imagingTrain.camera) {
                        Text("None").tag(CameraProfile?.none)
                        ForEach(cameras) { Text($0.displayName).tag(CameraProfile?.some($0)) }
                    }
                    .labelsHidden()
                }
            )

            roleSection(
                title: "Filter Wheel",
                isIncluded: isFilterWheelIncluded,
                onToggle: { included in
                    isFilterWheelIncluded = included
                    imagingTrain.filterWheel = included ? (imagingTrain.filterWheel ?? filterWheels.first) : nil
                    touch()
                },
                summary: imagingTrain.filterWheel.map { roleSummary(name: $0.displayName, deviceName: $0.deviceName) },
                picker: {
                    Picker("Filter Wheel", selection: $imagingTrain.filterWheel) {
                        Text("None").tag(FilterWheelProfile?.none)
                        ForEach(filterWheels) { Text($0.displayName).tag(FilterWheelProfile?.some($0)) }
                    }
                    .labelsHidden()
                }
            )

            roleSection(
                title: "Rotator",
                isIncluded: isRotatorIncluded,
                onToggle: { included in
                    isRotatorIncluded = included
                    imagingTrain.rotator = included ? (imagingTrain.rotator ?? rotators.first) : nil
                    touch()
                },
                summary: imagingTrain.rotator.map { roleSummary(name: $0.displayName, deviceName: $0.deviceName) },
                picker: {
                    Picker("Rotator", selection: $imagingTrain.rotator) {
                        Text("None").tag(RotatorProfile?.none)
                        ForEach(rotators) { Text($0.displayName).tag(RotatorProfile?.some($0)) }
                    }
                    .labelsHidden()
                }
            )
        }
        .onAppear {
            if imagingTrain.name.isEmpty { isNameFocused = true }
            load()
        }
        .onChange(of: changeKey) { touch() }
    }

    private func roleSummary(name: String, deviceName: String?) -> String {
        if let deviceName {
            return "\(name) · Device: \(deviceName)"
        }
        return "\(name) · Device: blank"
    }

    /// See `RigEditForm.roleSection` — identical pattern, duplicated rather than shared since it's
    /// the only piece these two otherwise-unrelated composition forms have in common.
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
        isCameraIncluded = imagingTrain.camera != nil
        isFilterWheelIncluded = imagingTrain.filterWheel != nil
        isRotatorIncluded = imagingTrain.rotator != nil
    }

    private func touch() {
        imagingTrain.modifiedAt = .now
    }

    /// Every editable field folded into one comparable value, so `modifiedAt` is stamped from a
    /// single `.onChange` rather than one per field — see `CameraLikeProfile.editableChangeKey`
    /// for why the list is kept in one place.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(imagingTrain.name)
        // Composed records identified by id: swapping which camera a train uses is an edit.
        parts.append(imagingTrain.camera.map { "\($0.persistentModelID)" } ?? "")
        parts.append(imagingTrain.filterWheel.map { "\($0.persistentModelID)" } ?? "")
        parts.append(imagingTrain.rotator.map { "\($0.persistentModelID)" } ?? "")
        return parts.joined(separator: "\u{1F}")
    }

}
