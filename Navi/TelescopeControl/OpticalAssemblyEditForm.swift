//
//  OpticalAssemblyEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI
import SwiftData

/// Editor for one `OpticalAssemblyProfile` (§4.3) — shared by the main and guide optical assembly
/// kinds, which are ordinary reusable records distinguished only by `OpticalAssemblyPurpose`.
/// `purpose` is fixed when the record is created (the Equipment pane has a separate kind for each),
/// so it isn't editable here and no longer needs passing in.
///
/// The focuser fields are all optional together (`nil` for all of them means "no focuser" —
/// `OpticalAssemblyProfile.hasFocuser`); `focuserDeviceName` is picker-only while connected (§4.2).
/// See `MountEditForm` for the no-Save-button convention.
struct OpticalAssemblyEditForm: View {
    @Bindable var opticalAssembly: OpticalAssemblyProfile

    /// Mirrors `hasFocuser` but is tracked separately so toggling it off, clearing the fields, and
    /// toggling back on doesn't fight the derived value mid-edit.
    @State private var includesFocuser = false

    var body: some View {
        SettingsDetailForm(title: opticalAssembly.displayName) {
            LabeledField("Name") {
                TextField("Esprit 100", text: $opticalAssembly.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                LabeledField("Make") {
                    TextField("Sky-Watcher", text: Binding(nilAsEmpty: $opticalAssembly.make))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Model") {
                    TextField("Esprit 100", text: Binding(nilAsEmpty: $opticalAssembly.model))
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 12) {
                LabeledField("Aperture (mm)") {
                    TextField("0", value: $opticalAssembly.apertureMm, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField("Focal Length (mm)") {
                    TextField("0", value: $opticalAssembly.focalLengthMm, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            LabeledField("Optical Design") {
                Picker("Optical Design", selection: $opticalAssembly.opticalDesign) {
                    Text("Unspecified").tag(OpticalDesign?.none)
                    ForEach(OpticalDesign.allCases, id: \.self) { design in
                        Text(design.displayName).tag(OpticalDesign?.some(design))
                    }
                }
                .labelsHidden()
            }

            Divider()

            Toggle("Has Focuser", isOn: Binding(
                get: { includesFocuser },
                set: { included in
                    includesFocuser = included
                    if !included { clearFocuser() }
                    touch()
                }
            ))

            if includesFocuser {
                HStack(spacing: 12) {
                    LabeledField("Focuser Make") {
                        TextField("ZWO", text: Binding(nilAsEmpty: $opticalAssembly.focuserMake))
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Focuser Model") {
                        TextField("EAF", text: Binding(nilAsEmpty: $opticalAssembly.focuserModel))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                DevicePickerField(label: "Focuser INDI Device", deviceName: $opticalAssembly.focuserDeviceName)
                HStack(spacing: 12) {
                    LabeledField("Min Position") {
                        TextField("0", value: $opticalAssembly.focuserMinPosition, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledField("Max Position") {
                        TextField("0", value: $opticalAssembly.focuserMaxPosition, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            LabeledField("Notes") {
                TextField("Optional notes", text: Binding(nilAsEmpty: $opticalAssembly.notes))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onAppear { includesFocuser = opticalAssembly.hasFocuser }
        .onChange(of: opticalAssembly.name) { touch() }
        .onChange(of: opticalAssembly.make) { touch() }
        .onChange(of: opticalAssembly.model) { touch() }
        .onChange(of: opticalAssembly.apertureMm) { touch() }
        .onChange(of: opticalAssembly.focalLengthMm) { touch() }
        .onChange(of: opticalAssembly.opticalDesign) { touch() }
        .onChange(of: opticalAssembly.focuserMake) { touch() }
        .onChange(of: opticalAssembly.focuserModel) { touch() }
        .onChange(of: opticalAssembly.focuserDeviceName) { touch() }
        .onChange(of: opticalAssembly.focuserMinPosition) { touch() }
        .onChange(of: opticalAssembly.focuserMaxPosition) { touch() }
        .onChange(of: opticalAssembly.notes) { touch() }
    }

    /// "Has Focuser" off clears every focuser field together, matching
    /// `OpticalAssemblyProfile.hasFocuser`'s "all optional together" contract.
    private func clearFocuser() {
        opticalAssembly.focuserMake = nil
        opticalAssembly.focuserModel = nil
        opticalAssembly.focuserDeviceName = nil
        opticalAssembly.focuserMinPosition = nil
        opticalAssembly.focuserMaxPosition = nil
    }

    private func touch() {
        opticalAssembly.modifiedAt = .now
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
