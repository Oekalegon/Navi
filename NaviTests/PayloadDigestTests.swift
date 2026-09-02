//
//  PayloadDigestTests.swift
//  NaviTests
//

import Testing
import Foundation
@testable import Navi
import INDIMCPKit

/// `PayloadDigest` is load-bearing twice over: it decides whether a record needs pushing at all,
/// and it's the basis of NAVI-86's drift check. A digest that were unstable between encodes would
/// mean pushing on every flush and reporting drift constantly; one that missed a field would mean
/// silently skipping a real edit, or clobbering someone else's.
struct PayloadDigestTests {

    private func observatory(
        id: String = "home",
        name: String = "Home Backyard",
        lat: Double = 52.1,
        lon: Double = 4.3,
        elevation: Double = 12,
        horizon: [HorizonPoint]? = nil
    ) -> Observatory {
        Observatory(
            id: id, name: name, latitudeDeg: lat, longitudeDeg: lon,
            elevationMeters: elevation, horizonProfile: horizon
        )
    }

    // MARK: - Stability

    @Test func theSameValueDigestsIdenticallyAcrossCalls() {
        // Without .sortedKeys, JSON key order isn't guaranteed between encodes — which would make
        // every comparison report a spurious difference.
        let first = PayloadDigest.of(observatory())
        let second = PayloadDigest.of(observatory())
        #expect(first != nil)
        #expect(first == second)
    }

    @Test func twoSeparatelyBuiltEqualValuesAgree() {
        #expect(PayloadDigest.of(observatory()) == PayloadDigest.of(observatory()))
    }

    // MARK: - Sensitivity

    @Test func everyEditedFieldChangesTheDigest() {
        let baseline = PayloadDigest.of(observatory())
        #expect(PayloadDigest.of(observatory(name: "Renamed")) != baseline)
        #expect(PayloadDigest.of(observatory(lat: 52.2)) != baseline)
        #expect(PayloadDigest.of(observatory(lon: 4.4)) != baseline)
        #expect(PayloadDigest.of(observatory(elevation: 13)) != baseline)
        #expect(PayloadDigest.of(observatory(id: "other")) != baseline)
    }

    @Test func aFieldNaviDoesNotEditStillChangesTheDigest() {
        // horizonProfile has no editor in Navi, but it round-trips through save — and a change to
        // it made elsewhere is exactly the drift worth reporting, so it must not be excluded.
        let withHorizon = observatory(horizon: [HorizonPoint(azimuthDeg: 0, altitudeDeg: 10)])
        #expect(PayloadDigest.of(withHorizon) != PayloadDigest.of(observatory()))
    }

    @Test func aSmallNumericChangeIsNotRoundedAway() {
        #expect(PayloadDigest.of(observatory(lat: 52.1000001)) != PayloadDigest.of(observatory(lat: 52.1)))
    }

    // MARK: - Rigs

    @Test func rigDigestTracksItsComponents() {
        let mount = Component(role: .mount, id: "mount", device: "EQMod Mount")
        let camera = Component(role: .camera, id: "camera", device: "ZWO CCD")

        let baseline = PayloadDigest.of(Rig(id: "rig", name: "Rig", components: [mount]))
        #expect(baseline != nil)
        // Adding a component is an edit.
        #expect(PayloadDigest.of(Rig(id: "rig", name: "Rig", components: [mount, camera])) != baseline)
        // So is renaming the rig.
        #expect(PayloadDigest.of(Rig(id: "rig", name: "Renamed", components: [mount])) != baseline)
        // And so is rebinding a component's device.
        let rebound = Component(role: .mount, id: "mount", device: "Other Mount")
        #expect(PayloadDigest.of(Rig(id: "rig", name: "Rig", components: [rebound])) != baseline)
    }

    @Test func anUnchangedRigDigestsIdentically() {
        let components = [Component(role: .mount, id: "mount", device: "EQMod Mount")]
        #expect(
            PayloadDigest.of(Rig(id: "rig", name: "Rig", components: components))
                == PayloadDigest.of(Rig(id: "rig", name: "Rig", components: components))
        )
    }
}
