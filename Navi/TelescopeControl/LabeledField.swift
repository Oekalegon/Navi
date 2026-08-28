//
//  LabeledField.swift
//  Navi
//

import SwiftUI

/// A caption-labeled form field: a small secondary-styled title above its content. Shared by every
/// equipment-library edit form (Rig/Mount/OpticalAssembly/ImagingTrain/GuideCamera/Observatory) —
/// previously an identical private `labeledField(_:content:)` helper copy-pasted into each one.
struct LabeledField<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
