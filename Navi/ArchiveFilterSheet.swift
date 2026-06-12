//
//  ArchiveFilterSheet.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI

struct ActiveFilterChip: View {
    let category: String
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("\(category): \(label)")
                .font(.caption)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.1))
        .foregroundStyle(Color.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 0.5))
    }
}

struct ArchiveFilterSheet: View {
    @Binding var filter: ArchiveFilter
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: FilterCategory = .object
    @State private var allObjects: [String] = []
    @State private var isLoadingObjects = false
    @State private var objectSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            // Sheet header
            HStack {
                Text("Filter Archive")
                    .font(.headline)
                Spacer()
                if filter.isActive {
                    Button("Clear All") { filter = ArchiveFilter() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Two-column layout
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(FilterCategory.allCases, id: \.self) { cat in
                        HStack(spacing: 8) {
                            Label(cat.rawValue, systemImage: cat.icon)
                                .font(.callout)
                            Spacer()
                            if filter.isActive(for: cat) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(selectedCategory == cat
                            ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedCategory = cat }
                    }
                    Spacer()
                }
                .padding(8)
                .frame(width: 180)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Detail panel
                VStack(alignment: .leading, spacing: 0) {
                    // Category header
                    HStack {
                        Text(selectedCategory.rawValue)
                            .font(.title3).fontWeight(.semibold)
                        Spacer()
                        if filter.isActive(for: selectedCategory) {
                            Button("Clear") { filter.clear(selectedCategory) }
                                .buttonStyle(.plain)
                                .font(.callout)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    Divider()

                    categoryDetail
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(width: 560, height: 400)
        .task { await loadObjects() }
    }

    @ViewBuilder
    private var categoryDetail: some View {
        switch selectedCategory {
        case .object:    objectDetail
        case .frameType: frameTypeDetail
        case .kind:      kindDetail
        case .level:     levelDetail
        case .date:      dateDetail
        case .quality:   qualityDetail
        }
    }

    // MARK: Object
    private var objectDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search", text: $objectSearch)
                .textFieldStyle(.roundedBorder)

            let visible = objectSearch.isEmpty ? allObjects
                : allObjects.filter { $0.localizedCaseInsensitiveContains(objectSearch) }

            if isLoadingObjects {
                ProgressView("Loading objects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text(allObjects.isEmpty ? "No objects in archive" : "No objects match \"\(objectSearch)\"")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(visible, id: \.self) { obj in
                            Toggle(isOn: Binding(
                                get: { filter.objects.contains(obj) },
                                set: { checked in
                                    guard checked != filter.objects.contains(obj) else { return }
                                    if checked { filter.objects.insert(obj) } else { filter.objects.remove(obj) }
                                }
                            )) { Text(obj).font(.callout) }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Frame Type
    private var frameTypeDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select frame types to include")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(["light", "dark", "flat", "bias", "darkflat", "diagnostic"], id: \.self) { type in
                    FilterChip(label: type.capitalized, isSelected: filter.types.contains(type)) {
                        if filter.types.contains(type) { filter.types.remove(type) }
                        else { filter.types.insert(type) }
                    }
                }
            }
            Spacer()
        }
    }

    // MARK: Kind
    private var kindDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show in results")
                .font(.callout).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { filter.kind ?? "both" },
                set: { new in
                    let resolved: String? = new == "both" ? nil : new
                    if filter.kind != resolved { filter.kind = resolved }
                }
            )) {
                Text("Frames and framesets").tag("both")
                Text("Frames only").tag("frames")
                Text("Framesets only").tag("framesets")
            }
            .pickerStyle(.radioGroup)
            Spacer()
        }
    }

    // MARK: Processing Level
    private var levelDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processing level")
                .font(.callout).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { filter.processingLevel ?? "all" },
                set: { new in
                    let resolved: String? = new == "all" ? nil : new
                    if filter.processingLevel != resolved { filter.processingLevel = resolved }
                }
            )) {
                Text("All levels").tag("all")
                Text("Raw").tag("raw")
                Text("Stacked").tag("stacked")
                Text("Stretched").tag("stretched")
            }
            .pickerStyle(.radioGroup)
            Spacer()
        }
    }

    // MARK: Date
    private var dateDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("From", isOn: Binding(
                    get: { filter.dateFrom != nil },
                    set: { enabled in
                        guard enabled != (filter.dateFrom != nil) else { return }
                        filter.dateFrom = enabled ? Calendar.current.date(byAdding: .month, value: -3, to: Date()) : nil
                    }
                ))
                .toggleStyle(.checkbox).frame(width: 50, alignment: .leading)
                if filter.dateFrom != nil {
                    DatePicker("", selection: Binding(get: { filter.dateFrom! }, set: { filter.dateFrom = $0 }),
                               displayedComponents: .date).labelsHidden()
                }
            }
            HStack {
                Toggle("To", isOn: Binding(
                    get: { filter.dateTo != nil },
                    set: { enabled in
                        guard enabled != (filter.dateTo != nil) else { return }
                        filter.dateTo = enabled ? Date() : nil
                    }
                ))
                .toggleStyle(.checkbox).frame(width: 50, alignment: .leading)
                if filter.dateTo != nil {
                    DatePicker("", selection: Binding(get: { filter.dateTo! }, set: { filter.dateTo = $0 }),
                               displayedComponents: .date).labelsHidden()
                }
            }
            Spacer()
        }
    }

    // MARK: Quality
    private var qualityDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Empty fields are ignored")
                .font(.caption).foregroundStyle(.secondary)
            QualityRangeRow(label: "FWHM",  min: $filter.minFWHM,  max: $filter.maxFWHM)
            QualityRangeRow(label: "SNR",   min: $filter.minSNR,   max: $filter.maxSNR)
            QualityRangeRow(label: "Stars", min: $filter.minStars, max: $filter.maxStars)
            Spacer()
        }
    }

    private func loadObjects() async {
        isLoadingObjects = true
        defer { isLoadingObjects = false }
        do {
            let result = try await ArchiveManager.shared.callTool(name: "archive_list_objects", arguments: [:])
            let parsed = ArchiveViewerContent.parse(toolName: "archive_list_objects", content: result)
            let names = parsed.rows.compactMap { row -> String? in
                let n = row.values["name"] ?? row.values["object"] ?? ""
                return n.isEmpty ? nil : n
            }
            let sorted = Array(Set(names)).sorted()
            if !sorted.isEmpty { allObjects = sorted }
        } catch {}
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct QualityRangeRow: View {
    let label: String
    @Binding var min: String
    @Binding var max: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .frame(width: 44, alignment: .leading)
            Text("≥")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $min)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .font(.callout)
            Text("≤")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $max)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .font(.callout)
        }
    }
}
