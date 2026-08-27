//
//  ObservatoryIDSlugTests.swift
//  NaviTests
//

import Testing
@testable import Navi

struct ObservatoryIDSlugTests {

    @Test func lowercasesAndHyphenatesSpaces() {
        #expect(ObservatoryIDSlug.make(from: "Home Backyard") == "home-backyard")
    }

    @Test func collapsesRunsOfNonAlphanumericsToOneHyphen() {
        #expect(ObservatoryIDSlug.make(from: "  Star Party -- 2026!! ") == "star-party-2026")
    }

    @Test func fallsBackToAUUIDWhenNothingAlphanumericRemains() {
        let slug = ObservatoryIDSlug.make(from: "!!!")
        #expect(slug.count == 36) // UUID string length
        #expect(!slug.isEmpty)
    }
}
