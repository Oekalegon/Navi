//
//  MountEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// Editor for one `MountProfile` (§4.3's equipment library). Edits bind straight to the record and
/// take effect immediately — macOS Settings treats any edit as committed, so there's no Save/Cancel
/// pair and no local `@State` mirror. A blank record is inserted by the pane's "+" and edited in
/// place. `deviceName` is picker-only while connected (§4.2).
struct MountEditForm: View {
    @Bindable var mount: MountProfile

    var body: some View {
        SettingsDetailForm(title: mount.displayName) {
            LabeledField("Name") {
                TextField("EQ6-R Pro", text: $mount.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Sky-Watcher", text: Binding(nilAsEmpty: $mount.make))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("EQ6-R Pro", text: Binding(nilAsEmpty: $mount.model))
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $mount.deviceName)
            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $mount.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onChange(of: mount.name) { mount.modifiedAt = .now }
        .onChange(of: mount.make) { mount.modifiedAt = .now }
        .onChange(of: mount.model) { mount.modifiedAt = .now }
        .onChange(of: mount.deviceName) { mount.modifiedAt = .now }
        .onChange(of: mount.notes) { mount.modifiedAt = .now }
    }
}
