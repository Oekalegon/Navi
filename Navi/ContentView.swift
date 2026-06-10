//
//  ContentView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var paneManager = PaneManager()
    @State private var settings = SettingsManager.shared
    @State private var showingSettings = false

    var body: some View {
        SplitPaneView(pane: paneManager.rootPane, paneManager: paneManager)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 6) {
                        Button(action: {}) {
                            Image(systemName: "sidebar.leading")
                                .font(.system(size: 13))
                        }
                        .controlSize(.small)

                        Button(action: {}) {
                            Image(systemName: "plus")
                                .font(.system(size: 13))
                        }
                        .controlSize(.small)

                        Button(action: { paneManager.showArchivePane() }) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 13))
                        }
                        .controlSize(.small)
                        .help("Open Archive Pane")

                        Button(action: { paneManager.toggleFITSViewer() }) {
                            Image(systemName: "photo")
                                .font(.system(size: 13))
                        }
                        .controlSize(.small)
                        .help(paneManager.isFITSViewerVisible ? "Hide FITS Viewer" : "Show FITS Viewer")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                    }
                    .controlSize(.small)
                }
            }
            .environment(paneManager)
            .environment(settings)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(settings)
            }
    }
}
