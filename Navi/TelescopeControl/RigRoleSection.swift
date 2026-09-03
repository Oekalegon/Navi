//
//  RigRoleSection.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-86.
//

import SwiftUI
import SwiftData

/// One "pick which library entity fills this role" row — a toggle, and while it's on, a picker
/// plus a summary of what's picked. Shared by `RigEditForm` (nine roles) and `ImagingTrainEditForm`
/// (three), which is the point: before this they carried two copies of the same view, acknowledged
/// as duplication in both files' own comments.
///
/// `Entity` is whichever equipment/composition type the role picks from — `MountProfile`,
/// `OpticalAssemblyProfile`, `ImagingTrainProfile`, `GuideCameraProfile`, `CameraProfile`,
/// `FilterWheelProfile`, `RotatorProfile`, `StandaloneEquipmentProfile`. All nine of `RigEditForm`'s
/// roles and all three of `ImagingTrainEditForm`'s reduce to this same shape: pick one, or none, no
/// inline creation — an empty library points at the Equipment tab instead (`selectSettingsTab` in
/// the environment).
///
/// `isIncluded` is a separate binding from `selection == nil` deliberately (the NAVI-62 precedent,
/// documented at both call sites this replaces): deriving "included" purely from whether something
/// is selected meant that on an empty library, turning the toggle on immediately snapped back off —
/// `selection ?? options.first` resolves to `nil` when both are empty, so the toggle read as off
/// again on the very next render.
struct RigRoleSection<Entity: PersistentModel & Hashable>: View {
    let title: String
    @Binding var selection: Entity?
    @Binding var isIncluded: Bool
    let options: [Entity]
    let displayName: (Entity) -> String
    /// `nil` means "no device bound" (a role that's picked but blank — a valid, distinct state from
    /// the role not being picked at all, per §4.2's blank-vs-absent contract).
    let deviceSummary: (Entity) -> String?
    var deviceLabel: String = "Device"

    @Environment(\.selectSettingsTab) private var selectSettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: Binding(
                get: { isIncluded },
                set: { included in
                    isIncluded = included
                    selection = included ? (selection ?? options.first) : nil
                }
            ))
            .font(.subheadline)
            .fontWeight(.semibold)

            if isIncluded {
                Picker(title, selection: $selection) {
                    Text("None").tag(Entity?.none)
                    ForEach(options) { Text(displayName($0)).tag(Entity?.some($0)) }
                }
                .labelsHidden()

                if let selection {
                    let summary = summaryText(for: selection)
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(summary.hasSuffix("blank") ? .orange : .secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("No \(title.lowercased()) defined yet —")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("go to Equipment…") { selectSettingsTab(.equipment) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func summaryText(for entity: Entity) -> String {
        if let deviceName = deviceSummary(entity) {
            return "\(displayName(entity)) · \(deviceLabel): \(deviceName)"
        }
        return "\(displayName(entity)) · \(deviceLabel): blank"
    }
}
