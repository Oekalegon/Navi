//
//  StandaloneEquipmentRole.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3. NAVI-85.
//

/// Which of the four device-bearing roles with no reusable-entity concept before NAVI-85 a
/// `StandaloneEquipmentProfile` represents.
///
/// A closed, fixed set of exactly four kinds internal to Navi's own UI — unlike the old
/// `StandaloneComponentEntry.role` (a raw `String`, deliberately open-ended to avoid a dependency
/// on INDIMCPKit's own open-ended `Role`), a typed enum here costs nothing and gives exhaustive
/// `switch`es for free wherever it's used (mirrors `OpticalAssemblyPurpose`'s pattern).
enum StandaloneEquipmentRole: String, Codable, CaseIterable, Sendable {
    case powerHub
    case flatScreen
    case dewHeater
    case observatoryControl

    var title: String {
        switch self {
        case .powerHub: return "Power Hub"
        case .flatScreen: return "Flat Screen"
        case .dewHeater: return "Dew Heater"
        case .observatoryControl: return "Observatory Control"
        }
    }
}
