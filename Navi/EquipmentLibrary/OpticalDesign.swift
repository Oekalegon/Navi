//
//  OpticalDesign.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

/// The optical design of an `OpticalAssemblyProfile`'s tube — manual input, not INDI-derived.
enum OpticalDesign: String, Codable, CaseIterable, Sendable {
    case refractor
    case newtonian
    case schmidtCassegrain
    case ritcheyChretien
    case maksutovCassegrain
    case other
}
