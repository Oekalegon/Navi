//
//  PayloadDigest.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.3. NAVI-86.
//

import Foundation
import CryptoKit

/// A stable fingerprint of a payload Navi pushes to the INDI-MCP server.
///
/// Stored on the local record as `lastPushedDigest` after a successful push, which lets one value
/// answer two questions: this record needs pushing when its *current* digest differs from the
/// stored one, and someone else changed it underneath us when the *server's* digest differs from
/// the stored one.
///
/// A rig digests its whole payload — Navi owns every field of one, so nothing is excluded and a
/// field added to `Rig` later is covered without anyone remembering to extend a list.
///
/// An observatory digests only the fields Navi actually edits, via `ofObservatoryFields`. Two
/// reasons. Its payload also carries `horizonProfile`, which Navi preserves but has no editor for —
/// and since a push reuses whatever the server currently holds for it, a change made there survives
/// regardless, so treating it as drift would only produce conflicts Navi could have resolved by
/// itself. More practically, "does this need pushing" has to be answerable *offline*, and the local
/// record doesn't store `horizonProfile`, so a whole-payload digest couldn't be computed without a
/// round trip — which defeats the point of a reconnect sync.
enum PayloadDigest {
    /// The Navi-owned subset of an observatory. Hand-listed deliberately — see the type's doc
    /// comment for why an observatory can't digest its whole payload.
    static func ofObservatoryFields(
        id: String,
        name: String,
        latitudeDeg: Double,
        longitudeDeg: Double,
        elevationMeters: Double
    ) -> String? {
        struct OwnedFields: Encodable {
            let id: String
            let name: String
            let latitudeDeg: Double
            let longitudeDeg: Double
            let elevationMeters: Double
        }
        return of(OwnedFields(
            id: id, name: name, latitudeDeg: latitudeDeg,
            longitudeDeg: longitudeDeg, elevationMeters: elevationMeters
        ))
    }

    /// `nil` only if the value can't be encoded, which for these payloads would be a programming
    /// error rather than a runtime condition — callers treat it as "can't compare, don't claim
    /// anything", never as "unchanged".
    static func of(_ value: some Encodable) -> String? {
        let encoder = JSONEncoder()
        // Key order is not otherwise guaranteed between encodes, and an unstable ordering would
        // make every comparison report a spurious difference.
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
