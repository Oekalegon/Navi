//
//  ObservatoryDashboardView.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §3.3, §4.6. The one pane in the app that opens
//  automatically — the moment Connect succeeds (TelescopeToolbarButton.connect()) — rather than
//  via a toolbar toggle.
//

import SwiftUI
import AstroKit
import AstroKitUI
import INDIMCPKit

struct ObservatoryDashboardView: View {
    var pane: SplitPane
    @State private var telescope = TelescopeSessionManager.shared
    @State private var observatory: INDIObservatory?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: observatoryTaskID) {
            await loadObservatory()
        }
        .task(id: telescope.connectionSessionID) {
            await holdDeviceAcquisitions()
        }
    }

    // Re-fetch whenever the armed observatory changes, or a fresh connection might have a
    // different one armed than the last time this pane loaded.
    private var observatoryTaskID: String? {
        telescope.state == .connected ? telescope.armedObservatoryID : nil
    }

    // Acquires every connectable component's device for the lifetime of one connected session,
    // releasing them all when this task is cancelled — either by `connectionSessionID` changing
    // (disconnect, connection loss, or a fresh reconnect even to the same rig) or by this view
    // disappearing (pane closed). `connectionSessionID` rather than `currentRig?.id` as the task
    // id specifically so a reconnect to the *same* rig still re-acquires: the id wouldn't change
    // in that case, but the underlying ObservableDevice instances were already torn down by the
    // intervening disconnect.
    private func holdDeviceAcquisitions() async {
        guard let rig = telescope.currentRig else { return }
        let roles = rig.components.compactMap { $0.device != nil ? $0.role : nil }
        guard !roles.isEmpty else { return }
        for role in roles { telescope.acquireDevice(for: role) }
        defer { for role in roles { telescope.releaseDevice(for: role) } }
        try? await Task.sleep(for: .seconds(86400))
    }

    private var headerBar: some View {
        PaneHeaderBar(paneType: .observatoryDashboard, pane: pane) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14))
            Text("Dashboard")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if telescope.state != .connected {
            disconnectedState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    timeSection
                    observatorySection
                    rigSection
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var disconnectedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not connected")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Time / Local Sidereal Time

    private var timeSection: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 24) {
                labeledValue("Time") {
                    Text(timeline.date, style: .time)
                }
                if let lst = localSiderealTime(at: timeline.date) {
                    labeledValue("Local Sidereal Time") {
                        Text(AngleFormatter(format: .hms, precision: 3).attributedString(from: lst))
                    }
                }
            }
        }
    }

    private func localSiderealTime(at date: Date) -> Double? {
        guard let observatory else { return nil }
        return SiderealTime(observatory: AstroObservatory(indi: observatory), date: date).local
    }

    // MARK: - Observatory

    @ViewBuilder
    private var observatorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Observatory").font(.headline)
            if let observatory {
                HStack(spacing: 24) {
                    labeledValue("Latitude") {
                        Text(AngleFormatter(format: .sdms, precision: 2)
                            .attributedString(from: observatory.latitudeDeg * .pi / 180))
                    }
                    labeledValue("Longitude") {
                        Text(AngleFormatter(format: .dms, precision: 2)
                            .attributedString(from: observatory.longitudeDeg * .pi / 180))
                    }
                    labeledValue("Elevation") {
                        Text("\(observatory.elevationMeters, specifier: "%.0f") m")
                    }
                }
                // Recomputed every minute, not just once on load: a session left connected
                // across a day boundary (this app targets an always-on observatory Pi, so
                // multi-day connections are plausible) would otherwise keep showing a stale
                // night's rise/set times indefinitely.
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    sunTimesRow(for: observatory, now: timeline.date)
                }
            } else if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No observatory selected").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sunTimesRow(for observatory: INDIObservatory, now: Date) -> some View {
        let astroObservatory = AstroObservatory(indi: observatory)
        let times = Sun().riseTransitSet(
            on: now, at: astroObservatory, window: .night, altitude: .standardAltitudeSun
        )
        return HStack(spacing: 24) {
            labeledValue("Sunset") {
                Text(times.set.map(Self.timeOfDay) ?? "—")
            }
            labeledValue("Sunrise") {
                Text(times.rise.map(Self.timeOfDay) ?? "—")
            }
        }
    }

    private static func timeOfDay(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func loadObservatory() async {
        observatory = nil
        loadError = nil
        guard let id = telescope.armedObservatoryID, telescope.state == .connected else { return }
        do {
            observatory = try await telescope.getObservatory(id: id)
        } catch {
            loadError = TelescopeSessionManager.describe(error)
        }
    }

    // MARK: - Rig components

    @ViewBuilder
    private var rigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rig").font(.headline)
            if let rig = telescope.currentRig {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rig.components, id: \.id) { component in
                        componentRow(component)
                    }
                }
            } else {
                Text("No rig connected").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func componentRow(_ component: Component) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.roleIcons[component.role.rawValue] ?? "cpu")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(component.model ?? component.make ?? Self.displayName(for: component.role))
            Spacer()
            statusBadge(for: component)
        }
    }

    // A passive item (e.g. an OTA) has `device == nil` — no connection state to show at all,
    // matching TelescopeSessionManager.disconnect()'s own `component.device != nil` idiom.
    @ViewBuilder
    private func statusBadge(for component: Component) -> some View {
        if component.device == nil {
            EmptyView()
        } else if let device = telescope.device(for: component.role) {
            switch Self.status(for: device) {
            case .connected:
                Image(systemName: "circle.fill")
                    .foregroundStyle(.green)
                    .help("Connected")
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(device.lastError ?? "Error")
            case .disconnected:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .help("Disconnected")
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private enum ComponentStatus { case connected, disconnected, error }

    // ObservableDevice has no ready-made tri-state status enum: `isConnected: Bool?` is itself
    // tri-state (nil = not yet observed), and `lastError` is never cleared by a later success —
    // so `lastError != nil` alone isn't "currently erroring," only "something has failed at some
    // point." Treated here as: live-connected wins outright, otherwise a recorded failure reads
    // as an error state, otherwise disconnected (including "never observed yet").
    private static func status(for device: ObservableDevice) -> ComponentStatus {
        if device.isConnected == true { return .connected }
        if device.lastError != nil { return .error }
        return .disconnected
    }

    private static let roleIcons: [String: String] = [
        Role.mount.rawValue: "gyroscope",
        Role.telescope.rawValue: "circle.dotted",
        Role.guideTelescope.rawValue: "circle.dotted",
        Role.camera.rawValue: "camera",
        Role.guideCamera.rawValue: "camera.viewfinder",
        Role.focuser.rawValue: "camera.macro",
        Role.filterWheel.rawValue: "circle.grid.3x3",
        Role.rotator.rawValue: "rotate.right",
        Role.powerHub.rawValue: "bolt",
        Role.observatoryControl.rawValue: "building.columns",
        Role.flatScreen.rawValue: "rectangle.on.rectangle",
        Role.dewHeater.rawValue: "flame"
    ]

    private static let roleNames: [String: String] = [
        Role.mount.rawValue: "Mount",
        Role.telescope.rawValue: "Optical Assembly",
        Role.guideTelescope.rawValue: "Guide Optical Assembly",
        Role.camera.rawValue: "Camera",
        Role.guideCamera.rawValue: "Guide Camera",
        Role.focuser.rawValue: "Focuser",
        Role.filterWheel.rawValue: "Filter Wheel",
        Role.rotator.rawValue: "Rotator",
        Role.powerHub.rawValue: "Power Hub",
        Role.observatoryControl.rawValue: "Observatory Control",
        Role.flatScreen.rawValue: "Flat Screen",
        Role.dewHeater.rawValue: "Dew Heater"
    ]

    private static func displayName(for role: Role) -> String {
        roleNames[role.rawValue] ?? role.rawValue.capitalized
    }

    @ViewBuilder
    private func labeledValue<Content: View>(
        _ label: String, @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// AstroKit's `Observatory` takes lon/lat in radians; INDIMCPKit's uses degrees. Both packages
// have a type literally named `Observatory` (docs/design/INDI-MCP-Integration.md §4.6) — and
// each also shadows its own module name with an empty enum of the same name, which defeats a
// bare `AstroKit.Observatory`/`INDIMCPKit.Observatory` qualification once both are imported in
// one file. Use the `AstroObservatory`/`INDIObservatory` typealiases (declared from single-
// import contexts in AstroKitObservatoryAlias.swift / TelescopeSessionManager.swift) instead.
// Not `private`: covered directly by AstroKitObservatoryAliasTests.
extension AstroObservatory {
    init(indi: INDIObservatory) {
        self.init(
            longitude: indi.longitudeDeg * .pi / 180,
            latitude: indi.latitudeDeg * .pi / 180,
            height: indi.elevationMeters
        )
    }
}
