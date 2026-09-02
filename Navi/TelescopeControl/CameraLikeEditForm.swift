//
//  CameraLikeEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData

/// The one editor behind both `CameraEditForm` and `GuideCameraEditForm` — they were identical
/// apart from the type and two placeholders (see `CameraLikeProfile`'s doc comment).
///
/// Edits bind straight to the record and take effect immediately: macOS Settings treats any edit as
/// committed, so there is no Save/Cancel pair and no local `@State` mirror to write through. A new
/// record is inserted blank by the pane's "+" and edited in place, which is why `subject` is
/// non-optional here.
///
/// `deviceName` is picker-only while connected (§4.2), via `DevicePickerField`; every other field is
/// freely editable offline.
struct CameraLikeEditForm<Subject: CameraLikeProfile>: View {
    @Bindable var subject: Subject
    let namePlaceholder: String
    let makePlaceholder: String

    var body: some View {
        SettingsDetailForm(title: subject.displayName) {
            LabeledField("Name") {
                // Optional: blank falls back to make/model for display (see equipmentDisplayName).
                TextField(namePlaceholder, text: $subject.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField(makePlaceholder, text: Binding(nilAsEmpty: $subject.make))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField(namePlaceholder, text: Binding(nilAsEmpty: $subject.model))
                        .textFieldStyle(.roundedBorder)
                }
            }
            DevicePickerField(label: "INDI Device", deviceName: $subject.deviceName)
            Toggle("Cooled", isOn: Binding(nilAsFalse: $subject.cooled))
            HStack(spacing: 12) {
                LabeledField("Pixels X") {
                    TextField("0", value: $subject.pixelsX, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Pixels Y") {
                    TextField("0", value: $subject.pixelsY, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 12) {
                LabeledField("Pixel Size (µm)") {
                    TextField("0", value: $subject.pixelSizeMicron, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Bit Depth") {
                    TextField("0", value: $subject.bitDepth, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $subject.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        // Any edit counts as a modification for the §4.3 "Resync all" staleness check, which used
        // to be stamped by the Save button.
        .onChange(of: subject.name) { touch() }
        .onChange(of: subject.make) { touch() }
        .onChange(of: subject.model) { touch() }
        .onChange(of: subject.deviceName) { touch() }
        .onChange(of: subject.cooled) { touch() }
        .onChange(of: subject.pixelsX) { touch() }
        .onChange(of: subject.pixelsY) { touch() }
        .onChange(of: subject.pixelSizeMicron) { touch() }
        .onChange(of: subject.bitDepth) { touch() }
        .onChange(of: subject.notes) { touch() }
    }

    private func touch() {
        subject.modifiedAt = .now
    }
}
