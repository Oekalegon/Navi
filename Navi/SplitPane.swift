//
//  SplitPane.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import Observation

@Observable
class SplitPane: Identifiable {
    let id = UUID()
    var children: [SplitPane]?
    var direction: SplitDirection?
    var paneType: PaneType
    var preferredWidth: CGFloat?

    init(type: PaneType = .aiAssistant) {
        self.paneType = type
    }

    var isLeaf: Bool { children == nil }
}
