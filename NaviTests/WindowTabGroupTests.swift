//
//  WindowTabGroupTests.swift
//  NaviTests
//
//  NAVI-70: the tab add/close/move logic lives on WindowTabGroup precisely so it's testable here
//  without standing up ContentView/SwiftUI.
//

import Testing
import Foundation
@testable import Navi

struct WindowTabGroupTests {

    @Test func addingTabAppendsAndSelectsIt() {
        var group = WindowTabGroup.blank(name: "First")
        let firstID = group.tabs[0].id

        let newID = group.addingTab(name: "Second")

        #expect(group.tabs.map(\.id) == [firstID, newID])
        #expect(group.tabs.last?.name == "Second")
        #expect(group.selectedTabID == newID)
    }

    @Test func closingTheSelectedTabSelectsItsFormerLeftNeighbor() {
        var group = WindowTabGroup.blank(name: "A")
        let a = group.tabs[0].id
        let b = group.addingTab(name: "B")
        let c = group.addingTab(name: "C")
        group.selectedTabID = c

        let closed = group.closingTab(c)

        #expect(closed)
        #expect(group.tabs.map(\.id) == [a, b])
        #expect(group.selectedTabID == b)
    }

    @Test func closingAnUnselectedTabLeavesSelectionUntouched() {
        var group = WindowTabGroup.blank(name: "A")
        let a = group.tabs[0].id
        let b = group.addingTab(name: "B")
        group.selectedTabID = a

        let closed = group.closingTab(b)

        #expect(closed)
        #expect(group.tabs.map(\.id) == [a])
        #expect(group.selectedTabID == a)
    }

    @Test func closingTheLastTabIsANoOp() {
        var group = WindowTabGroup.blank(name: "Only")
        let onlyID = group.tabs[0].id

        let closed = group.closingTab(onlyID)

        #expect(!closed)
        #expect(group.tabs.map(\.id) == [onlyID])
    }

    @Test func movingTabSwapsWithItsNeighbor() {
        var group = WindowTabGroup.blank(name: "A")
        let a = group.tabs[0].id
        let b = group.addingTab(name: "B")
        let c = group.addingTab(name: "C")

        group.movingTab(a, by: 1)

        #expect(group.tabs.map(\.id) == [b, a, c])
    }

    @Test func movingTabPastTheEdgeIsANoOp() {
        var group = WindowTabGroup.blank(name: "A")
        let a = group.tabs[0].id
        let b = group.addingTab(name: "B")

        group.movingTab(a, by: -1)

        #expect(group.tabs.map(\.id) == [a, b])
    }
}
