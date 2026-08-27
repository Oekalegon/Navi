//
//  EquipmentLibrarySchemaTests.swift
//  NaviTests
//

import Testing
import Foundation
import SwiftData
@testable import Navi

struct EquipmentLibrarySchemaTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(EquipmentLibrarySchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func schemaBuildsAndPersistsARig() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let mount = MountProfile(name: "My EQ6-R", deviceName: "EQMod Mount")
        let mainOTA = OpticalAssemblyProfile(
            name: "Esprit 100",
            apertureMm: 100,
            focalLengthMm: 550,
            opticalDesign: .refractor,
            purpose: .mainImaging,
            focuserDeviceName: "ZWO EAF"
        )
        let guideOTA = OpticalAssemblyProfile(name: "50mm Guide Scope", purpose: .guideScope)
        let train = ImagingTrainProfile(
            name: "ASI2600MM Train",
            cameraDeviceName: "ZWO CCD ASI2600MM Pro",
            cameraCooled: true,
            filterWheelDeviceName: "ZWO EFW",
            filterWheelSlots: [
                FilterSlotEntry(slot: 1, name: "Luminance"),
                FilterSlotEntry(slot: 2, name: "Red"),
                FilterSlotEntry(slot: 3, name: "Green"),
                FilterSlotEntry(slot: 4, name: "Blue"),
            ]
        )
        let guideCamera = GuideCameraProfile(name: "ASI120MM Mini", deviceName: "ZWO CCD ASI120MM Mini")
        let server = ServerProfile(name: "Observatory Pi", url: URL(string: "http://observatory.local:8080/mcp")!)

        let rig = RigProfile(
            serverRigID: "rig-001",
            name: "Backyard EQ6-R Rig",
            mount: mount,
            opticalAssembly: mainOTA,
            guideOpticalAssembly: guideOTA,
            imagingTrain: train,
            guideCamera: guideCamera,
            defaultObservatoryID: "obs-001",
            defaultServer: server,
            standaloneComponents: [
                StandaloneComponentEntry(id: "power-1", role: "powerHub", deviceName: "Pegasus PPBA")
            ]
        )
        context.insert(rig)
        try context.save()

        let descriptor = FetchDescriptor<RigProfile>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)

        let fetchedRig = try #require(fetched.first)
        #expect(fetchedRig.serverRigID == "rig-001")
        #expect(fetchedRig.mount?.deviceName == "EQMod Mount")
        #expect(fetchedRig.opticalAssembly?.purpose == .mainImaging)
        #expect(fetchedRig.guideOpticalAssembly?.purpose == .guideScope)
        #expect(fetchedRig.imagingTrain?.filterWheelSlots?.first { $0.slot == 2 }?.name == "Red")
        #expect(fetchedRig.guideCamera?.deviceName == "ZWO CCD ASI120MM Mini")
        #expect(fetchedRig.defaultServer?.url.absoluteString == "http://observatory.local:8080/mcp")
        #expect(fetchedRig.standaloneComponents.first?.role == "powerHub")
        #expect(fetchedRig.hasStaleLibraryReferences == false)
    }

    @Test func staleLibraryReferenceIsDetectedAfterEditingAReferencedEntity() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let mount = MountProfile(name: "My EQ6-R")
        let rig = RigProfile(serverRigID: "rig-002", name: "Test Rig", mount: mount, lastResyncedAt: .now)
        context.insert(rig)
        try context.save()

        #expect(rig.hasStaleLibraryReferences == false)

        // Simulate editing the referenced Mount after the rig was last resynced.
        mount.deviceName = "New Mount Device"
        mount.modifiedAt = rig.lastResyncedAt.addingTimeInterval(60)
        try context.save()

        #expect(rig.hasStaleLibraryReferences == true)
    }

    @Test func opticalAssemblyReportsWhetherItHasAFocuser() {
        let withFocuser = OpticalAssemblyProfile(name: "Main OTA", focuserDeviceName: "ZWO EAF")
        #expect(withFocuser.hasFocuser == true)

        let withoutFocuser = OpticalAssemblyProfile(name: "Guide Scope", purpose: .guideScope)
        #expect(withoutFocuser.hasFocuser == false)
    }
}
