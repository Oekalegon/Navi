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

            RigRoleSection(
                title: "Camera", selection: $imagingTrain.camera, isIncluded: $isCameraIncluded,
                options: cameras, displayName: \.displayName, deviceSummary: \.deviceName
            )

            RigRoleSection(
                title: "Filter Wheel", selection: $imagingTrain.filterWheel, isIncluded: $isFilterWheelIncluded,
                options: filterWheels, displayName: \.displayName, deviceSummary: \.deviceName
            )

            RigRoleSection(
                title: "Rotator", selection: $imagingTrain.rotator, isIncluded: $isRotatorIncluded,
                options: rotators, displayName: \.displayName, deviceSummary: \.deviceName
            )
        }
        .onAppear {
            if imagingTrain.name.isEmpty { isNameFocused = true }
            load()
        }
        .onChange(of: changeKey) { touch() }
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
