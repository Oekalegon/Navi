//
//  CameraLikeEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI
import SwiftData

/// The one add/edit form behind both `CameraEditForm` and `GuideCameraEditForm` — they were
/// identical apart from the type and two placeholders (see `CameraLikeProfile`'s doc comment).
/// `deviceName` is picker-only while connected (§4.2), via `DevicePickerField`; every other field
/// is freely editable offline.
///
/// `makeNew` rather than a protocol initializer requirement: `@Model` types can't satisfy an
/// `init` requirement through the macro-generated memberwise init, so the caller supplies the
/// create path directly.
struct CameraLikeEditForm<Subject: CameraLikeProfile>: View {
    @Environment(\.modelContext) private var modelContext
    let subject: Subject?
    /// "Camera" / "Guide Camera" — drives the header ("Add Camera" / "Edit Guide Camera").
    let noun: String
    let namePlaceholder: String
    let makePlaceholder: String
    let makeNew: () -> Subject
    var onSaved: (Subject) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77) — Cancel only.
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var deviceName: String?
    @State private var cooled = false
    @State private var pixelsX: Int?
    @State private var pixelsY: Int?
    @State private var pixelSizeMicron: Double?
    @State private var bitDepth: Int?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(subject == nil ? "Add \(noun)" : "Edit \(noun)")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledField("Name") {
                        TextField(namePlaceholder, text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        LabeledField("Make") {
                            TextField(makePlaceholder, text: $make)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Model") {
                            TextField(namePlaceholder, text: $model)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    DevicePickerField(label: "INDI Device", deviceName: $deviceName)
                    Toggle("Cooled", isOn: $cooled)
                    HStack(spacing: 12) {
                        LabeledField("Pixels X") {
                            TextField("0", value: $pixelsX, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Pixels Y") {
                            TextField("0", value: $pixelsY, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    HStack(spacing: 12) {
                        LabeledField("Pixel Size (µm)") {
                            TextField("0", value: $pixelSizeMicron, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Bit Depth") {
                            TextField("0", value: $bitDepth, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
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
            name = subject?.name ?? ""
            make = subject?.make ?? ""
            model = subject?.model ?? ""
            deviceName = subject?.deviceName
            cooled = subject?.cooled ?? false
            pixelsX = subject?.pixelsX
            pixelsY = subject?.pixelsY
            pixelSizeMicron = subject?.pixelSizeMicron
            bitDepth = subject?.bitDepth
            notes = subject?.notes ?? ""
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

        let saved: Subject
        if let subject {
            saved = subject
        } else {
            let created = makeNew()
            modelContext.insert(created)
            saved = created
        }
        saved.name = trimmedName
        saved.make = trimmedMake.isEmpty ? nil : trimmedMake
        saved.model = trimmedModel.isEmpty ? nil : trimmedModel
        saved.deviceName = deviceName
        saved.cooled = cooled
        saved.pixelsX = pixelsX
        saved.pixelsY = pixelsY
        saved.pixelSizeMicron = pixelSizeMicron
        saved.bitDepth = bitDepth
        saved.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        saved.modifiedAt = .now

        try? modelContext.save()
        onSaved(saved)
    }
}
