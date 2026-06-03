//
//  PaneTypes.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation

// Direction for splitting a pane
enum SplitDirection {
    case horizontal // Left/Right split
    case vertical   // Up/Down split
}

// Types of panes
enum PaneType: Equatable {
    case aiAssistant
    case fitsViewer
    case archiveViewer
    case empty
}
