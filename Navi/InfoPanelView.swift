//
//  InfoPanelView.swift
//  Navi
//
//  Created by Dieudonné Willems on 12/06/2026.
//

import SwiftUI
import AstrophotoKit
import AstrophotoArchiveKit

/// Right-side info pane (NAVI-27): shows the full FITS header of the current
/// frame, grouped via FITSKeywordCatalog, followed by archive data that is not
/// already present in the header (processing state, quality metrics, …).
struct InfoPanelView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager

    @State private var headerSections: [FITSHeaderSection] = []
    @State private var archiveItems: [InfoItem] = []
    @State private var qualityItems: [InfoItem] = []
    @State private var frameTitle: String? = nil
    @State private var loadError: String? = nil
    @State private var isLoading = false

    struct InfoItem: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: paneManager.infoURL) { await load() }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            PaneCloseButton(paneType: .infoPanel)

            Divider()
                .frame(height: 14)

            Image(systemName: "info.circle")
                .font(.system(size: 14))
            Text(frameTitle ?? "Info")
                .font(.headline)
                .lineLimit(1)
                .help(paneManager.infoURL?.lastPathComponent ?? "")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if paneManager.infoURL == nil {
            emptyState("Select a frame to see its information")
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    ForEach(headerSections, id: \.group) { section in
                        sectionHeader(section.group.rawValue)
                        ForEach(section.entries, id: \.keyword) { entry in
                            InfoRow(label: entry.displayName, value: entry.displayValue,
                                    detail: entry.keyword)
                        }
                    }
                    if !archiveItems.isEmpty {
                        sectionHeader("Archive")
                        ForEach(archiveItems) { item in
                            InfoRow(label: item.label, value: item.value)
                        }
                    }
                    if !qualityItems.isEmpty {
                        sectionHeader("Quality")
                        ForEach(qualityItems) { item in
                            InfoRow(label: item.label, value: item.value)
                        }
                    }
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "info.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func load() async {
        guard let url = paneManager.infoURL else {
            headerSections = []; archiveItems = []; qualityItems = []
            frameTitle = nil; loadError = nil
            return
        }
        isLoading = true
        defer { isLoading = false }

        let frame = await ArchiveManager.shared.archivedFrame(filePath: url.path)
        var metadata: [String: FITSHeaderValue] = [:]
        do {
            metadata = try await Task.detached(priority: .userInitiated) {
                let file = try FITSFile(path: url.path)
                return try file.readHeader()
            }.value
            loadError = nil
        } catch {
            loadError = "Could not read FITS header: \(error.localizedDescription)"
        }
        headerSections = FITSKeywordCatalog.groupedSections(from: metadata)
        archiveItems = Self.archiveInfo(frame: frame, header: metadata)
        qualityItems = Self.qualityInfo(frame: frame)
        frameTitle = frame.flatMap(Self.displayName) ?? url.lastPathComponent
    }

    // Same naming convention as the FITS viewer header.
    private static func displayName(for frame: ArchivedFrame) -> String? {
        let parts = [
            frame.objectName ?? "",
            frame.filter ?? "",
            frame.processingLevel.rawValue.capitalized
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // Archive fields that duplicate a FITS keyword are skipped when that
    // keyword is present in the header (the header section already shows it).
    private static func archiveInfo(frame: ArchivedFrame?,
                                    header: [String: FITSHeaderValue]) -> [InfoItem] {
        guard let f = frame else {
            return [InfoItem(label: "Archive", value: "Not in archive")]
        }
        func missing(_ keywords: String...) -> Bool {
            !keywords.contains { header[$0] != nil }
        }
        var items: [InfoItem] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { items.append(InfoItem(label: label, value: value)) }
        }

        add("ID", f.id.uuidString)
        var processing = f.processingLevel.rawValue.capitalized
        let flags = [f.calibrated ? "calibrated" : nil,
                     f.stacked ? "stacked" : nil,
                     f.stretched ? "stretched" : nil].compactMap { $0 }
        if !flags.isEmpty { processing += " (\(flags.joined(separator: ", ")))" }
        add("Processing", processing)
        add("Added", f.addedAt.formatted(date: .abbreviated, time: .shortened))
        if f.rejected {
            add("Rejected", f.rejectedReason.map { "Yes — \($0)" } ?? "Yes")
        }

        if missing("OBJECT")   { add("Object", f.objectName) }
        if missing("IMAGETYP") { add("Frame type", f.frameType.capitalized) }
        if missing("FILTER")   { add("Filter", f.filter) }
        if missing("DATE-OBS") {
            add("Date", f.timestamp.map { $0.formatted(date: .abbreviated, time: .shortened) })
        }
        if f.stacked, let beg = f.sessionBeg, let end = f.sessionEnd {
            add("Session", "\(beg.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
        }
        if missing("EXPTIME", "EXPOSURE") {
            add("Exposure", f.exposureTime.map { String(format: "%g s", $0) })
        }
        if missing("INSTRUME") { add("Camera", f.camera) }
        if missing("TELESCOP") { add("Telescope", f.telescope) }
        if missing("OBSERVAT") { add("Site", f.site) }
        if missing("GAIN")     { add("Gain", f.gain.map { String(format: "%g", $0) }) }
        if missing("OFFSET")   { add("Offset", f.offset.map { String(format: "%g", $0) }) }
        if missing("EGAIN")    { add("EGAIN", f.egain.map { String(format: "%.4f e⁻/ADU", $0) }) }
        if missing("CCD-TEMP") { add("Sensor temp", f.temperature.map { String(format: "%.1f °C", $0) }) }
        if f.stacked, let mn = f.temperatureMin, let mx = f.temperatureMax, abs(mx - mn) >= 0.5 {
            add("Temp range", String(format: "%.1f – %.1f °C", mn, mx))
        }
        if missing("FOCALLEN") { add("Focal length", f.focalLength.map { String(format: "%.0f mm", $0) }) }
        if missing("PIXSCALE", "SCALE") {
            add("Pixel scale", f.pixelScale.map { String(format: "%.3f \"/px", $0) })
        }
        if missing("POSANGLE", "PA", "ROTATANG") {
            add("Position angle", f.positionAngle.map { String(format: "%.1f°", $0) })
        }
        if missing("OBJCTRA", "RA"),
           let ra = f.ra, let dec = f.dec {
            add("RA / Dec", String(format: "%.4f° / %.4f°", ra, dec))
        }
        return items
    }

    // Quality metrics are archive measurements; always shown (a header FWHM,
    // if present, is the acquisition software's estimate, not the same thing).
    private static func qualityInfo(frame: ArchivedFrame?) -> [InfoItem] {
        guard let f = frame else { return [] }
        var items: [InfoItem] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { items.append(InfoItem(label: label, value: value)) }
        }
        add("Stars", f.starCount.map { "\($0)" })
        if let px = f.medianFWHM {
            let arcsec = f.medianFWHMArcsec.map { String(format: "  (%.2f\")", $0) } ?? ""
            add("FWHM (Mean)", String(format: "%.2f px%@", px, arcsec))
        }
        add("Eccentricity", f.medianEccentricity.map { String(format: "%.3f", $0) })
        if let e = f.backgroundNoiseElectrons {
            add("Background", String(format: "%.1f e⁻", e))
        } else if let n = f.backgroundNoise {
            add("Background", String(format: "%.1f ADU", n))
        }
        if let v = f.saturatedStarCount, v > 0 { add("Saturated stars", "\(v)") }
        if let v = f.hotPixelCount, v > 0 { add("Hot pixels", "≈\(v)") }
        return items
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var detail: String? = nil   // e.g. the raw FITS keyword, shown as tooltip

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
                .help(detail ?? label)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
