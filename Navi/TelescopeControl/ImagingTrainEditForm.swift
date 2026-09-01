//
//  ImagingTrainEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// Add/edit form for one `ImagingTrainProfile` (§4.3) — the camera, filter wheel, and rotator
/// behind an optical assembly. The camera is always present; filter wheel and rotator are each
/// optional groups of fields (`hasFilterWheel`/`hasRotator`), matching a Rig `Component`'s
/// "selected but no device" vs. "role not present at all" distinction. Every `...DeviceName`
/// field is picker-only while connected (§4.2), via `DevicePickerField`.
struct ImagingTrainEditForm: View {
    @Environment(\.modelContext) private var modelContext
    let imagingTrain: ImagingTrainProfile?
    var sharedDrivers: [DriverInfo]?
    var onSaved: (ImagingTrainProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @State private var name = ""

    @State private var cameraMake = ""
    @State private var cameraModel = ""
    @State private var cameraDeviceName: String?
    @State private var cameraPreferredDriverLabel: String?
    @State private var cameraCooled = false
    @State private var cameraPixelsX: Int?
    @State private var cameraPixelsY: Int?
    @State private var cameraPixelSizeMicron: Double?
    @State private var cameraBitDepth: Int?

    @State private var includesFilterWheel = false
    @State private var filterWheelMake = ""
    @State private var filterWheelModel = ""
    @State private var filterWheelDeviceName: String?
    @State private var filterWheelPreferredDriverLabel: String?
    @State private var filterWheelSlots: [FilterSlotEntry] = []

    @State private var includesRotator = false
    @State private var rotatorMake = ""
    @State private var rotatorModel = ""
    @State private var rotatorDeviceName: String?
    @State private var rotatorPreferredDriverLabel: String?

    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(imagingTrain == nil ? "Add Imaging Train" : "Edit Imaging Train")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField("Name") {
                        TextField("ASI2600MM Train", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Camera").font(.subheadline).fontWeight(.semibold)
                    HStack(spacing: 12) {
                        LabeledField("Make") {
                            TextField("ZWO", text: $cameraMake)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Model") {
                            TextField("ASI2600MM Pro", text: $cameraModel)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    DevicePickerField(label: "Camera INDI Device", deviceName: $cameraDeviceName)
                    DriverPickerField(label: "Camera Preferred Driver", driverLabel: $cameraPreferredDriverLabel, sharedDrivers: sharedDrivers)
                    Toggle("Cooled", isOn: $cameraCooled)
                    HStack(spacing: 12) {
                        LabeledField("Pixels X") {
                            TextField("0", value: $cameraPixelsX, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Pixels Y") {
                            TextField("0", value: $cameraPixelsY, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    HStack(spacing: 12) {
                        LabeledField("Pixel Size (µm)") {
                            TextField("0", value: $cameraPixelSizeMicron, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Bit Depth") {
                            TextField("0", value: $cameraBitDepth, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()
                    Toggle("Has Filter Wheel", isOn: $includesFilterWheel)
                    if includesFilterWheel {
                        HStack(spacing: 12) {
                            LabeledField("Make") {
                                TextField("ZWO", text: $filterWheelMake)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledField("Model") {
                                TextField("EFW", text: $filterWheelModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        DevicePickerField(label: "Filter Wheel INDI Device", deviceName: $filterWheelDeviceName)
                        DriverPickerField(label: "Filter Wheel Preferred Driver", driverLabel: $filterWheelPreferredDriverLabel, sharedDrivers: sharedDrivers)
                        filterSlotsEditor
                    }

                    Divider()
                    Toggle("Has Rotator", isOn: $includesRotator)
                    if includesRotator {
                        HStack(spacing: 12) {
                            LabeledField("Make") {
                                TextField("Pegasus", text: $rotatorMake)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledField("Model") {
                                TextField("Falcon Rotator", text: $rotatorModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        DevicePickerField(label: "Rotator INDI Device", deviceName: $rotatorDeviceName)
                        DriverPickerField(label: "Rotator Preferred Driver", driverLabel: $rotatorPreferredDriverLabel, sharedDrivers: sharedDrivers)
                    }

                    LabeledField("Notes") {
                        TextField("Optional notes", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinished() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: load)
    }

    private var filterSlotsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter Slots")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(filterWheelSlots.indices, id: \.self) { index in
                HStack {
                    TextField("Slot", value: $filterWheelSlots[index].slot, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    TextField("Filter name", text: $filterWheelSlots[index].name)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { filterWheelSlots.remove(at: index) }) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: {
                let nextSlot = (filterWheelSlots.map(\.slot).max() ?? 0) + 1
                filterWheelSlots.append(FilterSlotEntry(slot: nextSlot, name: ""))
            }) {
                Label("Add Slot", systemImage: "plus")
            }
            .buttonStyle(.plain)
        }
    }

    private func load() {
        name = imagingTrain?.name ?? ""
        cameraMake = imagingTrain?.cameraMake ?? ""
        cameraModel = imagingTrain?.cameraModel ?? ""
        cameraDeviceName = imagingTrain?.cameraDeviceName
        cameraPreferredDriverLabel = imagingTrain?.cameraPreferredDriverLabel
        cameraCooled = imagingTrain?.cameraCooled ?? false
        cameraPixelsX = imagingTrain?.cameraPixelsX
        cameraPixelsY = imagingTrain?.cameraPixelsY
        cameraPixelSizeMicron = imagingTrain?.cameraPixelSizeMicron
        cameraBitDepth = imagingTrain?.cameraBitDepth

        includesFilterWheel = imagingTrain?.hasFilterWheel ?? false
        filterWheelMake = imagingTrain?.filterWheelMake ?? ""
        filterWheelModel = imagingTrain?.filterWheelModel ?? ""
        filterWheelDeviceName = imagingTrain?.filterWheelDeviceName
        filterWheelPreferredDriverLabel = imagingTrain?.filterWheelPreferredDriverLabel
        filterWheelSlots = imagingTrain?.filterWheelSlots ?? []

        includesRotator = imagingTrain?.hasRotator ?? false
        rotatorMake = imagingTrain?.rotatorMake ?? ""
        rotatorModel = imagingTrain?.rotatorModel ?? ""
        rotatorDeviceName = imagingTrain?.rotatorDeviceName
        rotatorPreferredDriverLabel = imagingTrain?.rotatorPreferredDriverLabel

        notes = imagingTrain?.notes ?? ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }
        let trimmedCameraMake = cameraMake.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCameraModel = cameraModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedFilterWheelMake = filterWheelMake.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFilterWheelModel = filterWheelModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFilterWheelMake = includesFilterWheel && !trimmedFilterWheelMake.isEmpty ? trimmedFilterWheelMake : nil
        let resolvedFilterWheelModel = includesFilterWheel && !trimmedFilterWheelModel.isEmpty ? trimmedFilterWheelModel : nil
        let resolvedFilterWheelDevice = includesFilterWheel ? filterWheelDeviceName : nil
        let resolvedFilterWheelDriverLabel = includesFilterWheel ? filterWheelPreferredDriverLabel : nil
        let resolvedFilterWheelSlots = includesFilterWheel && !filterWheelSlots.isEmpty ? filterWheelSlots : nil

        let trimmedRotatorMake = rotatorMake.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRotatorModel = rotatorModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRotatorMake = includesRotator && !trimmedRotatorMake.isEmpty ? trimmedRotatorMake : nil
        let resolvedRotatorModel = includesRotator && !trimmedRotatorModel.isEmpty ? trimmedRotatorModel : nil
        let resolvedRotatorDevice = includesRotator ? rotatorDeviceName : nil
        let resolvedRotatorDriverLabel = includesRotator ? rotatorPreferredDriverLabel : nil

        let saved: ImagingTrainProfile
        if let imagingTrain {
            imagingTrain.name = trimmedName
            imagingTrain.cameraMake = trimmedCameraMake.isEmpty ? nil : trimmedCameraMake
            imagingTrain.cameraModel = trimmedCameraModel.isEmpty ? nil : trimmedCameraModel
            imagingTrain.cameraDeviceName = cameraDeviceName
            imagingTrain.cameraPreferredDriverLabel = cameraPreferredDriverLabel
            imagingTrain.cameraCooled = cameraCooled
            imagingTrain.cameraPixelsX = cameraPixelsX
            imagingTrain.cameraPixelsY = cameraPixelsY
            imagingTrain.cameraPixelSizeMicron = cameraPixelSizeMicron
            imagingTrain.cameraBitDepth = cameraBitDepth
            imagingTrain.filterWheelMake = resolvedFilterWheelMake
            imagingTrain.filterWheelModel = resolvedFilterWheelModel
            imagingTrain.filterWheelDeviceName = resolvedFilterWheelDevice
            imagingTrain.filterWheelPreferredDriverLabel = resolvedFilterWheelDriverLabel
            imagingTrain.filterWheelSlots = resolvedFilterWheelSlots
            imagingTrain.rotatorMake = resolvedRotatorMake
            imagingTrain.rotatorModel = resolvedRotatorModel
            imagingTrain.rotatorDeviceName = resolvedRotatorDevice
            imagingTrain.rotatorPreferredDriverLabel = resolvedRotatorDriverLabel
            imagingTrain.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            imagingTrain.modifiedAt = .now
            saved = imagingTrain
        } else {
            let created = ImagingTrainProfile(
                name: trimmedName,
                cameraMake: trimmedCameraMake.isEmpty ? nil : trimmedCameraMake,
                cameraModel: trimmedCameraModel.isEmpty ? nil : trimmedCameraModel,
                cameraDeviceName: cameraDeviceName,
                cameraPreferredDriverLabel: cameraPreferredDriverLabel,
                cameraCooled: cameraCooled,
                cameraPixelsX: cameraPixelsX,
                cameraPixelsY: cameraPixelsY,
                cameraPixelSizeMicron: cameraPixelSizeMicron,
                cameraBitDepth: cameraBitDepth,
                filterWheelMake: resolvedFilterWheelMake,
                filterWheelModel: resolvedFilterWheelModel,
                filterWheelDeviceName: resolvedFilterWheelDevice,
                filterWheelPreferredDriverLabel: resolvedFilterWheelDriverLabel,
                filterWheelSlots: resolvedFilterWheelSlots,
                rotatorMake: resolvedRotatorMake,
                rotatorModel: resolvedRotatorModel,
                rotatorDeviceName: resolvedRotatorDevice,
                rotatorPreferredDriverLabel: resolvedRotatorDriverLabel,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            modelContext.insert(created)
            saved = created
        }
        try? modelContext.save()
        onSaved(saved)
        onFinished()
    }
}
