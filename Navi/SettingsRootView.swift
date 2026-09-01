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
    enum Tab: Hashable {
        case general, apiKey, servers, observatories, equipment, imagingTrain, rigs
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

            // NAVI-85: Equipment sits before Rigs (not after Observatories) since a rig is
            // composed *from* equipment, but has nothing to do with Observatories.
            EquipmentSettingsPane()
                .id(Tab.equipment)
                .tabItem { Label("Equipment", systemImage: "wrench.and.screwdriver") }
                .tag(Tab.equipment)

            // Composition of equipment (Camera/Filter Wheel/Rotator), not equipment itself — its
            // own tab rather than a section in Equipment, the same reasoning Rigs already follows.
            ImagingTrainSettingsPane()
                .id(Tab.imagingTrain)
                .tabItem { Label("Imaging Train", systemImage: "camera.on.rectangle") }
                .tag(Tab.imagingTrain)

            RigSettingsPane()
                .id(Tab.rigs)
                .tabItem { Label("Rigs", systemImage: "scope") }
                .tag(Tab.rigs)
        }
        .frame(width: 900, height: 640)
        // NAVI-85: lets RigEditForm's empty-equipment-library message jump straight to the
        // Equipment tab, without RigEditForm needing to know anything about `Tab` beyond the one
        // case it asks for — see `SettingsTabNavigation.swift`.
        .environment(\.selectSettingsTab, { selectedTab = $0 })
    }
}
