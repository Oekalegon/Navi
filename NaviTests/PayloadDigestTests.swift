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

    private func fieldsDigest(_ o: Observatory) -> String? {
        PayloadDigest.ofObservatoryFields(
            id: o.id, name: o.name, latitudeDeg: o.latitudeDeg,
            longitudeDeg: o.longitudeDeg, elevationMeters: o.elevationMeters
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

    @Test func everyNaviEditedFieldChangesTheOwnedSubsetDigest() {
        // The subset digest is what actually gates pushing, so each editable field must move it.
        let baseline = fieldsDigest(observatory())
        #expect(baseline != nil)
        #expect(fieldsDigest(observatory(name: "Renamed")) != baseline)
        #expect(fieldsDigest(observatory(lat: 52.2)) != baseline)
        #expect(fieldsDigest(observatory(lon: 4.4)) != baseline)
        #expect(fieldsDigest(observatory(elevation: 13)) != baseline)
        #expect(fieldsDigest(observatory(id: "other")) != baseline)
        // And an unchanged record must not, or every reconnect would re-push everything.
        #expect(fieldsDigest(observatory()) == baseline)
    }

    @Test func observatoryFieldsDigestIgnoresHorizonProfile() {
        // Deliberately excluded, for two reasons (see PayloadDigest's doc comment): Navi has no
        // editor for it and preserves whatever the server holds, so a change there survives a push
        // anyway and would only produce a conflict Navi could resolve itself — and "does this need
        // pushing" has to be answerable offline, where the local record has no horizonProfile to
        // digest at all.
        let plain = observatory()
        let withHorizon = observatory(horizon: [HorizonPoint(azimuthDeg: 0, altitudeDeg: 10)])
        #expect(fieldsDigest(plain) == fieldsDigest(withHorizon))
        // The whole-payload digest still distinguishes them — it's only the owned-subset one that
        // deliberately doesn't.
        #expect(PayloadDigest.of(plain) != PayloadDigest.of(withHorizon))
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
