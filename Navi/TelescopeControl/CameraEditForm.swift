//
//  CameraEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI

/// Editor for one `CameraProfile` (§4.3) — the main imaging camera. A thin configuration of
/// `CameraLikeEditForm`, which it shares with `GuideCameraEditForm`.
struct CameraEditForm: View {
    let camera: CameraProfile

    var body: some View {
        CameraLikeEditForm(
            subject: camera,
            namePlaceholder: "ASI2600MM Pro",
            makePlaceholder: "ZWO"
        )
    }
}
