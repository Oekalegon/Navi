//
//  TelescopeControlView.swift
//  Navi
//
//  Mockup shell — NOT wired to INDIMCPKit yet. Static/sample state only,
//  meant for reacting to layout in the Xcode preview before real
//  integration work starts. Hosts the Mount and Camera panels as tabs,
//  echoing Ekos's per-device INDI control panel tabs.
//

import SwiftUI

struct TelescopeControlView: View {
    var body: some View {
        TabView {
            MountPanelView()
                .tabItem { Label("Mount", systemImage: "scope") }

            CameraPanelView()
                .tabItem { Label("Camera", systemImage: "camera.aperture") }
        }
        .frame(minWidth: 360, idealWidth: 380, minHeight: 620, idealHeight: 700)
    }
}

#Preview {
    TelescopeControlView()
}
