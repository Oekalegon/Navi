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
    @Environment(\.modelContext) private var modelContext
    let mount: MountProfile?
    /// Called with the saved (inserted-or-mutated) mount, so the Rig editor can adopt it as this
    /// rig's `mount` relationship right away.
    var onSaved: (MountProfile) -> Void = { _ in }
    /// Called on **Cancel only** (NAVI-77) — this form is embedded inline as detail content, not
    /// presented as a sheet, so there's no `dismiss()` to call; the caller (e.g. a master-detail
    /// pane) uses this to navigate back to whatever it shows when nothing is being edited.
    ///
    /// Deliberately *not* called after a successful Save: `onSaved` already hands the caller the
    /// persisted entity so it can select it, and calling both meant `onFinished` immediately
    /// clobbered that selection — leaving the user on a placeholder instead of the record they
    /// just saved, and making `onSaved`'s selection assignment dead code at every call site.
    /// `RigEditForm` has always called `onSaved` alone; the rest now match it.
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        SettingsDetailForm(title: mount == nil ? "Add Mount" : "Edit Mount") {
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

        } actions: {
            Button("Cancel") { onFinished() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
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
    }
}
