//
//  TelescopeErrorIndicator.swift
//  Navi
//
//  NAVI-69: TelescopeSessionManager.errorMessage was set on several failure paths (Connect with
//  no default server, a failed connect/reconnect, a lost connection, a failed observatory-list
//  refresh) but nothing ever displayed it — confirmed via grep, no view read it anywhere. Per
//  I-4's existing convention ("one place errors surface, read directly by views — no toasts or
//  .alert() sheets"), this is a persistent, click-to-reveal indicator (not an auto-appearing
//  alert) placed in the main toolbar next to TelescopeToolbarButton, since that's the one place
//  always visible regardless of which panes are open.
//

import SwiftUI

struct TelescopeErrorIndicator: View {
    @State private var telescope = TelescopeSessionManager.shared
    @State private var showingPopover = false

    var body: some View {
        if let message = telescope.errorMessage {
            Button(action: { showingPopover = true }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help(message)
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280, alignment: .leading)
                    HStack {
                        Spacer()
                        Button("Dismiss") {
                            telescope.errorMessage = nil
                            showingPopover = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }
        }
    }
}
