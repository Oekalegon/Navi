//
//  CaptureImportPlanningTests.swift
//  NaviTests
//
//  CaptureImportPlanning is the pure logic behind NAVI-52's frame download/import pipeline —
//  kept separate from CaptureImportManager's async orchestration so it's testable without a live
//  server.
//

import Testing
import Foundation
import AstrophotoArchiveKit
import INDIMCPKit
@testable import Navi

struct CaptureImportPlanningTests {

    private func frame(
        frameId: String, runId: String?, device: String = "CCD Simulator",
        capturedAt: String = "2026-01-01T00:00:00Z"
    ) -> FrameMetadataResponse {
        FrameMetadataResponse(
            frameId: frameId, runId: runId, device: device, sizeBytes: 100,
            checksumSha256: nil, capturedAt: capturedAt, transferredAt: nil,
            downloadUrl: "https://example.com/\(frameId)", issues: []
        )
    }

    // MARK: relevantFrames — the "only frames Navi itself captured" filter

    @Test func keepsOnlyFramesWithATrackedRunID() {
        let mine = frame(frameId: "a", runId: "run-1")
        let otherClient = frame(frameId: "b", runId: "run-2")
        let adHoc = frame(frameId: "c", runId: nil)

        let relevant = CaptureImportPlanning.relevantFrames([mine, otherClient, adHoc], myRunIDs: ["run-1"])

        #expect(relevant.map(\.frameId) == ["a"])
    }

    @Test func emptyTrackedSetKeepsNothing() {
        let frames = [frame(frameId: "a", runId: "run-1")]

        #expect(CaptureImportPlanning.relevantFrames(frames, myRunIDs: []).isEmpty)
    }

    // MARK: localDestination

    @Test func destinationGroupsByLocalCaptureDate() {
        let root = URL(fileURLWithPath: "/archive")
        let f = frame(frameId: "abc", runId: "run-1", device: "CCD", capturedAt: "2026-03-15T10:00:00Z")

        let destination = CaptureImportPlanning.localDestination(for: f, archiveRoot: root)

        #expect(destination.deletingLastPathComponent().lastPathComponent == "2026-03-15")
        #expect(destination.lastPathComponent == f.suggestedLocalFilename)
    }

    @Test func destinationFallsBackWhenTimestampDoesNotParse() {
        let root = URL(fileURLWithPath: "/archive")
        let f = frame(frameId: "abc", runId: "run-1", capturedAt: "not-a-date")

        let destination = CaptureImportPlanning.localDestination(for: f, archiveRoot: root)

        #expect(destination.deletingLastPathComponent().lastPathComponent == "unknown-date")
    }

    // MARK: frameSetQuery / frameSetName

    private func archivedFrame(
        id: UUID = UUID(), objectName: String? = "M31", frameType: String = "light",
        camera: String? = "CCD Simulator", timestamp: Date? = Date(timeIntervalSince1970: 0)
    ) -> ArchivedFrame {
        ArchivedFrame(
            id: id, filePath: "/tmp/\(id).fits", objectName: objectName, ra: nil, dec: nil,
            healpixPixel: nil, frameType: frameType, filter: nil, camera: camera,
            focalLength: nil, pixelScale: nil, temperature: nil, timestamp: timestamp,
            exposureTime: nil, gain: nil, offset: nil, width: nil, height: nil, bitpix: nil,
            calibrated: false, stacked: false, stretched: false,
            processingLevel: .raw, addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func queryNarrowsByFrameTypeCameraAndTimeSpan() throws {
        let a = archivedFrame(timestamp: Date(timeIntervalSince1970: 100))
        let b = archivedFrame(timestamp: Date(timeIntervalSince1970: 200))

        let query = try #require(CaptureImportPlanning.frameSetQuery(for: [a, b]))

        #expect(query.frameTypes == ["light"])
        #expect(query.camera == "CCD Simulator")
        let range = try #require(query.dateRange)
        #expect(range.start < Date(timeIntervalSince1970: 100))
        #expect(range.end > Date(timeIntervalSince1970: 200))
    }

    @Test func queryIsNilForAnEmptyFrameList() {
        #expect(CaptureImportPlanning.frameSetQuery(for: []) == nil)
    }

    @Test func nameCombinesObjectTypeAndDate() {
        let f = archivedFrame(objectName: "M31", frameType: "light")

        let name = CaptureImportPlanning.frameSetName(for: f)

        #expect(name.contains("M31"))
        #expect(name.contains("light"))
    }

    @Test func nameFallsBackWhenNothingIsAvailable() {
        let f = archivedFrame(objectName: nil, frameType: "", timestamp: nil)

        #expect(CaptureImportPlanning.frameSetName(for: f) == "Capture")
    }

    // MARK: extraMemberIDs

    @Test func extraMemberIDsFindsWhatIsNotInTheExactSet() {
        let a = UUID(), b = UUID(), c = UUID()

        let extras = CaptureImportPlanning.extraMemberIDs(current: [a, b, c], exact: [a, b])

        #expect(extras == [c])
    }

    @Test func extraMemberIDsIsEmptyWhenEverythingMatches() {
        let a = UUID(), b = UUID()

        #expect(CaptureImportPlanning.extraMemberIDs(current: [a, b], exact: [a, b]).isEmpty)
    }
}
