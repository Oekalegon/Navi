//
//  ObservatoryIDSlug.swift
//  Navi
//
//  See docs/design/INDI-MCP-Integration.md §4.1, §4.2.
//

import Foundation

/// Generates a stable id for a new `Observatory`, shared by `ObservatoryEditForm`'s "Add
/// Observatory" flow and `TelescopeSelectionSheet`'s "Current Location" quick-create (§4.1) —
/// both create a brand-new `Observatory` and need the same id-generation rule.
enum ObservatoryIDSlug {
    /// A filesystem-safe id from `name`, matching how INDIMCP-server files observatories
    /// (`observatories/<id>.yaml`) — lowercased, non-alphanumeric runs collapsed to one hyphen.
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
