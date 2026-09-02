//
//  CameraEditForm.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.2/§4.3. NAVI-85 follow-up.
//

import SwiftUI

/// Add/edit form for one `CameraProfile` (§4.3) — the main imaging camera. A thin configuration of
/// `CameraLikeEditForm`, which it shares with `GuideCameraEditForm`; the two differ only in the
/// entity they edit and their placeholder text.
struct CameraEditForm: View {
    let camera: CameraProfile?
    var onSaved: (CameraProfile) -> Void = { _ in }
    var onFinished: () -> Void = {}

    var body: some View {
        CameraLikeEditForm(
            subject: camera,
            noun: "Camera",
            namePlaceholder: "ASI2600MM Pro",
            makePlaceholder: "ZWO",
            makeNew: { CameraProfile(name: "") },
            onSaved: onSaved,
            onFinished: onFinished
        )
    }
}
