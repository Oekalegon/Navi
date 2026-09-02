//
//  OpticalAssemblyEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// Add/edit form for one `OpticalAssemblyProfile` (§4.3) — shared by the Rig editor's main
/// optical assembly and guide optical assembly sections, which are ordinary, independently-
/// reusable records distinguished only by `OpticalAssemblyPurpose` (§4.3). `purpose` is fixed by
/// the caller (not user-editable here) so a record created from the "guide optical assembly"
/// section can't accidentally end up `.mainImaging`-purposed or vice versa.
///
/// The focuser fields are all optional together (`nil` for all of them means "no focuser" —
/// `OpticalAssemblyProfile.hasFocuser`); `focuserDeviceName` is picker-only while connected
/// (§4.2), matching `DevicePickerField`'s contract.
struct OpticalAssemblyEditForm: View {
    @Environment(\.modelContext) private var modelContext
    let opticalAssembly: OpticalAssemblyProfile?
    let purpose: OpticalAssemblyPurpose
    var onSaved: (OpticalAssemblyProfile) -> Void = { _ in }
    /// See `MountEditForm.onFinished`'s doc comment (NAVI-77).
    var onFinished: () -> Void = {}

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var apertureMm: Double?
    @State private var focalLengthMm: Double?
    @State private var opticalDesign: OpticalDesign?
    @State private var includesFocuser = false
    @State private var focuserMake = ""
    @State private var focuserModel = ""
    @State private var focuserDeviceName: String?
    @State private var focuserMinPosition: Int?
    @State private var focuserMaxPosition: Int?
    @State private var notes = ""
    @State private var validationError: String?

    var body: some View {
        SettingsDetailForm(title: opticalAssembly == nil ? "Add Optical Assembly" : "Edit Optical Assembly") {
            LabeledField("Name") {
                TextField("Esprit 100", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Sky-Watcher", text: $make)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("Esprit 100", text: $model)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 12) {
                LabeledField("Aperture (mm)") {
                    TextField("0", value: $apertureMm, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Focal Length (mm)") {
                    TextField("0", value: $focalLengthMm, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            LabeledField("Optical Design") {
                Picker("Optical Design", selection: $opticalDesign) {
                    Text("Unspecified").tag(OpticalDesign?.none)
                    ForEach(OpticalDesign.allCases, id: \.self) { design in
                        Text(design.displayName).tag(OpticalDesign?.some(design))
                    }
                }
                .labelsHidden()
            }

            Divider()

            Toggle("Has Focuser", isOn: $includesFocuser)

            if includesFocuser {
                HStack(spacing: 12) {
                    LabeledField("Focuser Make") {
                        TextField("ZWO", text: $focuserMake)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Focuser Model") {
                        TextField("EAF", text: $focuserModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                DevicePickerField(label: "Focuser INDI Device", deviceName: $focuserDeviceName)
                HStack(spacing: 12) {
                    LabeledField("Min Position") {
                        TextField("0", value: $focuserMinPosition, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Max Position") {
                        TextField("0", value: $focuserMaxPosition, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

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
            name = opticalAssembly?.name ?? ""
            make = opticalAssembly?.make ?? ""
            model = opticalAssembly?.model ?? ""
            apertureMm = opticalAssembly?.apertureMm
            focalLengthMm = opticalAssembly?.focalLengthMm
            opticalDesign = opticalAssembly?.opticalDesign
            includesFocuser = opticalAssembly?.hasFocuser ?? false
            focuserMake = opticalAssembly?.focuserMake ?? ""
            focuserModel = opticalAssembly?.focuserModel ?? ""
            focuserDeviceName = opticalAssembly?.focuserDeviceName
            focuserMinPosition = opticalAssembly?.focuserMinPosition
            focuserMaxPosition = opticalAssembly?.focuserMaxPosition
            notes = opticalAssembly?.notes ?? ""
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
        let trimmedFocuserMake = focuserMake.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFocuserModel = focuserModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Has Focuser" toggled off clears every focuser field together, matching
        // `OpticalAssemblyProfile.hasFocuser`'s "all optional together" contract.
        let resolvedFocuserMake = includesFocuser && !trimmedFocuserMake.isEmpty ? trimmedFocuserMake : nil
        let resolvedFocuserModel = includesFocuser && !trimmedFocuserModel.isEmpty ? trimmedFocuserModel : nil
        let resolvedFocuserDevice = includesFocuser ? focuserDeviceName : nil
        let resolvedFocuserMin = includesFocuser ? focuserMinPosition : nil
        let resolvedFocuserMax = includesFocuser ? focuserMaxPosition : nil

        let saved: OpticalAssemblyProfile
        if let opticalAssembly {
            opticalAssembly.name = trimmedName
            opticalAssembly.make = trimmedMake.isEmpty ? nil : trimmedMake
            opticalAssembly.model = trimmedModel.isEmpty ? nil : trimmedModel
            opticalAssembly.apertureMm = apertureMm
            opticalAssembly.focalLengthMm = focalLengthMm
            opticalAssembly.opticalDesign = opticalDesign
            opticalAssembly.purpose = purpose
            opticalAssembly.focuserMake = resolvedFocuserMake
            opticalAssembly.focuserModel = resolvedFocuserModel
            opticalAssembly.focuserDeviceName = resolvedFocuserDevice
            opticalAssembly.focuserMinPosition = resolvedFocuserMin
            opticalAssembly.focuserMaxPosition = resolvedFocuserMax
            opticalAssembly.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            opticalAssembly.modifiedAt = .now
            saved = opticalAssembly
        } else {
            let created = OpticalAssemblyProfile(
                name: trimmedName,
                make: trimmedMake.isEmpty ? nil : trimmedMake,
                model: trimmedModel.isEmpty ? nil : trimmedModel,
                apertureMm: apertureMm,
                focalLengthMm: focalLengthMm,
                opticalDesign: opticalDesign,
                purpose: purpose,
                focuserMake: resolvedFocuserMake,
                focuserModel: resolvedFocuserModel,
                focuserDeviceName: resolvedFocuserDevice,
                focuserMinPosition: resolvedFocuserMin,
                focuserMaxPosition: resolvedFocuserMax,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            modelContext.insert(created)
            saved = created
        }
        try? modelContext.save()
        onSaved(saved)
    }
}

extension OpticalDesign {
    var displayName: String {
        switch self {
        case .refractor: return "Refractor"
        case .newtonian: return "Newtonian"
        case .schmidtCassegrain: return "Schmidt-Cassegrain"
        case .ritcheyChretien: return "Ritchey-Chrétien"
        case .maksutovCassegrain: return "Maksutov-Cassegrain"
        case .other: return "Other"
        }
    }
}
