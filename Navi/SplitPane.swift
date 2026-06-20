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
    let id: UUID
    var children: [SplitPane]?
    var direction: SplitDirection?
    var paneType: PaneType
    var preferredWidth: CGFloat?
    var preferredHeight: CGFloat?

    init(id: UUID = UUID(), type: PaneType = .aiAssistant) {
        self.id = id
        self.paneType = type
    }

    var isLeaf: Bool { children == nil }
}

// Codable snapshot of the pane tree — used to persist layout across launches.
// UUIDs are preserved so NSSplitView autosave names survive restart.
struct PaneTreeSnapshot: Codable {
    var id: UUID
    var paneType: PaneType
    var direction: SplitDirection?
    var preferredWidth: CGFloat?
    var preferredHeight: CGFloat?
    var children: [PaneTreeSnapshot]?
}

extension SplitPane {
    func snapshot() -> PaneTreeSnapshot {
        PaneTreeSnapshot(id: id, paneType: paneType, direction: direction,
                         preferredWidth: preferredWidth, preferredHeight: preferredHeight,
                         children: children?.map { $0.snapshot() })
    }

    convenience init(snapshot s: PaneTreeSnapshot) {
        self.init(id: s.id, type: s.paneType)
        self.direction = s.direction
        self.preferredWidth = s.preferredWidth
        self.preferredHeight = s.preferredHeight
        self.children = s.children?.map { SplitPane(snapshot: $0) }
    }
}
