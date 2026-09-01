//
//  StandaloneEquipmentEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// Add/edit form for one `StandaloneEquipmentProfile` (§4.3's equipment library) — shared by all
/// four standalone roles (Power Hub, Flat Screen, Dew Heater, Observatory Control), `role` fixed by
/// the caller (same pattern as `OpticalAssemblyEditForm`'s `purpose`). `equipment == nil` means
/// "creating a new one" — saving inserts it; otherwise saving mutates the passed-in record in place.
struct StandaloneEquipmentEditForm: View {
    @Environment(\.modelContext) private var modelContext
    let equipment: StandaloneEquipmentProfile?
    let role: StandaloneEquipmentRole
    var sharedDrivers: [DriverInfo]?
    /// Called with the saved (inserted-or-mutated) entity, so the Equipment pane can adopt it as
    /// the current selection right away.
    var onSaved: (StandaloneEquipmentProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var preferredDriverLabel: String?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(equipment == nil ? "Add \(role.title)" : "Edit \(role.title)")
                .font(.headline)

            LabeledField("Name") {
                TextField("\(role.title) 1", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Optional", text: $make)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("Optional", text: $model)
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $deviceName)
            DriverPickerField(label: "Preferred Driver", driverLabel: $preferredDriverLabel, sharedDrivers: sharedDrivers)
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
            name = equipment?.name ?? ""
            make = equipment?.make ?? ""
            model = equipment?.model ?? ""
            deviceName = equipment?.deviceName
            preferredDriverLabel = equipment?.preferredDriverLabel
            notes = equipment?.notes ?? ""
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

        let saved: StandaloneEquipmentProfile
        if let equipment {
            equipment.name = trimmedName
            equipment.make = trimmedMake.isEmpty ? nil : trimmedMake
            equipment.model = trimmedModel.isEmpty ? nil : trimmedModel
            equipment.deviceName = deviceName
            equipment.preferredDriverLabel = preferredDriverLabel
            equipment.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            equipment.modifiedAt = .now
            saved = equipment
        } else {
            let created = StandaloneEquipmentProfile(
                name: trimmedName,
                role: role,
                make: trimmedMake.isEmpty ? nil : trimmedMake,
                model: trimmedModel.isEmpty ? nil : trimmedModel,
                deviceName: deviceName,
                preferredDriverLabel: preferredDriverLabel,
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
