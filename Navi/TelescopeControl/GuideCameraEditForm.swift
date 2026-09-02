//
//  GuideCameraEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3.
//

import SwiftUI

/// Editor for one `GuideCameraProfile` (§4.3) — the guiding camera, which attaches either to a
/// guide scope or as an off-axis guider (see `RigProfile`'s doc comment). A thin configuration of
/// `CameraLikeEditForm`, shared with `CameraEditForm`.
struct GuideCameraEditForm: View {
    let guideCamera: GuideCameraProfile

    var body: some View {
        CameraLikeEditForm(
            subject: guideCamera,
            namePlaceholder: "ASI120MM Mini",
            makePlaceholder: "ZWO"
        )
    }
}
