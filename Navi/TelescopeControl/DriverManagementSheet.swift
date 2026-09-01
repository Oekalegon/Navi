//
//  DriverManagementSheet.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/I-1's "Driver list" — NAVI-62. Lets the user
//  start/stop an INDI driver directly, independent of any rig's connect cascade: bootstrapping a
//  brand-new rig is otherwise a chicken-and-egg problem, since a rig's device picker only ever
//  shows a device once its driver is already running, but nothing starts a driver until a rig
//  with a binding for it exists — which needs the device picker to have shown something first.
//

import SwiftUI
import INDIMCPKit

/// Embedded inline in `ServerSettingsPane`'s detail pane (NAVI-77) — shown only while its
/// `serverName` is the one currently connected. Since the parent already conditions this view's
/// presence on `telescope.state == .connected`, it disappears on its own the next render after a
/// disconnect; no dismiss/auto-dismiss machinery needed here.
struct DriverManagementSheet: View {
    let serverName: String
    @State private var telescope = TelescopeSessionManager.shared

    @State private var catalog: [DriverInfo] = []
    @State private var runningLabels: Set<String> = []
    @State private var isLoading = false
    @State private var busyLabels: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Drivers")
                .font(.headline)
            Text(serverName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && catalog.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if catalog.isEmpty {
            emptyState
        } else {
            List(catalog, id: \.label) { driver in
                row(for: driver)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No drivers found")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for driver: DriverInfo) -> some View {
        let isRunning = runningLabels.contains(driver.label)
        let isBusy = busyLabels.contains(driver.label)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(driver.label)
                    .font(.body)
                Text(driver.family)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 60)
            } else if !driver.installed {
                Text("Not Installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60)
            } else {
                Button(isRunning ? "Stop" : "Start") {
                    Task { await toggle(driver) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isRunning ? .red : .accentColor)
                .frame(width: 60)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage, !catalog.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button("Refresh") { Task { await refresh() } }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let catalogTask = telescope.driverCatalog()
            async let runningTask = telescope.runningDrivers()
            let (fetchedCatalog, running) = try await (catalogTask, runningTask)
            catalog = fetchedCatalog.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            runningLabels = Set(running.filter(\.running).map(\.label))
        } catch {
            errorMessage = TelescopeSessionManager.describe(error)
        }
    }

    private func toggle(_ driver: DriverInfo) async {
        busyLabels.insert(driver.label)
        defer { busyLabels.remove(driver.label) }
        do {
            if runningLabels.contains(driver.label) {
                try await telescope.stopDriver(label: driver.label)
            } else {
                try await telescope.startDriver(label: driver.label)
            }
            await refresh()
        } catch {
            errorMessage = TelescopeSessionManager.describe(error)
        }
    }
}
