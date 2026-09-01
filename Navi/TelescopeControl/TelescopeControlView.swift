//
//  TelescopeControlView.swift
//  Navi
//
//  Hosts the Mount and Camera panels behind a segmented switcher, echoing Ekos's per-device INDI
//  control panel tabs (NAVI-52). Mount stays a mockup (NAVI-53 backlog: a real Mount panel needs
//  its own design pass); Camera is wired to INDIMCPKit.
//
//  Deliberately not a `TabView` (NAVI-76): on macOS, TabView's default style backs onto
//  NSTabViewController, which can fold its tab picker directly into the *window's* toolbar
//  regardless of how deeply the TabView is nested — that hijacked Navi's own toolbar, pushing the
//  telescope selection/Connect button to the trailing edge the moment this pane appeared. A plain
//  segmented Picker gives the same look with no AppKit toolbar integration.
//
//  Both panels stay in the view tree at all times (opacity/hit-testing toggled, not conditionally
//  rendered) rather than switching between them — NSTabViewController kept its child view
//  controllers alive across tab switches, and CameraPanelView holds meaningful unsaved local state
//  (exposure/gain/offset/binning/target temp) that switching to Mount and back must not silently
//  reset. NAVI-75 will remove this switcher entirely in favor of separate Mount/Camera panes.
//

import SwiftUI

struct TelescopeControlView: View {
    var pane: SplitPane

    private enum Device: String, CaseIterable, Identifiable {
        case mount = "Mount"
        case camera = "Camera"
        var id: String { rawValue }
    }

    @State private var selectedDevice: Device = .mount

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            Picker("Device", selection: $selectedDevice) {
                ForEach(Device.allCases) { device in
                    Text(device.rawValue).tag(device)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            ZStack {
                MountPanelView()
                    .opacity(selectedDevice == .mount ? 1 : 0)
                    .allowsHitTesting(selectedDevice == .mount)
                    .accessibilityHidden(selectedDevice != .mount)
                CameraPanelView()
                    .opacity(selectedDevice == .camera ? 1 : 0)
                    .allowsHitTesting(selectedDevice == .camera)
                    .accessibilityHidden(selectedDevice != .camera)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerBar: some View {
        PaneHeaderBar(paneType: .telescopeControl, pane: pane) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14))
            Text("Telescope Control")
                .font(.headline)
        }
    }
}

#Preview {
    TelescopeControlView(pane: SplitPane(type: .telescopeControl))
}
