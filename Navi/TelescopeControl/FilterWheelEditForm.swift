//
//  FilterWheelEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData
import INDIMCPKit

/// Add/edit form for one `FilterWheelProfile` (§4.3). `deviceName` is picker-only while connected
/// (§4.2), via `DevicePickerField`.
struct FilterWheelEditForm: View {
    @Environment(\.modelContext) private var modelContext
    let filterWheel: FilterWheelProfile?
    var sharedDrivers: [DriverInfo]?
    var onSaved: (FilterWheelProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var preferredDriverLabel: String?
    @State private var slots: [FilterSlotEntry] = []
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(filterWheel == nil ? "Add Filter Wheel" : "Edit Filter Wheel")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField("Name") {
                        TextField("EFW", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        LabeledField("Make") {
                            TextField("ZWO", text: $make)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Model") {
                            TextField("EFW", text: $model)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    DevicePickerField(label: "INDI Device", deviceName: $deviceName)
                    DriverPickerField(label: "Preferred Driver", driverLabel: $preferredDriverLabel, sharedDrivers: sharedDrivers)
                    slotsEditor
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
            name = filterWheel?.name ?? ""
            make = filterWheel?.make ?? ""
            model = filterWheel?.model ?? ""
            deviceName = filterWheel?.deviceName
            preferredDriverLabel = filterWheel?.preferredDriverLabel
            slots = filterWheel?.slots ?? []
            notes = filterWheel?.notes ?? ""
        }
    }

    private var slotsEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter Slots")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(slots.indices, id: \.self) { index in
                HStack {
                    TextField("Slot", value: $slots[index].slot, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    TextField("Filter name", text: $slots[index].name)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { slots.remove(at: index) }) {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: {
                let nextSlot = (slots.map(\.slot).max() ?? 0) + 1
                slots.append(FilterSlotEntry(slot: nextSlot, name: ""))
            }) {
                Label("Add Slot", systemImage: "plus")
            }
            .buttonStyle(.plain)
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
        let resolvedSlots = slots.isEmpty ? nil : slots

        let saved: FilterWheelProfile
        if let filterWheel {
            filterWheel.name = trimmedName
            filterWheel.make = trimmedMake.isEmpty ? nil : trimmedMake
            filterWheel.model = trimmedModel.isEmpty ? nil : trimmedModel
            filterWheel.deviceName = deviceName
            filterWheel.preferredDriverLabel = preferredDriverLabel
            filterWheel.slots = resolvedSlots
            filterWheel.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            filterWheel.modifiedAt = .now
            saved = filterWheel
        } else {
            let created = FilterWheelProfile(
                name: trimmedName,
                make: trimmedMake.isEmpty ? nil : trimmedMake,
                model: trimmedModel.isEmpty ? nil : trimmedModel,
                deviceName: deviceName,
                preferredDriverLabel: preferredDriverLabel,
                slots: resolvedSlots,
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
