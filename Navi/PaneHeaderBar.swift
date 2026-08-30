//
//  PaneHeaderBar.swift
//  Navi
//
//  The close+move+divider+…+spacer+…+padding/background shell every pane header already shared
//  verbatim (FITSViewerView, ArchiveViewerView, InfoPanelView, ObservatoryDashboardView) —
//  extracted once a 4th near-identical copy appeared. `titleContent`/`trailing` stay fully
//  arbitrary ViewBuilders so each pane keeps its own icon/title/action logic unchanged; only the
//  mechanical wrapper is shared.
//

import SwiftUI

struct PaneHeaderBar<TitleContent: View, Trailing: View>: View {
    let paneType: PaneType
    let pane: SplitPane
    @ViewBuilder var titleContent: () -> TitleContent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            PaneCloseButton(paneType: paneType)
            PaneMoveButton(pane: pane)

            Divider()
                .frame(height: 14)

            titleContent()

            Spacer()

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

extension PaneHeaderBar where Trailing == EmptyView {
    init(paneType: PaneType, pane: SplitPane, @ViewBuilder titleContent: @escaping () -> TitleContent) {
        self.init(paneType: paneType, pane: pane, titleContent: titleContent) { EmptyView() }
    }
}
