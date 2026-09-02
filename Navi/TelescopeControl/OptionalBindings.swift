//
//  OptionalBindings.swift
//  Navi
//
//  NAVI-85 follow-up — support for editing SwiftData models directly, without local @State mirrors.
//

import SwiftUI

/// Bridges a model's optional field to a control that needs a non-optional binding.
///
/// Settings edit forms bind straight to their `@Model` record (macOS treats any edit as committed,
/// so there's no Save button and therefore no local `@State` copy to write through). Most equipment
/// fields are optional — `make`, `model`, `notes` are `String?`, `cooled` is `Bool?` — while
/// `TextField`/`Toggle` want `String`/`Bool`, hence these.
extension Binding where Value == String {
    /// Empty string reads as `nil` on the way back in, so clearing a field genuinely clears it
    /// rather than storing `""` — matching what every form's old `trimmed.isEmpty ? nil : trimmed`
    /// save path did explicitly.
    init(nilAsEmpty source: Binding<String?>) {
        self.init(
            get: { source.wrappedValue ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                source.wrappedValue = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}

extension Binding where Value == Bool {
    init(nilAsFalse source: Binding<Bool?>) {
        self.init(
            get: { source.wrappedValue ?? false },
            set: { source.wrappedValue = $0 }
        )
    }
}
