//
//  EquipmentDisplayNameTests.swift
//  NaviTests
//

import Testing
@testable import Navi

/// `equipmentDisplayName` decides what every equipment list row and detail-pane title says, and a
/// name is no longer required (NAVI-85 follow-up) — so the make/model fallback is the *normal*
/// path for a lot of records, not an edge case.
struct EquipmentDisplayNameTests {

    // MARK: - Name wins when present

    @Test func anExplicitNameIsUsedVerbatim() {
        #expect(
            equipmentDisplayName(name: "Backyard Scope", make: "ZWO", model: "ASI2600MM Pro", fallback: "Untitled Camera")
                == "Backyard Scope"
        )
    }

    @Test func aNameIsTrimmedBeforeUse() {
        #expect(
            equipmentDisplayName(name: "  Backyard Scope  ", make: nil, model: nil, fallback: "Untitled Camera")
                == "Backyard Scope"
        )
    }

    @Test func aWhitespaceOnlyNameFallsThroughToMakeAndModel() {
        // The reason the name is trimmed before the emptiness check: a field the user cleared to
        // spaces must behave as unnamed, not render as blank.
        #expect(
            equipmentDisplayName(name: "   ", make: "ZWO", model: "ASI2600MM Pro", fallback: "Untitled Camera")
                == "ZWO ASI2600MM Pro"
        )
    }

    // MARK: - Make/model fallback

    @Test func makeAndModelCombineInReadingOrder() {
        #expect(
            equipmentDisplayName(name: "", make: "ZWO", model: "ASI2600MM Pro", fallback: "Untitled Camera")
                == "ZWO ASI2600MM Pro"
        )
    }

    @Test func eitherHalfAloneIsEnough() {
        #expect(equipmentDisplayName(name: "", make: "ZWO", model: nil, fallback: "Untitled Camera") == "ZWO")
        #expect(equipmentDisplayName(name: "", make: nil, model: "ASI2600MM Pro", fallback: "Untitled Camera") == "ASI2600MM Pro")
    }

    @Test func blankMakeOrModelIsSkippedRatherThanLeavingAStraySpace() {
        // `nilAsEmpty` writes nil for cleared fields, but a record could still hold "" — joining
        // naively would render "ZWO " or " ASI2600MM Pro".
        #expect(equipmentDisplayName(name: "", make: "ZWO", model: "", fallback: "Untitled Camera") == "ZWO")
        #expect(equipmentDisplayName(name: "", make: "  ", model: "ASI2600MM Pro", fallback: "Untitled Camera") == "ASI2600MM Pro")
    }

    @Test func makeAndModelAreTrimmedIndividually() {
        #expect(
            equipmentDisplayName(name: "", make: " ZWO ", model: " ASI2600MM Pro ", fallback: "Untitled Camera")
                == "ZWO ASI2600MM Pro"
        )
    }

    // MARK: - Placeholder

    @Test func anEmptyRecordUsesItsTypeSpecificPlaceholder() {
        // What a record inserted by "+" reads as before the user types anything.
        #expect(equipmentDisplayName(name: "", make: nil, model: nil, fallback: "Untitled Camera") == "Untitled Camera")
        #expect(equipmentDisplayName(name: "", make: "", model: "", fallback: "Untitled Rotator") == "Untitled Rotator")
    }

    // MARK: - Through the model types

    @Test func eachEquipmentTypeCarriesItsOwnPlaceholder() {
        #expect(CameraProfile(name: "").displayName == "Untitled Camera")
        #expect(GuideCameraProfile(name: "").displayName == "Untitled Guide Camera")
        #expect(MountProfile(name: "").displayName == "Untitled Mount")
        #expect(FilterWheelProfile(name: "").displayName == "Untitled Filter Wheel")
        #expect(RotatorProfile(name: "").displayName == "Untitled Rotator")
        #expect(ImagingTrainProfile(name: "").displayName == "Untitled Imaging Train")
    }

    @Test func opticalAssemblyPlaceholderDistinguishesItsPurpose() {
        // The Equipment pane lists main and guide assemblies as separate kinds, so an unnamed one
        // has to say which it is.
        #expect(OpticalAssemblyProfile(name: "", purpose: .mainImaging).displayName == "Untitled Optical Assembly")
        #expect(OpticalAssemblyProfile(name: "", purpose: .guideScope).displayName == "Untitled Guide Optical Assembly")
    }

    @Test func standaloneEquipmentPlaceholderNamesItsRole() {
        #expect(StandaloneEquipmentProfile(name: "", role: .powerHub).displayName == "Untitled Power Hub")
        #expect(StandaloneEquipmentProfile(name: "", role: .dewHeater).displayName == "Untitled Dew Heater")
    }

    @Test func aRealCameraFallsBackToItsMakeAndModel() {
        let camera = CameraProfile(name: "", make: "ZWO", model: "ASI2600MM Pro")
        #expect(camera.displayName == "ZWO ASI2600MM Pro")
    }
}
