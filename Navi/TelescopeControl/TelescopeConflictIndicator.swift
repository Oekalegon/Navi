//
//  TelescopeConflictIndicator.swift
//  Navi
//
//  NAVI-86. Same convention as `TelescopeErrorIndicator` (I-4): a persistent, click-to-reveal
//  toolbar indicator, not an auto-appearing alert — placed next to it since both are things the
//  user needs to notice regardless of which panes are open, and a conflict can be raised by
//  PendingPushSync running unattended after a reconnect, with no editor open at all.
//

import SwiftUI

struct TelescopeConflictIndicator: View {
    @State private var telescope = TelescopeSessionManager.shared
    @State private var showingPopover = false
    @State private var isResolving = false

    var body: some View {
        if let conflict = telescope.pendingConflict {
            Button(action: { showingPopover = true }) {
                // See `TelescopeErrorIndicator`/`SettingsPaneHeader`'s "+"/"−" for why.
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .help("\(conflict.recordName) changed on the server — click to resolve")
            .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(conflict.recordName) changed on the server since Navi last pushed it.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your local edit was kept but not sent, so nothing has been overwritten yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            resolve(conflict.pushMine)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Push My Version")
                                Text("Overwrites the server's change with Navi's.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            resolve(conflict.acceptServer)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep the Server's Version")
                                Text(conflict.acceptServerDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if isResolving {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Working…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 320, alignment: .leading)
                .disabled(isResolving)
            }
        }
    }

    private func resolve(_ action: @escaping () async -> Void) {
        isResolving = true
        Task {
            await action()
            telescope.pendingConflict = nil
            isResolving = false
            showingPopover = false
        }
    }
}
