//
//  DriverPickerField.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import SwiftUI
import INDIMCPKit

/// One preferred-INDI-driver field in an equipment editor (§4.3) — mirrors `DevicePickerField`'s
/// shape exactly (same connected/disconnected branching, same `sharedDrivers`-avoids-redundant-
/// fetch pattern), but over `telescope.driverCatalog() -> [DriverInfo]` instead of
/// `liveDeviceNames() -> [String]`, and binds `DriverInfo.label` rather than a device name.
///
/// A driver's `label` and the INDI device name(s) it ends up exposing are decoupled at the protocol
/// level — starting a driver doesn't tell you what device name it will produce
/// (`TelescopeSessionManager.liveDeviceNames()`'s own doc comment flags this exact gap). So this
/// field is **informational plus a manual convenience**, not an auto-bind: picking a driver here
/// doesn't touch the entity's own `deviceName` (still set independently via `DevicePickerField`) —
/// it just remembers which driver this equipment expects, with a "Start Driver" shortcut
/// (`TelescopeSessionManager.startDriver(label:)`, the same call `DriverManagementSheet` makes) so
/// the user doesn't have to leave this form to bootstrap it.
///
/// The "Start Driver"/running-state row only appears when this field manages its own fetch
/// (`sharedDrivers == nil`) — when a parent shares one catalog fetch across several fields (see
/// `EquipmentSettingsPane`), running-driver state isn't shared alongside it, so showing a
/// potentially-stale Start button there would be misleading; the Servers pane's own Driver
/// Management section remains the place to start/stop drivers in that context.
struct DriverPickerField: View {
    let label: String
    @Binding var driverLabel: String?
    var sharedDrivers: [DriverInfo]?
    @State private var telescope = TelescopeSessionManager.shared
    @State private var ownDrivers: [DriverInfo] = []
    @State private var runningLabels: Set<String> = []
    @State private var isLoading = false
    @State private var isStarting = false
    @State private var loadError: String?

    private var isConnected: Bool { telescope.state == .connected }
    private var availableDrivers: [DriverInfo] { sharedDrivers ?? ownDrivers }
    private var availableLabels: [String] { availableDrivers.map(\.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isConnected {
                Picker(label, selection: $driverLabel) {
                    Text("None").tag(String?.none)
                    // The currently-bound driver is always offered even if it didn't come back in
                    // this load, matching `DevicePickerField.devicesIncludingCurrent`'s reasoning.
                    ForEach(labelsIncludingCurrent, id: \.self) { candidate in
                        Text(isInstalled(candidate) ? candidate : "\(candidate) (Not Installed)")
                            .tag(String?.some(candidate))
                    }
                }
                .labelsHidden()
                .task {
                    guard sharedDrivers == nil else { return }
                    await loadCatalog()
                }
                if sharedDrivers == nil, let driverLabel {
                    startDriverRow(for: driverLabel)
                }
            } else {
                HStack {
                    Text(driverLabel ?? "Not set")
                        .font(.body)
                        .foregroundStyle(driverLabel == nil ? .secondary : .primary)
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

    private var labelsIncludingCurrent: [String] {
        guard let driverLabel, !availableLabels.contains(driverLabel) else { return availableLabels }
        return ([driverLabel] + availableLabels).sorted()
    }

    private func isInstalled(_ label: String) -> Bool {
        // Unknown (not in the loaded catalog, e.g. authored offline) — don't flag it as missing on
        // no evidence either way.
        availableDrivers.first { $0.label == label }?.installed ?? true
    }

    @ViewBuilder
    private func startDriverRow(for label: String) -> some View {
        HStack(spacing: 6) {
            if isStarting {
                ProgressView().controlSize(.small)
            } else if runningLabels.contains(label) {
                Label("Running", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if !isInstalled(label) {
                Text("Not installed on server")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button("Start Driver") { Task { await start(label) } }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        }
    }

    private func loadCatalog() async {
        guard ownDrivers.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let catalogTask = telescope.driverCatalog()
            async let runningTask = telescope.runningDrivers()
            let (catalog, running) = try await (catalogTask, runningTask)
            ownDrivers = catalog
            runningLabels = Set(running.filter(\.running).map(\.label))
        } catch {
            loadError = TelescopeSessionManager.describe(error)
        }
    }

    private func start(_ label: String) async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await telescope.startDriver(label: label)
            runningLabels.insert(label)
        } catch {
            loadError = TelescopeSessionManager.describe(error)
        }
    }
}
