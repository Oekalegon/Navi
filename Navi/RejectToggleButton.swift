//
//  RejectToggleButton.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI

/// Bordered toggle button used in both the Archive viewer and FITS viewer toolbars.
/// Clear background + border when not rejected; grey fill + border when rejected.
struct RejectToggleButton: View {
    let isRejected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "xmark.diamond.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, isRejected ? Color.red : Color.primary)
                Text("Reject")
            }
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(isRejected ? Color.gray.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5))
        .disabled(isDisabled)
        .help(isRejected ? "Click to unreject" : "Reject frame")
    }
}
