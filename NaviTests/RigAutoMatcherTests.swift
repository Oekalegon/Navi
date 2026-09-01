//
//  RigAutoMatcherTests.swift
//  NaviTests
//

import Testing
@testable import Navi

// NAVI-67: RigAutoMatcher.bestMatch is the pure scoring logic behind "connect to a bare server,
// then auto-detect which local Rig matches the live devices" -- covered directly here since it
// needs neither a live TelescopeSessionManager nor a ModelContext, only plain RigProfile values
// (SwiftData @Model types work fine unattached to a context, matching RigProfileTranslatorTests'
// existing convention).
struct RigAutoMatcherTests {

    @Test func returnsNilWhenNoCandidateSharesAnyDevice() throws {
        let rig = RigProfile(serverRigID: "rig-1", name: "Rig 1", mount: MountProfile(name: "Mount", deviceName: "EQ6-R"))
        let match = RigAutoMatcher.bestMatch(liveNames: ["CCD Simulator"], candidates: [rig])
        #expect(match == nil)
    }

    @Test func returnsNilForNoCandidates() {
        let match = RigAutoMatcher.bestMatch(liveNames: ["EQ6-R"], candidates: [])
        #expect(match == nil)
    }

    @Test func matchesTheOnlyCandidateSharingADevice() throws {
        let rig = RigProfile(serverRigID: "rig-1", name: "Rig 1", mount: MountProfile(name: "Mount", deviceName: "EQ6-R"))
        let match = RigAutoMatcher.bestMatch(liveNames: ["EQ6-R", "CCD Simulator"], candidates: [rig])
        #expect(match === rig)
    }

    @Test func picksTheCandidateWithTheHigherOverlapScore() throws {
        // Rig 1 only shares the mount; Rig 2 shares both mount and camera -- Rig 2 should win
        // even though both share at least one device.
        let rig1 = RigProfile(
            serverRigID: "rig-1", name: "Rig 1",
            mount: MountProfile(name: "Mount", deviceName: "EQ6-R")
        )
        let rig2 = RigProfile(
            serverRigID: "rig-2", name: "Rig 2",
            mount: MountProfile(name: "Mount", deviceName: "EQ6-R"),
            imagingTrain: ImagingTrainProfile(
                name: "Train",
                camera: CameraProfile(name: "ASI2600MM", deviceName: "ASI2600MM")
            )
        )
        let match = RigAutoMatcher.bestMatch(
            liveNames: ["EQ6-R", "ASI2600MM"],
            candidates: [rig1, rig2]
        )
        #expect(match === rig2)
    }

    @Test func aRigWithNoDeviceBoundNeverMatches() throws {
        // A "blank" pick (role present, device nil) contributes nothing to the live-device set,
        // matching mountMapsToMountRoleEvenWithNoDeviceBound's expectations for makeComponents().
        let rig = RigProfile(serverRigID: "rig-1", name: "Rig 1", mount: MountProfile(name: "Mount"))
        let match = RigAutoMatcher.bestMatch(liveNames: ["EQ6-R"], candidates: [rig])
        #expect(match == nil)
    }
}
