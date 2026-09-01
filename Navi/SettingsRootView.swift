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
    private enum Tab: Hashable {
        case general, apiKey, servers, observatories, rigs
    }

    // NAVI-77: an explicit selection binding + `.tag()` per tab, rather than relying on
    // TabView's implicit internal selection state — without it, once Servers/Observatories/Rigs
    // became `NavigationSplitView`s (each backed by its own NSSplitViewController), switching
    // tabs could leave a previous tab's sidebar content showing and desync which toolbar icon
    // looked selected. Giving SwiftUI an explicit, distinct identity per tab resolves that.
    @State private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            APIKeySettingsPane()
                .tabItem { Label("API Key", systemImage: "key.fill") }
                .tag(Tab.apiKey)

            ServerSettingsPane()
                .id(Tab.servers)
                .tabItem { Label("Servers", systemImage: "server.rack") }
                .tag(Tab.servers)

            ObservatorySettingsPane()
                .id(Tab.observatories)
                .tabItem { Label("Observatories", systemImage: "location") }
                .tag(Tab.observatories)

            RigSettingsPane()
                .id(Tab.rigs)
                .tabItem { Label("Rigs", systemImage: "scope") }
                .tag(Tab.rigs)
        }
        .frame(width: 900, height: 640)
    }
}
