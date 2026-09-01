//
//  RotatorEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData

/// Add/edit form for one `RotatorProfile` (§4.3). `deviceName` is picker-only while connected
/// (§4.2), via `DevicePickerField`; every other field is freely editable offline.
struct RotatorEditForm: View {
    @Environment(\.modelContext) private var modelContext
    let rotator: RotatorProfile?
    var onSaved: (RotatorProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(rotator == nil ? "Add Rotator" : "Edit Rotator")
                .font(.headline)

            LabeledField("Name") {
                TextField("Falcon Rotator", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Pegasus", text: $make)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("Falcon Rotator", text: $model)
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $deviceName)
            LabeledField("Notes") {
                TextField("Optional notes", text: $notes)
                    .textFieldStyle(.roundedBorder)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

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
            name = rotator?.name ?? ""
            make = rotator?.make ?? ""
            model = rotator?.model ?? ""
            deviceName = rotator?.deviceName
            notes = rotator?.notes ?? ""
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

        let saved: RotatorProfile
        if let rotator {
            rotator.name = trimmedName
            rotator.make = trimmedMake.isEmpty ? nil : trimmedMake
            rotator.model = trimmedModel.isEmpty ? nil : trimmedModel
            rotator.deviceName = deviceName
            rotator.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            rotator.modifiedAt = .now
            saved = rotator
        } else {
            let created = RotatorProfile(
                name: trimmedName,
                make: trimmedMake.isEmpty ? nil : trimmedMake,
                model: trimmedModel.isEmpty ? nil : trimmedModel,
                deviceName: deviceName,
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
