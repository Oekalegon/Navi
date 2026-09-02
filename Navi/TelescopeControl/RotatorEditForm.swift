//
//  RotatorEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData

/// Editor for one `RotatorProfile` (§4.3). See `MountEditForm`'s doc comment for the
/// bind-directly-to-the-record, no-Save-button convention.
struct RotatorEditForm: View {
    @Bindable var rotator: RotatorProfile

    var body: some View {
        SettingsDetailForm(title: rotator.displayName) {
            LabeledField("Name") {
                TextField("Falcon Rotator", text: $rotator.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Pegasus", text: Binding(nilAsEmpty: $rotator.make))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("Falcon Rotator", text: Binding(nilAsEmpty: $rotator.model))
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $rotator.deviceName)
            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $rotator.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onChange(of: rotator.name) { rotator.modifiedAt = .now }
        .onChange(of: rotator.make) { rotator.modifiedAt = .now }
        .onChange(of: rotator.model) { rotator.modifiedAt = .now }
        .onChange(of: rotator.deviceName) { rotator.modifiedAt = .now }
        .onChange(of: rotator.notes) { rotator.modifiedAt = .now }
    }
}
