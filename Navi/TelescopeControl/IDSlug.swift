//
//  IDSlug.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1, §4.2.
//

import Foundation

/// Generates a stable id for a new server-side record, shared by every flow that creates one
/// without the server having assigned an id yet: `ObservatoryEditForm`'s "Add Observatory" flow
/// and `TelescopeSelectionSheet`'s "Current Location" quick-create (§4.1, both `Observatory`),
/// and `RigEditForm`'s "Add Rig" flow (§4.2, `Rig`) — one shared id-generation rule rather than a
/// copy per record kind. Kind-agnostic on purpose: matches INDIMCP-server's general
/// `<kind>/<id>.yaml` filing convention for any record kind, not just observatories.
enum IDSlug {
    /// A filesystem-safe id from `name`, matching how INDIMCP-server files records
    /// (e.g. `observatories/<id>.yaml`, `rigs/<id>.yaml`) — lowercased, non-alphanumeric runs
    /// collapsed to one hyphen.
    static func make(from name: String) -> String {
        let lowered = name.lowercased()
        let slug = lowered.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-" && result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? UUID().uuidString : slug
    }
}
