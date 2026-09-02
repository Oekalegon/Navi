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

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    var body: some View {
        SettingsDetailForm(title: equipment.displayName) {
            LabeledField("Name") {
                TextField("\(equipment.role.title) 1", text: $equipment.name)
                        .focused($isNameFocused)
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
        .onAppear { if equipment.name.isEmpty { isNameFocused = true } }
        .onChange(of: changeKey) { equipment.modifiedAt = .now }
    }

    /// Every editable field folded into one comparable value, so `modifiedAt` is stamped from a
    /// single `.onChange` rather than one per field. `modifiedAt` drives
    /// `RigProfile.hasStaleLibraryReferences`, so a field missing here means edits to it leave a
    /// rig claiming to be in sync when it isn't — keeping the list in one place makes that easier
    /// to spot than ten separate handlers anyone could forget to extend.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(equipment.name)
        parts.append(equipment.make ?? "")
        parts.append(equipment.model ?? "")
        parts.append(equipment.deviceName ?? "")
        parts.append(equipment.notes ?? "")
        return parts.joined(separator: "\u{1F}")
    }

}
