//
//  SettingsRootView.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2. NAVI-56: replaces the old sheet-of-sheets
//  SettingsView with the native macOS Settings-scene pattern (App menu ⌘, + a Safari/Mail-style
//  toolbar of panes), so Servers/Observatories/Rigs are toolbar tabs rather than nested sheets.
//

import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }

            APIKeySettingsPane()
                .tabItem { Label("API Key", systemImage: "key.fill") }

            ServerSettingsPane()
                .tabItem { Label("Servers", systemImage: "server.rack") }

            ObservatorySettingsPane()
                .tabItem { Label("Observatories", systemImage: "location") }

            RigSettingsPane()
                .tabItem { Label("Rigs", systemImage: "scope") }
        }
        .frame(width: 520, height: 460)
    }
}
