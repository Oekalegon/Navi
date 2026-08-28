//
//  SettingsPaneHeader.swift
//  Navi
//
//  Shared header chrome (title + optional trailing content + "+" add button) for the
//  Server/Observatory/Rig settings panes — factored out once all three became sibling tabs in
//  SettingsRootView (NAVI-56) and their header markup turned out to be near-identical.
//

import SwiftUI

struct SettingsPaneHeader<TrailingContent: View>: View {
    let title: String
    var isAddDisabled: Bool = false
    let addHelp: String
    let onAdd: () -> Void
    @ViewBuilder var trailingContent: () -> TrailingContent

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            trailingContent()
            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .disabled(isAddDisabled)
            .help(addHelp)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension SettingsPaneHeader where TrailingContent == EmptyView {
    init(title: String, isAddDisabled: Bool = false, addHelp: String, onAdd: @escaping () -> Void) {
        self.init(title: title, isAddDisabled: isAddDisabled, addHelp: addHelp, onAdd: onAdd) {
            EmptyView()
        }
    }
}
