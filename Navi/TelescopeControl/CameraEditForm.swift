//
//  CameraEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData

/// Add/edit form for one `CameraProfile` (§4.3). `deviceName` is picker-only while connected
/// (§4.2), via `DevicePickerField`; every other field is freely editable offline.
struct CameraEditForm: View {
    @Environment(\.modelContext) private var modelContext
    let camera: CameraProfile?
    var onSaved: (CameraProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var cooled = false
    @State private var pixelsX: Int?
    @State private var pixelsY: Int?
    @State private var pixelSizeMicron: Double?
    @State private var bitDepth: Int?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(camera == nil ? "Add Camera" : "Edit Camera")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField("Name") {
                        TextField("ASI2600MM Pro", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        LabeledField("Make") {
                            TextField("ZWO", text: $make)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Model") {
                            TextField("ASI2600MM Pro", text: $model)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    DevicePickerField(label: "INDI Device", deviceName: $deviceName)
                    Toggle("Cooled", isOn: $cooled)
                    HStack(spacing: 12) {
                        LabeledField("Pixels X") {
                            TextField("0", value: $pixelsX, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Pixels Y") {
                            TextField("0", value: $pixelsY, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    HStack(spacing: 12) {
                        LabeledField("Pixel Size (µm)") {
                            TextField("0", value: $pixelSizeMicron, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Bit Depth") {
                            TextField("0", value: $bitDepth, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
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
        .onAppear {
            name = camera?.name ?? ""
            make = camera?.make ?? ""
            model = camera?.model ?? ""
            deviceName = camera?.deviceName
            cooled = camera?.cooled ?? false
            pixelsX = camera?.pixelsX
            pixelsY = camera?.pixelsY
            pixelSizeMicron = camera?.pixelSizeMicron
            bitDepth = camera?.bitDepth
            notes = camera?.notes ?? ""
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationError = "Name is required."
            return
        }
        let trimmedMake = make.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let saved: CameraProfile
        if let camera {
            camera.name = trimmedName
            camera.make = trimmedMake.isEmpty ? nil : trimmedMake
            camera.model = trimmedModel.isEmpty ? nil : trimmedModel
            camera.deviceName = deviceName
            camera.cooled = cooled
            camera.pixelsX = pixelsX
            camera.pixelsY = pixelsY
            camera.pixelSizeMicron = pixelSizeMicron
            camera.bitDepth = bitDepth
            camera.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            camera.modifiedAt = .now
            saved = camera
        } else {
            let created = CameraProfile(
                name: trimmedName,
                make: trimmedMake.isEmpty ? nil : trimmedMake,
                model: trimmedModel.isEmpty ? nil : trimmedModel,
                deviceName: deviceName,
                cooled: cooled,
                pixelsX: pixelsX,
                pixelsY: pixelsY,
                pixelSizeMicron: pixelSizeMicron,
                bitDepth: bitDepth,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            modelContext.insert(created)
            saved = created
        }
        try? modelContext.save()
        onSaved(saved)
    }
}
