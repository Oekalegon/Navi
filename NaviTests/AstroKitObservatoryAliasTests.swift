//
//  AstroKitObservatoryAliasTests.swift
//  NaviTests
//

import Testing
import AstroKit
import INDIMCPKit
@testable import Navi

// NAVI-50: AstroObservatory.init(indi:) converts INDIMCPKit's degrees/"elevationMeters" shape
// into AstroKit's radians/"height" shape — exactly the unit-and-field-name mismatch
// docs/design/INDI-MCP-Integration.md §4.6 calls out as easy to get wrong silently.
struct AstroKitObservatoryAliasTests {

    @Test func convertsDegreesToRadians() {
        let indi = INDIObservatory(
            id: "obs-1", name: "Home Backyard",
            latitudeDeg: 52.0, longitudeDeg: 4.5, elevationMeters: 12.0,
            horizonProfile: nil
        )
        let astro = AstroObservatory(indi: indi)

        #expect(abs(astro.latitude - 52.0 * .pi / 180) < 1e-12)
        #expect(abs(astro.longitude - 4.5 * .pi / 180) < 1e-12)
    }

    @Test func mapsElevationMetersToHeight() {
        let indi = INDIObservatory(
            id: "obs-2", name: "Mountain Site",
            latitudeDeg: -30.0, longitudeDeg: -70.0, elevationMeters: 2400.0,
            horizonProfile: nil
        )
        let astro = AstroObservatory(indi: indi)

        #expect(astro.height == 2400.0)
    }

    @Test func preservesNegativeLatitudeAndLongitudeSign() {
        let indi = INDIObservatory(
            id: "obs-3", name: "Southern Hemisphere Site",
            latitudeDeg: -33.86, longitudeDeg: -70.66, elevationMeters: 0.0,
            horizonProfile: nil
        )
        let astro = AstroObservatory(indi: indi)

        #expect(astro.latitude < 0)
        #expect(astro.longitude < 0)
    }
}
