//
//  SplitPaneView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI

struct SplitPaneView: View {
    var pane: SplitPane
    var paneManager: PaneManager

    var body: some View {
        if let children = pane.children, let direction = pane.direction {
            if direction == .horizontal {
                HSplitView {
                    ForEach(children) { child in
                        SplitPaneView(pane: child, paneManager: paneManager)
                            .frame(idealWidth: child.preferredWidth)
                    }
                }
            } else {
                VSplitView {
                    ForEach(children) { child in
                        SplitPaneView(pane: child, paneManager: paneManager)
                            .frame(idealHeight: child.preferredHeight)
                    }
                }
            }
        } else {
            PaneContentView(pane: pane)
        }
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
