//
//  RigSection.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-81.
//

import Foundation

/// One equipment-concern page within `RigEditForm`'s sidebar-driven navigation (NAVI-81) — the
/// Rig Settings pane's sidebar shows these as subitems under each rig, so editing e.g. the Imaging
/// Train doesn't mean scrolling past every other role.
///
/// `guideScope` deliberately bundles two of `RigProfile`'s relationships (`guideOpticalAssembly`
/// *and* `guideCamera`) onto one page — a guide scope and its camera are physically one subsystem
/// (§4.3). Every other case maps to exactly one `RigProfile` relationship or
/// `StandaloneComponentEntry` role.
///
/// `dewHeater` and `observatoryControl` each still map to a *single* `StandaloneComponentEntry`,
/// matching today's one-entry-per-role model — not because that's the desired end state, but
/// because neither change is implementable yet:
/// - Multiple dew heaters would need `RigProfileTranslator.makeRigComponents` to tolerate more than
///   one `Component` sharing a `Role`, which it explicitly rejects (`RigProfileTranslationError
///   .duplicateRole`, tracked upstream as INDIMCP-138). See NAVI-82/IMCPKIT-69.
/// - Moving `observatoryControl` (roof/dome) onto `Observatory` instead of `RigProfile` needs
///   INDIMCPKit's `Observatory` to gain a device-binding concept it doesn't have today. See
///   NAVI-83/IMCPKIT-70.
///
/// `CaseIterable`'s declaration order is the sidebar's display order.
enum RigSection: String, CaseIterable, Identifiable, Hashable {
    case opticalAssembly
    case mount
    case imagingTrain
    case guideScope
    case powerHub
    case flatScreen
    case dewHeater
    case observatoryControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opticalAssembly: return "OTA / Focuser"
        case .mount: return "Mount"
        case .imagingTrain: return "Imaging Train"
        case .guideScope: return "Guide Scope"
        case .powerHub: return "Power Hub"
        case .flatScreen: return "Flat Screen"
        case .dewHeater: return "Dew Heater"
        case .observatoryControl: return "Observatory Control"
        }
    }

    // Kept in sync with ObservatoryDashboardView's private `roleIcons` by convention, not shared
    // code — that dictionary is keyed by INDIMCPKit's `Role` (a live Component's role once saved),
    // this is keyed by a purely local UI-navigation concept.
    var icon: String {
        switch self {
        case .opticalAssembly: return "circle.dotted"
        case .mount: return "gyroscope"
        case .imagingTrain: return "camera"
        case .guideScope: return "camera.viewfinder"
        case .powerHub: return "bolt"
        case .flatScreen: return "rectangle.on.rectangle"
        case .dewHeater: return "flame"
        case .observatoryControl: return "building.columns"
        }
    }
}
