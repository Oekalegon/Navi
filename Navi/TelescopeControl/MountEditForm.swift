//
//  MountEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// Add/edit form for one `MountProfile` (§4.3's equipment library). `mount == nil` means
/// "creating a new one" — saving inserts it; otherwise saving mutates the passed-in record in
/// place. Non-device fields are always editable; the `deviceName` binding is picker-only while
/// connected (§4.2), matching `DevicePickerField`'s contract.
struct MountEditForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let mount: MountProfile?
    /// Called with the saved (inserted-or-mutated) mount, so the Rig editor can adopt it as this
    /// rig's `mount` relationship right away.
    var onSaved: (MountProfile) -> Void = { _ in }

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mount == nil ? "Add Mount" : "Edit Mount")
                .font(.headline)

            LabeledField("Name") {
                TextField("EQ6-R Pro", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Sky-Watcher", text: $make)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("EQ6-R Pro", text: $model)
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
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 380, height: 320)
        .onAppear {
            name = mount?.name ?? ""
            make = mount?.make ?? ""
            model = mount?.model ?? ""
            deviceName = mount?.deviceName
            notes = mount?.notes ?? ""
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

        let saved: MountProfile
        if let mount {
            mount.name = trimmedName
            mount.make = trimmedMake.isEmpty ? nil : trimmedMake
            mount.model = trimmedModel.isEmpty ? nil : trimmedModel
            mount.deviceName = deviceName
            mount.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            mount.modifiedAt = .now
            saved = mount
        } else {
            let created = MountProfile(
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
        dismiss()
    }
}
