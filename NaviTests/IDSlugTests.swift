//
//  IDSlugTests.swift
//  NaviTests
//

import Testing
@testable import Navi

struct IDSlugTests {

    @Test func lowercasesAndHyphenatesSpaces() {
        #expect(IDSlug.make(from: "Home Backyard") == "home-backyard")
    }

    @Test func collapsesRunsOfNonAlphanumericsToOneHyphen() {
        #expect(IDSlug.make(from: "  Star Party -- 2026!! ") == "star-party-2026")
    }

    @Test func fallsBackToAUUIDWhenNothingAlphanumericRemains() {
        let slug = IDSlug.make(from: "!!!")
        #expect(slug.count == 36) // UUID string length
        #expect(!slug.isEmpty)
    }
}
