//
//  SettingsTabNavigation.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

import SwiftUI

/// Lets a view nested arbitrarily deep inside `SettingsRootView`'s `TabView` (e.g. `RigEditForm`,
/// pointing the user at an empty equipment library) switch to a different Settings tab, without
/// that view needing its own reference to `SettingsRootView`'s state. Injected once by
/// `SettingsRootView` itself; defaults to a no-op so any other context (previews, tests) using a
/// view that reads this key doesn't crash for lacking one.
private struct SelectSettingsTabKey: EnvironmentKey {
    static let defaultValue: (SettingsRootView.Tab) -> Void = { _ in }
}

extension EnvironmentValues {
    var selectSettingsTab: (SettingsRootView.Tab) -> Void {
        get { self[SelectSettingsTabKey.self] }
        set { self[SelectSettingsTabKey.self] = newValue }
    }
}
