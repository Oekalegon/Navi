//
//  FilterSlotEntry.swift
//  Navi
//
//  Equipment library entity — see docs/design/INDI-MCP-Integration.md §4.3.
//

import Foundation

/// One filter-wheel slot: slot number to filter name.
///
/// A plain `Codable` struct, not `[Int: String]` directly — SwiftData's attribute encoding
/// doesn't reliably support `Dictionary` with a non-`String` key (it crashes inside SwiftData's
/// internal `Encodable` machinery at save time, confirmed empirically), even though `Codable`/
/// `JSONEncoder` alone support it fine. An array of a small struct is SwiftData's well-supported
/// path for this kind of structured attribute data (see `ImagingTrainProfile.filterWheelSlots`).
struct FilterSlotEntry: Codable, Hashable {
    var slot: Int
    var name: String

    init(slot: Int, name: String) {
        self.slot = slot
        self.name = name
    }
}
