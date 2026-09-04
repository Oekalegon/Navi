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
    @State private var resolveError: String?

    var body: some View {
        if let conflict = telescope.pendingConflict {
            Button(action: {
                resolveError = nil
                showingPopover = true
            }) {
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
                    if let resolveError {
                        Text(resolveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .frame(maxWidth: 320, alignment: .leading)
                .disabled(isResolving)
            }
        }
    }

    /// `action` is throwing, not swallowed — `pendingConflict` (and the popover) must only clear
    /// on an actual success. Clearing it unconditionally, the way this used to work, told the user
    /// their edit was resolved even when e.g. the connection dropped mid-resolve and nothing
    /// actually reached the server: the indicator would just silently disappear, leaving the real
    /// drift unresolved with no sign anything went wrong.
    private func resolve(_ action: @escaping () async throws -> Void) {
        isResolving = true
        resolveError = nil
        Task {
            do {
                try await action()
                telescope.pendingConflict = nil
                showingPopover = false
            } catch {
                resolveError = TelescopeSessionManager.describe(error)
            }
            isResolving = false
        }
    }
}
