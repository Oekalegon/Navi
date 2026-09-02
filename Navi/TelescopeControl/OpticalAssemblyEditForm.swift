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

    /// "+" inserts a blank record and selects it, so the editor opens on something with no name.
    /// Focusing the name field means the next keystroke names it, rather than leaving a row reading
    /// "Untitled Camera" that's indistinguishable from the next one someone adds.
    @FocusState private var isNameFocused: Bool

    /// Mirrors `hasFocuser` but is tracked separately so toggling it off, clearing the fields, and
    /// toggling back on doesn't fight the derived value mid-edit.
    @State private var includesFocuser = false

    var body: some View {
        SettingsDetailForm(title: opticalAssembly.displayName) {
            LabeledField("Name") {
                TextField("Esprit 100", text: $opticalAssembly.name)
                        .focused($isNameFocused)
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
        .onAppear {
            if opticalAssembly.name.isEmpty { isNameFocused = true }
            includesFocuser = opticalAssembly.hasFocuser
        }
        .onChange(of: changeKey) { touch() }
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

    /// Every editable field folded into one comparable value, so `modifiedAt` is stamped from a
    /// single `.onChange` rather than one per field — see `CameraLikeProfile.editableChangeKey`
    /// for why the list is kept in one place.
    private var changeKey: String {
        var parts: [String] = []
        parts.append(opticalAssembly.name)
        parts.append(opticalAssembly.make ?? "")
        parts.append(opticalAssembly.model ?? "")
        parts.append(opticalAssembly.apertureMm.map { "\($0)" } ?? "")
        parts.append(opticalAssembly.focalLengthMm.map { "\($0)" } ?? "")
        parts.append(opticalAssembly.opticalDesign?.rawValue ?? "")
        parts.append(opticalAssembly.focuserMake ?? "")
        parts.append(opticalAssembly.focuserModel ?? "")
        parts.append(opticalAssembly.focuserDeviceName ?? "")
        parts.append(opticalAssembly.focuserMinPosition.map { "\($0)" } ?? "")
        parts.append(opticalAssembly.focuserMaxPosition.map { "\($0)" } ?? "")
        parts.append(opticalAssembly.notes ?? "")
        return parts.joined(separator: "\u{1F}")
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
