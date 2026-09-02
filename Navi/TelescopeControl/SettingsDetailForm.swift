//
//  SettingsDetailForm.swift
//  Navi
//
//  Shared chrome for every Settings *detail* pane (an add/edit form), the counterpart to
//  SettingsPaneHeader's use in the sidebars. NAVI-85 follow-up.
//

import SwiftUI

/// Wraps an edit form's fields and action buttons in the standard detail-pane chrome: a
/// `SettingsPaneHeader` title bar, a divider, the scrolling field area, a divider, and a footer
/// holding the Cancel/Save buttons.
///
/// Exists because the forms had drifted into two camps — `ImagingTrainEditForm`/`RigEditForm` drew
/// a real header bar with a divider, while the other eight just put a bare `Text(...).font(.headline)`
/// at the top of a padded `VStack`. Editing a Camera therefore looked visibly different from editing
/// an Imaging Train, and different again from the Equipment pane's own type-overview header sitting
/// directly across the split from it. Routing all of them through one wrapper (which itself reuses
/// `SettingsPaneHeader`) makes that class of drift impossible rather than merely fixed once.
struct SettingsDetailForm<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    /// The trailing action buttons — typically Cancel + Save. Laid out right-aligned in the footer;
    /// the wrapper supplies the `Spacer`, padding and background.
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPaneHeader(title: title)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Spacer()
                actions()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
