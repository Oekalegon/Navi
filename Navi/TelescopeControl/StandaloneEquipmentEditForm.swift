//
//  StandaloneEquipmentEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import SwiftUI
import SwiftData

/// Editor for one `StandaloneEquipmentProfile` (§4.3) — shared by all four standalone roles (Power
/// Hub, Flat Screen, Dew Heater, Observatory Control). The role is fixed when the record is created
/// by the pane's "+", so it isn't editable here. See `MountEditForm` for the no-Save-button
/// convention.
struct StandaloneEquipmentEditForm: View {
    @Bindable var equipment: StandaloneEquipmentProfile

    var body: some View {
        SettingsDetailForm(title: equipment.displayName) {
            LabeledField("Name") {
                TextField("\(equipment.role.title) 1", text: $equipment.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Optional", text: Binding(nilAsEmpty: $equipment.make))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("Optional", text: Binding(nilAsEmpty: $equipment.model))
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $equipment.deviceName)
            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $equipment.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onChange(of: equipment.name) { equipment.modifiedAt = .now }
        .onChange(of: equipment.make) { equipment.modifiedAt = .now }
        .onChange(of: equipment.model) { equipment.modifiedAt = .now }
        .onChange(of: equipment.deviceName) { equipment.modifiedAt = .now }
        .onChange(of: equipment.notes) { equipment.modifiedAt = .now }
    }
}
