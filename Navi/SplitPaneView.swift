//
//  SplitPaneView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import AppKit

struct SplitPaneView: View {
    var pane: SplitPane
    var paneManager: PaneManager

    var body: some View {
        if let children = pane.children, let direction = pane.direction {
            if direction == .horizontal {
                HSplitView {
                    ForEach(children) { child in
                        StableSplitPaneHost(pane: child, paneManager: paneManager)
                            .frame(idealWidth: child.preferredWidth, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VSplitView {
                    ForEach(children) { child in
                        StableSplitPaneHost(pane: child, paneManager: paneManager)
                            .frame(maxWidth: .infinity, idealHeight: child.preferredHeight, maxHeight: .infinity)
                    }
                }
            }
        } else {
            PaneContentView(pane: pane)
        }
    }
}

// Wraps SplitPaneView in a stable NSHostingView so the parent NSSplitView
// never sees a subview add/remove when pane content changes type
// (e.g. PaneContentView → VSplitView). NSSplitView only re-runs adjustSubviews
// on structural subview changes, so the user-set divider position is preserved.
struct StableSplitPaneHost: NSViewRepresentable {
    let pane: SplitPane
    let paneManager: PaneManager

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        let view = NSHostingView(rootView: content)
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSHostingView<AnyView>, context: Context) {
        nsView.rootView = content
    }

    private var content: AnyView {
        AnyView(
            SplitPaneView(pane: pane, paneManager: paneManager)
                .environment(paneManager)
        )
    }
}

struct PaneContentView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager

    var body: some View {
        Group {
            switch pane.paneType {
            case .aiAssistant:
                AIAssistantView(pane: pane)
            case .fitsViewer:
                FITSViewerView(pane: pane)
            case .archiveViewer:
                ArchiveViewerView(pane: pane)
            case .empty:
                Color.clear
            }
        }
        .frame(minWidth: 100, minHeight: 100)
    }
}
