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

// Types of panes. Codable/Hashable so a WindowToken can carry the root pane
// type through macOS window restoration (NAVI-10).
enum PaneType: String, Codable, Hashable {
    case aiAssistant
    case fitsViewer
    case archiveViewer
    case infoPanel
    case empty

    var displayName: String {
        switch self {
        case .aiAssistant: "AI Assistant"
        case .fitsViewer: "FITS Viewer"
        case .archiveViewer: "Archive"
        case .infoPanel: "Info"
        case .empty: "Empty Pane"
        }
    }
}
