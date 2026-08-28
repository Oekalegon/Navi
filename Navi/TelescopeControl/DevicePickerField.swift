//
//  DevicePickerField.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2.
//

import SwiftUI

/// One device-bearing field in the Rig editor (§4.2): a `Picker` over the live device list while
/// connected, or the currently-bound device shown as read-only text (with an explanation) while
/// not — every device-bearing field is **selection-only from the live device list, never free
/// text**, so this is the only way any editor in the Rig pane ever sets a `deviceName`.
///
/// Shared by every role's device field (mount, focuser, camera, filter wheel, rotator, guide
/// camera, and the four standalone components) rather than duplicating the connected/disconnected
/// branching at each call site.
///
/// `sharedDevices`, when supplied, is used as-is and this field never fetches on its own — lets a
/// parent form that shows several device fields at once (e.g. `RigEditForm`'s four standalone-
/// component rows) fetch `liveDeviceNames()` a single time and hand the same list to every field,
/// instead of each field independently re-issuing the same MCP call. Left `nil` (the default) for
/// call sites that only ever show one field at a time (the per-entity edit sheets), where each
/// field owning its own fetch is simplest and there's nothing to share.
struct DevicePickerField: View {
    let label: String
    @Binding var deviceName: String?
    var sharedDevices: [String]?
    @State private var telescope = TelescopeSessionManager.shared
    @State private var ownDevices: [String] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var isConnected: Bool { telescope.state == .connected }
    private var availableDevices: [String] { sharedDevices ?? ownDevices }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if deviceName == nil {
                    Text("blank")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if isConnected {
                Picker(label, selection: $deviceName) {
                    Text("None").tag(String?.none)
                    // The currently-bound device is always offered even if it didn't come back
                    // in this load — e.g. its driver isn't currently running — so picking it
                    // never silently clears a valid-but-momentarily-unlisted binding.
                    ForEach(devicesIncludingCurrent, id: \.self) { device in
                        Text(device).tag(String?.some(device))
                    }
                }
                .labelsHidden()
                .task {
                    guard sharedDevices == nil else { return }
                    await loadDevices()
                }
            } else {
                HStack {
                    Text(deviceName ?? "Not set")
                        .font(.body)
                        .foregroundStyle(deviceName == nil ? .secondary : .primary)
                    Spacer()
                    Text("Connect to change")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let loadError {
                Text(loadError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var devicesIncludingCurrent: [String] {
        guard let deviceName, !availableDevices.contains(deviceName) else { return availableDevices }
        return ([deviceName] + availableDevices).sorted()
    }

    private func loadDevices() async {
        guard ownDevices.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            ownDevices = try await telescope.liveDeviceNames()
        } catch {
            loadError = TelescopeSessionManager.describe(error)
        }
    }
}
