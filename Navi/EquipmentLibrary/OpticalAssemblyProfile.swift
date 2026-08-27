//
//  OpticalAssemblyProfile.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation
import SwiftData

/// The optical design of an `OpticalAssemblyProfile`'s tube — manual input, not INDI-derived.
enum OpticalDesign: String, Codable, CaseIterable, Sendable {
    case refractor
    case newtonian
    case schmidtCassegrain
    case ritcheyChretien
    case maksutovCassegrain
    case other
}

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

/// A reusable optical-tube-assembly definition in Navi's local equipment library — a telescope
/// tube plus its focuser, combined as one unit (§4.3: a focuser is normally semi-permanently
/// mounted to one tube, so an actual focuser swap is rare enough to just edit this record when it
/// happens, rather than modeling the focuser as its own separately-reusable entity).
///
/// The focuser fields are all optional together: `nil` means this assembly has no focuser at all
/// (typical for a piggyback guide scope, per §4.3). `focuserDeviceName` is picker-only, resolved
/// only while connected — never free text.
@Model
final class OpticalAssemblyProfile {
    var name: String
    var make: String?
    var model: String?
    var apertureMm: Double?
    var focalLengthMm: Double?
    var opticalDesign: OpticalDesign?
    var purpose: OpticalAssemblyPurpose

    var focuserMake: String?
    var focuserModel: String?
    var focuserDeviceName: String?
    var focuserMinPosition: Int?
    var focuserMaxPosition: Int?

    var notes: String?

    /// Updated whenever this record is saved; drives the §4.3 "Resync all" stale-Rig detection.
    var modifiedAt: Date

    init(
        name: String,
        make: String? = nil,
        model: String? = nil,
        apertureMm: Double? = nil,
        focalLengthMm: Double? = nil,
        opticalDesign: OpticalDesign? = nil,
        purpose: OpticalAssemblyPurpose = .mainImaging,
        focuserMake: String? = nil,
        focuserModel: String? = nil,
        focuserDeviceName: String? = nil,
        focuserMinPosition: Int? = nil,
        focuserMaxPosition: Int? = nil,
        notes: String? = nil,
        modifiedAt: Date = .now
    ) {
        self.name = name
        self.make = make
        self.model = model
        self.apertureMm = apertureMm
        self.focalLengthMm = focalLengthMm
        self.opticalDesign = opticalDesign
        self.purpose = purpose
        self.focuserMake = focuserMake
        self.focuserModel = focuserModel
        self.focuserDeviceName = focuserDeviceName
        self.focuserMinPosition = focuserMinPosition
        self.focuserMaxPosition = focuserMaxPosition
        self.notes = notes
        self.modifiedAt = modifiedAt
    }

    /// Whether this assembly has a focuser attached at all.
    var hasFocuser: Bool { focuserDeviceName != nil || focuserMake != nil || focuserModel != nil }
}
