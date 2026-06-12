//
//  ArchiveColumnSettings.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI
import Observation

struct ColumnEntry {
    let key: String
    let label: String       // shown in the column chooser
    var header: String? = nil  // table column header; defaults to label
}

struct ColumnGroup: Identifiable {
    let id: String
    let header: String
    let entries: [ColumnEntry]
}

@Observable
final class ArchiveColumnSettings {
    var hiddenColumns: Set<String> = []

    static let groups: [ColumnGroup] = [
        ColumnGroup(id: "observation", header: "Observation", entries: [
            ColumnEntry(key: "name",   label: "Name"),
            ColumnEntry(key: "object", label: "Object"),
            ColumnEntry(key: "date",   label: "Observation Date"),
        ]),
        ColumnGroup(id: "properties", header: "Properties", entries: [
            ColumnEntry(key: "type",   label: "Type"),
            ColumnEntry(key: "filter", label: "Filter"),
            ColumnEntry(key: "level",  label: "Level"),
            ColumnEntry(key: "exp",    label: "Exposure"),
        ]),
        ColumnGroup(id: "quality", header: "Quality", entries: [
            ColumnEntry(key: "fwhm",        label: "Mean FWHM [px]", header: "FWHM (Mean)"),
            ColumnEntry(key: "fwhm_arcsec", label: "Mean FWHM [\"]", header: "FWHM (Mean)"),
            ColumnEntry(key: "ecc",   label: "Eccentricity"),
            ColumnEntry(key: "stars", label: "Number of Stars"),
        ]),
        ColumnGroup(id: "equipment", header: "Equipment", entries: [
            ColumnEntry(key: "camera", label: "Camera"),
        ]),
        ColumnGroup(id: "archive", header: "Archive", entries: [
            ColumnEntry(key: "added",  label: "Added"),
            ColumnEntry(key: "frames", label: "Number of Frames"),
        ]),
        ColumnGroup(id: "file", header: "File", entries: [
            ColumnEntry(key: "file", label: "File"),
        ]),
    ]

    static var standardColumns: [String] {
        groups.flatMap { $0.entries.map { $0.key } }
    }

    private static let key = "archiveViewer.columnSettings"

    init() { load() }

    func visibleColumns(from available: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        // Standard columns always appear in group order (unless hidden)
        for col in Self.standardColumns where !hiddenColumns.contains(col) {
            result.append(col); seen.insert(col)
        }
        // Any extra columns from data that aren't in the standard set
        for col in available where !seen.contains(col) && !hiddenColumns.contains(col) {
            result.append(col)
        }
        return result
    }

    func save() {
        UserDefaults.standard.set(Array(hiddenColumns), forKey: Self.key)
    }

    private func load() {
        if let arr = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            hiddenColumns = Set(arr)
        } else if let dict = UserDefaults.standard.dictionary(forKey: Self.key),
                  let arr = dict["hiddenColumns"] as? [String] {
            hiddenColumns = Set(arr)
        }
    }
}

struct ColumnsPopover: View {
    let settings: ArchiveColumnSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Columns").font(.headline)
                Spacer()
                if !settings.hiddenColumns.isEmpty {
                    Button("Show All") { settings.hiddenColumns.removeAll(); settings.save() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ArchiveColumnSettings.groups) { group in
                        Text(group.header.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 3)
                        ForEach(group.entries, id: \.key) { entry in
                            Toggle(isOn: Binding(
                                get: { !settings.hiddenColumns.contains(entry.key) },
                                set: { show in
                                    let visible = !settings.hiddenColumns.contains(entry.key)
                                    guard show != visible else { return }
                                    if show { settings.hiddenColumns.remove(entry.key) }
                                    else    { settings.hiddenColumns.insert(entry.key) }
                                    settings.save()
                                }
                            )) { Text(entry.label).font(.callout) }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 210)
    }
}
