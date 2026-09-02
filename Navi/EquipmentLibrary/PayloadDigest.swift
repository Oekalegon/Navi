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
/// Derived from the encoded payload rather than a hand-listed set of fields, so a field added to
/// `Rig`/`Observatory` later is covered without anyone remembering to extend a list — the same
/// hazard that made `modifiedAt` stamping fragile. That does mean the digest covers *everything*
/// the payload carries, including anything Navi doesn't itself edit; that's deliberate, since a
/// server-side change to such a field is exactly the drift worth reporting.
enum PayloadDigest {
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
