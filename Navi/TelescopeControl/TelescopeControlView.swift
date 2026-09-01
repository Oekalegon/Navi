//
//  TelescopeControlView.swift
//  Navi
//
//  Hosts the Mount and Camera panels as tabs, echoing Ekos's per-device INDI control panel tabs
//  (NAVI-52). Mount stays a mockup (NAVI-53 backlog: a real Mount panel needs its own design
//  pass); Camera is wired to INDIMCPKit.
//

import SwiftUI

struct TelescopeControlView: View {
    var pane: SplitPane

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            TabView {
                MountPanelView()
                    .tabItem { Label("Mount", systemImage: "scope") }

                CameraPanelView()
                    .tabItem { Label("Camera", systemImage: "camera.aperture") }
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
