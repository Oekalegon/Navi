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
    /// `nil` on a *detail* header (an edit form's title bar), where there's nothing to add — the
    /// "+" is simply omitted. Sharing one component between sidebar and detail headers rather than
    /// hand-rolling the latter is what keeps their height and padding identical; they sit directly
    /// across a divider from each other, so any drift between them is immediately visible.
    var addHelp: String? = nil
    var onAdd: (() -> Void)? = nil
    @ViewBuilder var trailingContent: () -> TrailingContent

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            trailingContent()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .disabled(isAddDisabled)
                .help(addHelp ?? "Add")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension SettingsPaneHeader where TrailingContent == EmptyView {
    /// Sidebar header — title plus a trailing "+".
    init(title: String, isAddDisabled: Bool = false, addHelp: String, onAdd: @escaping () -> Void) {
        self.init(title: title, isAddDisabled: isAddDisabled, addHelp: addHelp, onAdd: onAdd) {
            EmptyView()
        }
    }

    /// Detail header — title only, for an edit form's title bar.
    init(title: String) {
        self.init(title: title, isAddDisabled: false, addHelp: nil, onAdd: nil) {
            EmptyView()
        }
    }
}
