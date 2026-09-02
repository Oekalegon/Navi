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

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    var body: some View {
        SettingsDetailForm(title: rotator.displayName) {
            LabeledField("Name") {
                TextField("Falcon Rotator", text: $rotator.name)
                        .focused($isNameFocused)
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
        .onAppear { if rotator.name.isEmpty { isNameFocused = true } }
        .onChange(of: changeKey) { rotator.modifiedAt = .now }
    }

    /// Every editable field folded into one comparable value, so `modifiedAt` is stamped from a
    /// single `.onChange` rather than one per field. `modifiedAt` drives
    /// `RigProfile.hasStaleLibraryReferences`, so a field missing here means edits to it leave a
    /// rig claiming to be in sync when it isn't — keeping the list in one place makes that easier
    /// to spot than ten separate handlers anyone could forget to extend.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(rotator.name)
        parts.append(rotator.make ?? "")
        parts.append(rotator.model ?? "")
        parts.append(rotator.deviceName ?? "")
        parts.append(rotator.notes ?? "")
        return parts.joined(separator: "\u{1F}")
    }

}
