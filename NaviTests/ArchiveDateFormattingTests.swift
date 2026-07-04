//
//  ArchiveDateFormattingTests.swift
//  NaviTests
//
//  Created by Dieudonné Willems on 04/07/2026.
//

import Testing
import Foundation
@testable import Navi

// Regression coverage for NAVI-42: shortDate() previously rendered timestamps via
// ISO8601DateFormatter, which defaults to UTC, so the Archive Table's date/added/
// created columns could show a different calendar date than the observer's local
// date. These tests pin a timestamp near local midnight and assert the day rolls
// over correctly in both directions relative to UTC.
struct ArchiveDateFormattingTests {

    @Test func shortDateRollsForwardInATimeZoneAheadOfUTC() {
        // 2025-01-01T23:30:00Z; Amsterdam is CET (UTC+1) in January (no DST).
        let date = Date(timeIntervalSince1970: 1_735_774_200)
        let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
        #expect(shortDate(date, timeZone: amsterdam) == "2025-01-02 00:30")
    }

    @Test func shortDateRollsBackwardInATimeZoneBehindUTC() {
        // 2025-01-01T02:30:00Z; Los Angeles is PST (UTC-8) in January (no DST).
        let date = Date(timeIntervalSince1970: 1_735_698_600)
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        #expect(shortDate(date, timeZone: losAngeles) == "2024-12-31 18:30")
    }

    @Test func shortDateDefaultsToTheSystemLocalTimeZone() {
        let date = Date(timeIntervalSince1970: 1_735_774_200)
        #expect(shortDate(date) == shortDate(date, timeZone: .current))
    }
}
