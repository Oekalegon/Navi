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

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    var body: some View {
        SettingsDetailForm(title: mount.displayName) {
            LabeledField("Name") {
                TextField("EQ6-R Pro", text: $mount.name)
                        .focused($isNameFocused)
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
        .onAppear { if mount.name.isEmpty { isNameFocused = true } }
        .onChange(of: changeKey) { mount.modifiedAt = .now }
    }

    /// Every editable field folded into one comparable value, so `modifiedAt` is stamped from a
    /// single `.onChange` rather than one per field. `modifiedAt` drives
    /// `RigProfile.hasStaleLibraryReferences`, so a field missing here means edits to it leave a
    /// rig claiming to be in sync when it isn't — keeping the list in one place makes that easier
    /// to spot than ten separate handlers anyone could forget to extend.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(mount.name)
        parts.append(mount.make ?? "")
        parts.append(mount.model ?? "")
        parts.append(mount.deviceName ?? "")
        parts.append(mount.notes ?? "")
        return parts.joined(separator: "\u{1F}")
    }

}
