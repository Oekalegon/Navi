//
//  RigProfileTranslatorTests.swift
//  NaviTests
//

import Testing
import Foundation
@testable import Navi
import INDIMCPKit

struct RigProfileTranslatorTests {

    @Test func emptyRigProducesNoComponents() throws {
        let rig = RigProfile(serverRigID: "rig-empty", name: "Empty Rig")
        #expect(try rig.makeComponents().isEmpty)
    }

    @Test func mountMapsToMountRoleEvenWithNoDeviceBound() throws {
        // A selected-but-blank role (§4.2) must still produce a Component — with device == nil —
        // rather than being silently omitted, since "blank" and "role not present at all" are
        // deliberately distinct states.
        let mount = MountProfile(name: "My EQ6-R")
        let rig = RigProfile(serverRigID: "rig-mount", name: "Mount Rig", mount: mount)

        let components = try rig.makeComponents()
        #expect(components.count == 1)
        let mountComponent = try #require(components.first)
        #expect(mountComponent.role == .mount)
        #expect(mountComponent.id == "mount")
        #expect(mountComponent.device == nil)
    }

    @Test func opticalAssemblyWithoutFocuserProducesOnlyTheTelescopeComponent() throws {
        let ota = OpticalAssemblyProfile(name: "Esprit 100", apertureMm: 100, focalLengthMm: 550, purpose: .mainImaging)
        let rig = RigProfile(serverRigID: "rig-ota", name: "OTA Rig", opticalAssembly: ota)

        let components = try rig.makeComponents()
        #expect(components.count == 1)
        #expect(components.first?.role == .telescope)
        #expect(components.first?.apertureMm == 100)
        #expect(components.first?.focalLengthMm == 550)
    }

    @Test func opticalAssemblyWithFocuserProducesBothComponents() throws {
        let ota = OpticalAssemblyProfile(
            name: "Esprit 100",
            purpose: .mainImaging,
            focuserDeviceName: "ZWO EAF",
            focuserMinPosition: 0,
            focuserMaxPosition: 100_000
        )
        let rig = RigProfile(serverRigID: "rig-ota-focuser", name: "OTA + Focuser Rig", opticalAssembly: ota)

        let components = try rig.makeComponents()
        #expect(components.count == 2)
        #expect(components.contains { $0.role == .telescope && $0.id == "telescope" })
        let focuser = try #require(components.first { $0.role == .focuser })
        #expect(focuser.id == "focuser")
        #expect(focuser.device == "ZWO EAF")
        #expect(focuser.minPosition == 0)
        #expect(focuser.maxPosition == 100_000)
    }

    @Test func guideOpticalAssemblyMapsToGuideTelescopeAndGuideFocuserRoles() throws {
        let guideOTA = OpticalAssemblyProfile(name: "50mm Guide Scope", purpose: .guideScope, focuserDeviceName: "Guide Focuser")
        let rig = RigProfile(serverRigID: "rig-guide-ota", name: "Guide OTA Rig", guideOpticalAssembly: guideOTA)

        let components = try rig.makeComponents()
        #expect(components.contains { $0.role == .guideTelescope && $0.id == "guideTelescope" })
        let focuser = try #require(components.first { $0.role == .focuser })
        #expect(focuser.id == "guideFocuser")
    }

    @Test func imagingTrainMapsCameraFilterWheelAndRotatorRolesOnlyWhenPresent() throws {
        let cameraProfile = CameraProfile(name: "ASI2600MM Pro", deviceName: "ZWO CCD ASI2600MM Pro", cooled: true)
        let filterWheelProfile = FilterWheelProfile(
            name: "EFW",
            deviceName: "ZWO EFW",
            slots: [
                FilterSlotEntry(slot: 1, name: "Luminance"),
                FilterSlotEntry(slot: 2, name: "Red"),
            ]
        )
        let train = ImagingTrainProfile(name: "ASI2600MM Train", camera: cameraProfile, filterWheel: filterWheelProfile)
        let rig = RigProfile(serverRigID: "rig-train", name: "Train Rig", imagingTrain: train)

        let components = try rig.makeComponents()
        // Camera + filter wheel only — no rotator configured on this train.
        #expect(components.count == 2)
        let camera = try #require(components.first { $0.role == .camera })
        #expect(camera.id == "camera")
        #expect(camera.device == "ZWO CCD ASI2600MM Pro")
        #expect(camera.cooled == true)
        let filterWheel = try #require(components.first { $0.role == .filterWheel })
        #expect(filterWheel.id == "filterWheel")
        #expect(filterWheel.slots?[1] == "Luminance")
        #expect(filterWheel.slots?[2] == "Red")
        #expect(components.contains { $0.role == .rotator } == false)
    }

    @Test func guideCameraMapsToGuideCameraRole() throws {
        let guideCamera = GuideCameraProfile(name: "ASI120MM Mini", deviceName: "ZWO CCD ASI120MM Mini")
        let rig = RigProfile(serverRigID: "rig-guide-cam", name: "Guide Camera Rig", guideCamera: guideCamera)

        let components = try rig.makeComponents()
        #expect(components.count == 1)
        #expect(components.first?.role == .guideCamera)
        #expect(components.first?.device == "ZWO CCD ASI120MM Mini")
    }

    @Test func standaloneEquipmentMapsToFixedRoles() throws {
        let rig = RigProfile(
            serverRigID: "rig-standalone",
            name: "Standalone Rig",
            powerHub: StandaloneEquipmentProfile(name: "Pegasus PPBA", role: .powerHub, deviceName: "Pegasus PPBA"),
            dewHeater: StandaloneEquipmentProfile(name: "Dew Heater 1", role: .dewHeater)
        )

        let components = try rig.makeComponents()
        #expect(components.count == 2)
        let power = try #require(components.first { $0.id == "powerHub" })
        #expect(power.role == .powerHub)
        #expect(power.device == "Pegasus PPBA")
        let dew = try #require(components.first { $0.id == "dewHeater" })
        #expect(dew.role == .dewHeater)
        #expect(dew.device == nil)
    }

    @Test func bothOpticalAssembliesHavingAFocuserThrowsDuplicateRole() throws {
        // The one reachable duplicate-role case given this model's shape (§4.2/RigProfileTranslator's
        // doc comment): the main and guide optical assemblies are independent relationships, but
        // both map their focuser to the same `.focuser` role once flattened.
        let mainOTA = OpticalAssemblyProfile(name: "Esprit 100", purpose: .mainImaging, focuserDeviceName: "ZWO EAF")
        let guideOTA = OpticalAssemblyProfile(name: "50mm Guide Scope", purpose: .guideScope, focuserDeviceName: "Guide Focuser")
        let rig = RigProfile(
            serverRigID: "rig-duplicate",
            name: "Duplicate Focuser Rig",
            opticalAssembly: mainOTA,
            guideOpticalAssembly: guideOTA
        )

        #expect(throws: RigProfileTranslationError.self) {
            try rig.makeComponents()
        }

        do {
            _ = try rig.makeComponents()
            Issue.record("Expected makeComponents() to throw")
        } catch let RigProfileTranslationError.duplicateRole(role) {
            #expect(role == .focuser)
        } catch {
            Issue.record("Expected RigProfileTranslationError.duplicateRole, got \(error)")
        }
    }

    @Test func fullRigFlattensEveryRoleWithoutThrowing() throws {
        let rig = RigProfile(
            serverRigID: "rig-full",
            name: "Full Rig",
            mount: MountProfile(name: "My EQ6-R", deviceName: "EQMod Mount"),
            opticalAssembly: OpticalAssemblyProfile(name: "Esprit 100", purpose: .mainImaging),
            guideOpticalAssembly: OpticalAssemblyProfile(name: "50mm Guide Scope", purpose: .guideScope),
            imagingTrain: ImagingTrainProfile(
                name: "ASI2600MM Train",
                camera: CameraProfile(name: "ASI2600MM Pro", deviceName: "ZWO CCD ASI2600MM Pro")
            ),
            guideCamera: GuideCameraProfile(name: "ASI120MM Mini", deviceName: "ZWO CCD ASI120MM Mini"),
            powerHub: StandaloneEquipmentProfile(name: "Pegasus PPBA", role: .powerHub)
        )

        let components = try rig.makeComponents()
        let roles = Set(components.map(\.role))
        #expect(roles == [.mount, .telescope, .guideTelescope, .camera, .guideCamera, .powerHub])
        // Every component id must be unique within the rig — `saveRig`'s own requirement.
        #expect(Set(components.map(\.id)).count == components.count)
    }
}
