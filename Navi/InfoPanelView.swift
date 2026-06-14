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
    @State private var provenanceEntries: [ProvenanceEntry] = []
    @State private var versionEntries: [VersionEntry] = []
    @State private var suppressedQualityKeywords: Set<String> = []
    @State private var frameTitle: String? = nil
    @State private var loadError: String? = nil
    @State private var isLoading = false

    struct InfoItem: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct ProvenanceEntry: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var framesetID: String? = nil
        var isSubheader: Bool = false
    }

    struct VersionEntry: Identifiable {
        let id: UUID
        let frame: ArchivedFrame
        let versionNumber: Int
        let isCurrent: Bool
        let diff: FrameDiff?  // diff between this frame and the next-older one in the chain
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
            PaneMoveButton(pane: pane)

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
                    ForEach(headerSections.filter {
                                (provenanceEntries.isEmpty || $0.group != .processing) &&
                                $0.group != .quality
                            }, id: \.group) { section in
                        sectionHeader(section.group.rawValue)
                        ForEach(section.entries, id: \.keyword) { entry in
                            InfoRow(label: entry.displayName, value: entry.displayValue,
                                    detail: entry.keyword)
                        }
                        if section.group == .camera {
                            let fitsQuality = headerSections.first { $0.group == .quality }
                            if fitsQuality != nil || !qualityItems.isEmpty {
                                sectionHeader("Quality")
                                if let fq = fitsQuality {
                                    ForEach(fq.entries.filter { !suppressedQualityKeywords.contains($0.keyword) },
                                            id: \.keyword) { entry in
                                        InfoRow(label: entry.displayName, value: entry.displayValue,
                                                detail: entry.keyword)
                                    }
                                }
                                ForEach(qualityItems) { item in
                                    InfoRow(label: item.label, value: item.value)
                                }
                            }
                        }
                    }
                    if !archiveItems.isEmpty {
                        sectionHeader("Archive")
                        ForEach(archiveItems) { item in
                            InfoRow(label: item.label, value: item.value)
                        }
                    }
                    if !provenanceEntries.isEmpty {
                        sectionHeader("Provenance")
                        ForEach(provenanceEntries) { entry in
                            if entry.isSubheader {
                                provenanceSubheader(entry.label)
                            } else if let fsID = entry.framesetID {
                                ProvenanceLinkRow(label: entry.label, value: entry.value) {
                                    openFrameset(id: fsID)
                                }
                            } else {
                                InfoRow(label: entry.label, value: entry.value)
                            }
                        }
                    }
                    if !versionEntries.isEmpty {
                        sectionHeader("Versions")
                        ForEach(versionEntries) { entry in
                            if entry.isCurrent {
                                VersionRow(entry: entry)
                            } else {
                                VersionLinkRow(entry: entry) { openVersion(entry.frame) }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func provenanceSubheader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 1)
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
            headerSections = []; archiveItems = []; qualityItems = []; provenanceEntries = []
            versionEntries = []; suppressedQualityKeywords = []; frameTitle = nil; loadError = nil
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
        suppressedQualityKeywords = frame.map(Self.suppressedQualityKeywords) ?? []
        provenanceEntries = frame != nil ? await loadProvenance(frame: frame!) : []
        versionEntries = frame != nil ? await loadVersionChain(frame: frame!, currentPath: url.path) : []
        frameTitle = frame.flatMap(Self.displayName) ?? url.lastPathComponent
    }

    private func loadVersionChain(frame: ArchivedFrame, currentPath: String) async -> [VersionEntry] {
        let chain = await ArchiveManager.shared.fullVersionChain(for: frame)
        guard chain.count > 1 else { return [] }
        var entries: [VersionEntry] = []
        for (index, f) in chain.enumerated() {
            let diff: FrameDiff?
            if index + 1 < chain.count {
                diff = await ArchiveManager.shared.frameDiff(f, predecessor: chain[index + 1])
            } else {
                diff = nil
            }
            entries.append(VersionEntry(
                id: f.id,
                frame: f,
                versionNumber: chain.count - index,
                isCurrent: f.filePath == currentPath,
                diff: diff
            ))
        }
        return entries
    }

    private func loadProvenance(frame: ArchivedFrame) async -> [ProvenanceEntry] {
        guard let (run, inputs) = await ArchiveManager.shared.processingRun(for: frame),
              !inputs.isEmpty else { return [] }
        var entries: [ProvenanceEntry] = []
        entries.append(ProvenanceEntry(label: "Pipeline", value: Self.formatSnakeCase(run.pipelineID)))
        entries.append(ProvenanceEntry(label: "Input frames", value: "\(inputs.count)"))

        let inputIDs = inputs.compactMap(\.frameID)
        if !inputIDs.isEmpty {
            var tally: [UUID: Int] = [:]
            for fid in inputIDs {
                for fsID in await ArchiveManager.shared.frameSetIDs(forFrame: fid) {
                    tally[fsID, default: 0] += 1
                }
            }
            let threshold = max(1, inputIDs.count / 2)
            let sourceIDs = tally.filter { $0.value >= threshold }.keys.sorted { $0.uuidString < $1.uuidString }
            for fsID in sourceIDs {
                guard let fs = await ArchiveManager.shared.frameSet(id: fsID) else { continue }
                let name = fs.name.isEmpty ? Self.framesetLabel(fs) : fs.name
                entries.append(ProvenanceEntry(label: "Source", value: name, framesetID: fsID.uuidString))
            }
        }

        let params = run.parameters.isEmpty
            ? ArchiveManager.shared.pipelineDefaultParameters(id: run.pipelineID)
            : run.parameters

        // Group parameters by the pipeline step that declares them.
        // Each step's ParameterSpec.from is the global key used in run.parameters.
        var assignedKeys = Set<String>()
        var groups: [(name: String, rows: [(key: String, value: String)])] = []
        if let pipeline = PipelineRegistry.shared.get(id: run.pipelineID) {
            for step in pipeline.steps {
                var stepRows: [(String, String)] = []
                for spec in step.parameters {
                    guard let key = spec.from, !assignedKeys.contains(key),
                          let value = params[key] else { continue }
                    assignedKeys.insert(key)
                    stepRows.append((key, value))
                }
                if !stepRows.isEmpty {
                    let name = step.name ?? Self.formatSnakeCase(step.id)
                    groups.append((name: name, rows: stepRows.sorted { $0.0 < $1.0 }))
                }
            }
        }
        let unclaimed = params.filter { !assignedKeys.contains($0.key) }
                              .sorted { $0.key < $1.key }

        if groups.count > 1 {
            for group in groups {
                entries.append(ProvenanceEntry(label: group.name, value: "", isSubheader: true))
                for (key, value) in group.rows {
                    entries.append(ProvenanceEntry(label: Self.formatSnakeCase(key), value: value))
                }
            }
            for (key, value) in unclaimed {
                entries.append(ProvenanceEntry(label: Self.formatSnakeCase(key), value: value))
            }
        } else {
            for (key, value) in params.sorted(by: { $0.key < $1.key }) {
                entries.append(ProvenanceEntry(label: Self.formatSnakeCase(key), value: value))
            }
        }
        return entries
    }

    private func openVersion(_ frame: ArchivedFrame) {
        let url = URL(fileURLWithPath: frame.filePath)
        paneManager.infoURL = url
        paneManager.showFITSViewerIfVisible(url: url)
    }

    private func openFrameset(id: String) {
        Task {
            do {
                let result = try await ArchiveManager.shared.callTool(
                    name: "archive_frameset_get",
                    arguments: ["id": id]
                )
                let content = ArchiveViewerContent.parse(toolName: "archive_frameset_get", content: result)
                paneManager.showArchiveViewer(content: content)
            } catch {}
        }
    }

    private static func suppressedQualityKeywords(for frame: ArchivedFrame) -> Set<String> {
        var s: Set<String> = []
        if frame.starCount           != nil { s.formUnion(["NSTARS"]) }
        if frame.saturatedStarCount  != nil { s.formUnion(["SATSTARS"]) }
        if frame.medianEccentricity  != nil { s.formUnion(["MEDECC", "MEANECC"]) }
        if frame.medianFWHM          != nil { s.formUnion(["MEDFWHM", "MEANFWHM", "FWHM"]) }
        if frame.backgroundNoise     != nil ||
           frame.backgroundNoiseElectrons != nil { s.formUnion(["BACKNOIS", "SKY_BKG"]) }
        return s
    }

    static func formatSnakeCase(_ s: String) -> String { infoPanelFormatSnakeCase(s) }


    private static func framesetLabel(_ fs: ArchivedFrameSet) -> String {
        let parts = [fs.objectName, fs.filter].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "Frameset" : parts.joined(separator: " ")
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

private struct VersionRow: View {
    let entry: InfoPanelView.VersionEntry
    @State private var showDiff = false

    var body: some View {
        HStack(spacing: 8) {
            Text("v\(entry.versionNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 110, alignment: .leading)
            Text(entry.frame.addedAt.formatted(date: .abbreviated, time: .shortened) + "  (current)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let diff = entry.diff, VersionDiffPopover.hasContent(diff) {
                Button { showDiff = true } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDiff, arrowEdge: .trailing) {
                    VersionDiffPopover(diff: diff)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

private struct VersionLinkRow: View {
    let entry: InfoPanelView.VersionEntry
    let action: () -> Void
    @State private var showDiff = false

    var body: some View {
        HStack(spacing: 8) {
            Text("v\(entry.versionNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(entry.frame.addedAt.formatted(date: .abbreviated, time: .shortened))
                    Image(systemName: "arrow.right.circle")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let diff = entry.diff, VersionDiffPopover.hasContent(diff) {
                Button { showDiff = true } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDiff, arrowEdge: .trailing) {
                    VersionDiffPopover(diff: diff)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

private struct VersionDiffPopover: View {
    let diff: FrameDiff

    static func deduplicatedParamChanges(_ diff: FrameDiff) -> [FrameDiff.ParameterChange] {
        diff.parameterChanges.sorted { $0.key < $1.key }
    }

    static func hasContent(_ diff: FrameDiff) -> Bool {
        let q = diff.quality
        let hasQuality =
            meaningfulChange(q.fwhm.from, q.fwhm.to, threshold: 0.005) ||
            (q.starCount.from != nil && q.starCount.from != q.starCount.to) ||
            meaningfulChange(q.eccentricity.from, q.eccentricity.to, threshold: 0.005) ||
            meaningfulChange(q.backgroundNoise.from, q.backgroundNoise.to, threshold: 0.01)
        return !deduplicatedParamChanges(diff).isEmpty ||
               diff.inputsAdded.count != diff.inputsRemoved.count ||
               hasQuality
    }

    private static func meaningfulChange(_ from: Double?, _ to: Double?, threshold: Double) -> Bool {
        guard let from, let to else { return false }
        return abs(from - to) > threshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let paramChanges = Self.deduplicatedParamChanges(diff)
            if !paramChanges.isEmpty {
                popoverSection("Parameters")
                ForEach(paramChanges, id: \.key) { change in
                    popoverRow(
                        label: infoPanelFormatSnakeCase(change.key),
                        value: "\(change.from?.description ?? "—") → \(change.to?.description ?? "—")"
                    )
                }
            }

            let inputDelta = diff.inputsAdded.count - diff.inputsRemoved.count
            if inputDelta != 0 {
                popoverSection("Inputs")
                let sign = inputDelta > 0 ? "+" : ""
                popoverRow(label: "Frames", value: "\(sign)\(inputDelta)")
            }

            let q = diff.quality
            let qualityRows: [(String, String)] = [
                (q.starCount.from != nil && q.starCount.from != q.starCount.to) ?
                    ("Stars", "\(q.starCount.from.map(String.init) ?? "—") → \(q.starCount.to.map(String.init) ?? "—")") : nil,
                Self.meaningfulChange(q.fwhm.from, q.fwhm.to, threshold: 0.005) ?
                    ("FWHM", String(format: "%.2f → %.2f px", q.fwhm.from!, q.fwhm.to!)) : nil,
                Self.meaningfulChange(q.eccentricity.from, q.eccentricity.to, threshold: 0.005) ?
                    ("Eccentricity", String(format: "%.3f → %.3f", q.eccentricity.from!, q.eccentricity.to!)) : nil,
                Self.meaningfulChange(q.backgroundNoise.from, q.backgroundNoise.to, threshold: 0.01) ?
                    ("Background", String(format: "%.1f → %.1f", q.backgroundNoise.from!, q.backgroundNoise.to!)) : nil
            ].compactMap { $0 }
            if !qualityRows.isEmpty {
                popoverSection("Quality")
                ForEach(qualityRows, id: \.0) { label, value in
                    popoverRow(label: label, value: value)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 260)
    }

    private func popoverSection(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func popoverRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }
}

private struct ProvenanceLinkRow: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Button(action: action) {
                HStack(spacing: 3) {
                    Text(value)
                    Image(systemName: "arrow.right.circle")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

private func infoPanelFormatSnakeCase(_ s: String) -> String {
    s.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
}
