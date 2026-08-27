//
//  OpticalAssemblyPurpose.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

/// Which role an `OpticalAssemblyProfile` plays when composed into a `RigProfile`.
///
/// Distinguishes "the main imaging tube" from "a piggyback guide scope" — a
/// `GuideCameraProfile` pairs with a `.guideScope`-purposed assembly (§4.3); the main imaging
/// assembly is always `.mainImaging`. Both are ordinary, independently-reusable
/// `OpticalAssemblyProfile` records — this is just a label on how one is being used.
enum OpticalAssemblyPurpose: String, Codable, CaseIterable, Sendable {
    case mainImaging
    case guideScope
}
