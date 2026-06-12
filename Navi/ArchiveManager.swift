//
//  ArchiveManager.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import AstrophotoArchiveKit
import AstrophotoKit
import AstrophotoToolDefinitions
import Metal
import OSLog
import Observation
import TabularData

@MainActor
@Observable
final class ArchiveManager {
    static let shared = ArchiveManager()

    var isConnected = false
    var errorMessage: String?

    private var archive: Archive?
    private var archiveBookmarkURL: URL?
    private let logger = Logger(subsystem: "com.navi.app", category: "Archive")
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let tableDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private let tableTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // Collapses the second date when the range falls within a single (UTC) day:
    // "2026-06-10 21:30 – 23:45" instead of "2026-06-10 21:30 – 2026-06-10 23:45".
    private func tableDateRange(from beg: Date, to end: Date) -> String {
        let (from, to) = beg <= end ? (beg, end) : (end, beg)
        if from == to { return tableDate.string(from: from) }
        let suffix = utcCalendar.isDate(from, inSameDayAs: to)
            ? tableTime.string(from: to)
            : tableDate.string(from: to)
        return tableDate.string(from: from) + " – " + suffix
    }

    private init() {}

    // MARK: - Connection

    // MARK: - Import

    private(set) var importVersion: Int = 0

    func importFITS(urls: [URL]) async -> FITSImportResult {
        guard let archive else { return FITSImportResult(added: 0, skipped: 0, failed: 0) }
        let fitsExtensions: Set<String> = ["fits", "fit", "fts"]
        let fm = FileManager.default
        var fitsFiles: [URL] = []

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
                for case let fileURL as URL in enumerator {
                    if fitsExtensions.contains(fileURL.pathExtension.lowercased()) {
                        fitsFiles.append(fileURL)
                    }
                }
            } else if fitsExtensions.contains(url.pathExtension.lowercased()) {
                fitsFiles.append(url)
            }
        }

        var added = 0, skipped = 0, failed = 0
        for url in fitsFiles {
            do {
                let (_, isNew) = try await archive.add(fitsFile: url)
                if isNew { added += 1 } else { skipped += 1 }
            } catch {
                failed += 1
                logger.error("Import failed for \(url.lastPathComponent): \(error)")
            }
        }
        importVersion += 1
        return FITSImportResult(added: added, skipped: skipped, failed: failed)
    }

    // MARK: - Connection

    func connect(archivePath: String) async {
        disconnect()
        guard !archivePath.isEmpty else {
            errorMessage = "Archive path not configured. Set it in Settings."
            return
        }

        // Restore sandbox access for the archive directory via its security-scoped bookmark.
        if let url = SettingsManager.shared.loadArchiveBookmark() {
            archiveBookmarkURL = url
            archiveBookmarkURL?.startAccessingSecurityScopedResource()
            logger.info("Archive security scope started: \(url.path)")
        }

        do {
            let config = ArchiveConfiguration(rootURL: URL(fileURLWithPath: archivePath))
            archive = try Archive(configuration: config)
            isConnected = true
            errorMessage = nil
            logger.info("Archive connected at: \(archivePath)")
        } catch {
            logger.error("Archive connection error: \(error.localizedDescription)")
            isConnected = false
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        archive = nil
        isConnected = false
        diskUsage = nil
        archiveBookmarkURL?.stopAccessingSecurityScopedResource()
        archiveBookmarkURL = nil
    }

    // MARK: - Disk usage

    // Formatted archive disk usage for the archive pane status bar (NAVI-25).
    // Cached because statistics() walks the archive directory to sum file sizes.
    private(set) var diskUsage: (used: String, available: String)?
    private var isRefreshingDiskUsage = false

    func refreshDiskUsage() async {
        guard !isRefreshingDiskUsage else { return }
        isRefreshingDiskUsage = true
        defer { isRefreshingDiskUsage = false }
        guard let archive, let stats = try? await archive.statistics() else {
            diskUsage = nil
            return
        }
        diskUsage = (used: stats.usedBytesFormatted, available: stats.availableBytesFormatted)
    }

    // MARK: - Tools exposed to Claude

    var availableTools: [[String: Any]] { ArchiveToolDefinitions.all + PipelineToolDefinitions.all }

    func frameTypeInfo(filePath: String) async -> (type: String, level: String)? {
        guard let frame = try? await archive?.frame(filePath: filePath) else { return nil }
        return (frame.frameType, frame.processingLevel.rawValue)
    }

    func isFrameRejected(filePath: String) async -> Bool? {
        return await archivedFrame(filePath: filePath)?.rejected
    }

    func archivedFrame(filePath: String) async -> ArchivedFrame? {
        do {
            return try await archive?.frame(filePath: filePath)
        } catch {
            logger.error("Failed to fetch archived frame at \(filePath): \(error)")
            return nil
        }
    }

    func updateStretchSettings(
        _ settings: StretchSettings?,
        sliderBlackNorm: Float,
        sliderWhiteNorm: Float,
        id: UUID
    ) async throws {
        guard let archive else { throw ArchiveManagerError.notConnected }
        try await archive.updateStretchSettings(
            settings,
            sliderBlackNorm: sliderBlackNorm,
            sliderWhiteNorm: sliderWhiteNorm,
            id: id
        )
    }

    func setRejected(_ rejected: Bool, id: UUID) async throws {
        guard let archive else { throw ArchiveManagerError.notConnected }
        if rejected {
            try await archive.reject(id: id, reason: nil)
        } else {
            try await archive.unreject(id: id)
        }
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await dispatch(name: name, arguments: arguments, archive: archive)
    }

    // MARK: - Dispatch

    private func dispatch(name: String, arguments: [String: Any], archive: Archive) async throws -> String {
        switch name {
        case "archive_add":                 return try await archiveAdd(arguments, archive: archive)
        case "archive_search":              return try await archiveSearch(arguments, archive: archive)
        case "archive_get":                 return try await archiveGet(arguments, archive: archive)
        case "archive_recent":              return try await archiveRecent(arguments, archive: archive)
        case "archive_list_objects":        return try await archiveListObjects(archive: archive)
        case "archive_stats":               return try await archiveStats(archive: archive)
        case "archive_reject":              return try await archiveReject(arguments, archive: archive)
        case "archive_update_quality":      return try await archiveUpdateQuality(arguments, archive: archive)
        case "archive_remove":              return try await archiveRemove(arguments, archive: archive)
        case "archive_frameset_list":       return try await archiveFramesetList(arguments, archive: archive)
        case "archive_frameset_get":        return try await archiveFramesetGet(arguments, archive: archive)
        case "archive_frameset_inspect":    return try await archiveFramesetInspect(arguments, archive: archive)
        case "archive_frameset_quality":    return try await archiveFramesetQuality(arguments, archive: archive)
        case "archive_frameset_create":     return try await archiveFramesetCreate(arguments, archive: archive)
        case "archive_frameset_delete":     return try await archiveFramesetDelete(arguments, archive: archive)
        case "archive_frameset_exclude":    return try await archiveFramesetExclude(arguments, archive: archive)
        case "list_pipelines":              return listPipelines()
        case "inspect_pipeline":            return try inspectPipeline(arguments)
        case "run_pipeline":                return try await runPipeline(arguments, archive: archive)
        default: throw ArchiveManagerError.unknownTool(name)
        }
    }

    // MARK: - Frame tools

    private func archiveAdd(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let path = args["path"] as? String else {
            throw ArchiveManagerError.missingArgument("path")
        }
        let expanded = (path as NSString).expandingTildeInPath
        let recursive = args["recursive"] as? Bool ?? false
        let fitsExtensions: Set<String> = ["fits", "fit", "fts"]
        let fm = FileManager.default

        var fitsFiles: [URL] = []
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else {
            throw ArchiveManagerError.missingArgument("path not found: \(path)")
        }
        if isDir.boolValue {
            let options: FileManager.DirectoryEnumerationOptions = recursive ? [] : [.skipsSubdirectoryDescendants]
            guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: expanded),
                                                  includingPropertiesForKeys: nil,
                                                  options: options) else {
                throw ArchiveManagerError.missingArgument("Cannot enumerate directory: \(path)")
            }
            for case let fileURL as URL in enumerator {
                if fitsExtensions.contains(fileURL.pathExtension.lowercased()) { fitsFiles.append(fileURL) }
            }
        } else if fitsExtensions.contains((expanded as NSString).pathExtension.lowercased()) {
            fitsFiles.append(URL(fileURLWithPath: expanded))
        }
        guard !fitsFiles.isEmpty else { return "No FITS files found at \(path)." }

        var added = 0, skipped = 0, failed = 0
        for url in fitsFiles {
            do {
                let (_, isNew) = try await archive.add(fitsFile: url)
                if isNew { added += 1 } else { skipped += 1 }
            } catch {
                failed += 1
                logger.error("archive_add failed for \(url.lastPathComponent): \(error)")
            }
        }
        importVersion += 1
        var parts: [String] = []
        if added > 0   { parts.append("\(added) added") }
        if skipped > 0 { parts.append("\(skipped) already in archive") }
        if failed > 0  { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ") + "."
    }

    private func archiveSearch(_ args: [String: Any], archive: Archive) async throws -> String {
        let kind = args["kind"] as? String ?? "frames"
        var results: [[String: Any]] = []

        if kind == "frames" || kind == "both" {
            var q = FrameQuery()
            q.objectName = args["object_name"] as? String
            q.filters = args["filters"] as? [String]
            if let t = args["frame_types"] as? [String] { q.frameTypes = t }
            if let l = args["processing_level"] as? String { q.processingLevel = ProcessingLevel(rawValue: l) }
            if let n = args["limit"] as? Int { q.limit = n }
            if let s = args["stacked"] as? Bool { q.stacked = s }
            results += try await archive.frames(matching: q).map { frameDict($0) }
        }

        if kind == "framesets" || kind == "both" {
            var q = FrameSetQuery()
            q.objectName = args["object_name"] as? String
            if let t = args["frame_types"] as? [String] { q.frameTypes = t }
            if let f = args["filters"] as? [String] { q.filters = f }
            if let l = args["processing_level"] as? String { q.processingLevel = ProcessingLevel(rawValue: l) }
            results += try await archive.frameSets(matching: q).map { frameSetDict($0) }
        }

        return try encodeJSON(results)
    }

    private func archiveGet(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        if let frame = try await archive.frame(id: uuid) {
            return try encodeJSON(frameDict(frame))
        }
        if let fs = try await archive.frameSet(id: uuid) {
            return try encodeJSON(frameSetDict(fs))
        }
        return "No frame or frameset found with id \(idStr)."
    }

    private func archiveRecent(_ args: [String: Any], archive: Archive) async throws -> String {
        let limit = args["limit"] as? Int ?? 15
        let frames = try await archive.recentFrames(limit: limit, rejectionFilter: .includeAll)
        return try encodeJSON(frames.map { frameDict($0) })
    }

    private func archiveListObjects(archive: Archive) async throws -> String {
        let objects = try await archive.listObjects()
        return try encodeJSON(objects.map { ["name": $0.name, "count": $0.count] as [String: Any] })
    }

    private func archiveStats(archive: Archive) async throws -> String {
        let s = try await archive.statistics()
        var dict: [String: Any] = [
            "objects": s.objectCount,
            "frames": s.frameCount,
            "used": s.usedBytesFormatted,
            "available": s.availableBytesFormatted
        ]
        if !s.frameCountByType.isEmpty { dict["by_type"] = s.frameCountByType }
        return try encodeJSON(dict)
    }

    private func archiveReject(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        try await archive.reject(id: uuid, reason: args["reason"] as? String)
        return "Frame \(idStr) marked as rejected."
    }

    private func archiveUpdateQuality(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        try await archive.updateFrameQuality(
            id: uuid,
            starCount: args["star_count"] as? Int,
            medianFWHM: args["median_fwhm"] as? Double,
            backgroundNoise: args["background_noise"] as? Double,
            medianEccentricity: args["median_eccentricity"] as? Double
        )
        return "Quality updated for frame \(idStr)."
    }

    private func archiveRemove(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        try await archive.remove(id: uuid, deleteFile: args["delete_file"] as? Bool ?? false)
        Task { await self.refreshDiskUsage() }
        return "Frame \(idStr) removed."
    }

    // MARK: - Frameset tools

    private func archiveFramesetList(_ args: [String: Any], archive: Archive) async throws -> String {
        var q = FrameSetQuery()
        q.objectName = args["object_name"] as? String
        q.name = args["name"] as? String
        if let t = args["frame_types"] as? [String] { q.frameTypes = t }
        if let f = args["filters"] as? [String] { q.filters = f }
        if let l = args["processing_level"] as? String { q.processingLevel = ProcessingLevel(rawValue: l) }
        let sets = try await archive.frameSets(matching: q)
        return try encodeJSON(sets.map { frameSetDict($0) })
    }

    private func archiveFramesetGet(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        let frames = try await archive.frames(inFrameSet: uuid)
        return try encodeJSON(frames.map { frameDict($0) })
    }

    private func archiveFramesetInspect(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        guard let fs = try await archive.frameSet(id: uuid) else {
            return "No frameset found with id \(idStr)."
        }
        let members = try await archive.members(inFrameSet: uuid)
        let activeCount = members.filter { !$0.excluded }.count
        var dict: [String: Any] = [
            "id": fs.id.uuidString,
            "name": fs.name,
            "type": fs.frameType,
            "level": fs.processingLevel.rawValue,
            "total_frames": fs.frameCount,
            "active_frames": activeCount,
            "excluded_frames": fs.excludedFrameCount
        ]
        if let v = fs.objectName  { dict["object"] = v }
        if let v = fs.filter      { dict["filter"] = v }
        if let v = fs.medianFWHM  { dict["median_fwhm"] = v }
        if let v = fs.medianStarCount { dict["median_stars"] = v }
        return try encodeJSON(dict)
    }

    private func archiveFramesetQuality(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        let members = try await archive.members(inFrameSet: uuid)
        let dicts: [[String: Any]] = members.map { m in
            var d: [String: Any] = [
                "id": m.frame.id.uuidString,
                "file": m.frame.filePath,
                "excluded": m.excluded
            ]
            if let v = m.frame.medianFWHM       { d["fwhm"] = v }
            if let v = m.frame.medianFWHMArcsec { d["fwhm_arcsec"] = v }
            if let v = m.frame.starCount         { d["stars"] = v }
            if let v = m.frame.medianEccentricity { d["ecc"] = v }
            if let r = m.excludedReason          { d["excluded_reason"] = r }
            return d
        }
        return try encodeJSON(dicts)
    }

    private func archiveFramesetCreate(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let name = args["name"] as? String, !name.isEmpty else {
            throw ArchiveManagerError.missingArgument("name")
        }
        var q = FrameQuery()
        q.objectName = args["object_name"] as? String
        q.filters = args["filters"] as? [String]
        if let t = args["frame_types"] as? [String] { q.frameTypes = t }
        if let l = args["processing_level"] as? String { q.processingLevel = ProcessingLevel(rawValue: l) }

        let (fs, _) = try await archive.createFrameSet(
            name: name,
            query: q,
            force: args["force"] as? Bool ?? false,
            maxFWHM: args["max_fwhm"] as? Double,
            maxEccentricity: args["max_eccentricity"] as? Double
        )
        return try encodeJSON(frameSetDict(fs))
    }

    private func archiveFramesetDelete(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        try await archive.deleteFrameSet(id: uuid)
        return "Frameset \(idStr) deleted."
    }

    private func archiveFramesetExclude(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let fsIdStr = args["frameset_id"] as? String,
              let fIdStr = args["frame_id"] as? String,
              let fsUUID = UUID(uuidString: fsIdStr),
              let fUUID = UUID(uuidString: fIdStr) else {
            throw ArchiveManagerError.missingArgument("frameset_id or frame_id")
        }
        let exclude = args["exclude"] as? Bool ?? true
        try await archive.setMemberExcluded(frameSetID: fsUUID, frameID: fUUID, excluded: exclude)
        return "Frame \(fIdStr) \(exclude ? "excluded from" : "included in") frameset \(fsIdStr)."
    }

    // MARK: - Encoding helpers

    private func frameDict(_ f: ArchivedFrame) -> [String: Any] {
        var d: [String: Any] = [
            "id": f.id.uuidString,
            "type": f.frameType,
            "level": f.processingLevel.rawValue,
            "file": f.filePath,
            "added": iso.string(from: f.addedAt)
        ]
        if let v = f.objectName          { d["object"] = v }
        if let v = f.filter              { d["filter"] = v }
        if let v = f.camera              { d["camera"] = v }
        if f.stacked, let beg = f.sessionBeg {
            d["date"] = tableDateRange(from: beg, to: f.sessionEnd ?? beg)
        } else if let obsDate = f.timestamp ?? f.fileDate {
            d["date"] = tableDate.string(from: obsDate)
        } else {
            d["date"] = "—"
        }
        if let v = f.exposureTime        { d["exp"] = v }
        if let v = f.starCount           { d["stars"] = v }
        if let v = f.medianFWHM          { d["fwhm"] = v }
        if let v = f.medianFWHMArcsec    { d["fwhm_arcsec"] = v }
        if let v = f.medianEccentricity  { d["ecc"] = v }
        if f.rejected                    { d["rejected"] = "true" }
        return d
    }

    private func frameSetDict(_ fs: ArchivedFrameSet) -> [String: Any] {
        var d: [String: Any] = [
            "id": fs.id.uuidString,
            "name": fs.name,
            "type": fs.frameType,
            "level": fs.processingLevel.rawValue,
            "frames": fs.frameCount,
            "added": iso.string(from: fs.createdAt)
        ]
        if let v = fs.objectName     { d["object"] = v }
        if let v = fs.filter         { d["filter"] = v }
        if let v = fs.camera         { d["camera"] = v }
        if let v = fs.exposureTime   { d["exp"] = v }
        if let from = fs.dateFrom {
            d["date"] = tableDateRange(from: from, to: fs.dateTo ?? from)
        } else {
            d["date"] = tableDate.string(from: fs.createdAt)
        }
        if let v = fs.medianFWHM     { d["fwhm"] = v }
        if let v = fs.medianFWHMArcsec { d["fwhm_arcsec"] = v }
        if let v = fs.medianStarCount { d["stars"] = v }
        return d
    }

    private func encodeJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

}

// MARK: - Pipeline tool definitions and implementations

extension ArchiveManager {

    func listPipelines() -> String {
        let all = PipelineRegistry.shared.getAll()
        guard !all.isEmpty else { return "No pipelines registered." }
        var lines = ["Available pipelines (\(all.count)):"]
        for p in all.values.sorted(by: { $0.id < $1.id }) {
            lines.append("• \(p.id)\(p.description.map { ": \($0)" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    func inspectPipeline(_ args: [String: Any]) throws -> String {
        guard let id = args["pipeline_id"] as? String else {
            throw ArchiveManagerError.missingArgument("pipeline_id")
        }
        guard let pipeline = PipelineRegistry.shared.get(id: id) else {
            throw ArchiveManagerError.missingArgument("Pipeline not found: '\(id)'. Call list_pipelines to see what's available.")
        }
        let inputNames = Array(Set(pipeline.steps.flatMap { step in
            step.dataInputs.compactMap { di in di.from.contains(".") ? nil : di.from }
        })).sorted()
        let paramSpecs: [String: ParameterSpec] = pipeline.steps
            .flatMap { $0.parameters }
            .filter { $0.from != nil }
            .reduce(into: [:]) { acc, spec in if acc[spec.from!] == nil { acc[spec.from!] = spec } }

        var lines = ["Pipeline: \(pipeline.id)", "Name: \(pipeline.name)"]
        if let desc = pipeline.description { lines.append("Description: \(desc)") }
        lines.append("")
        lines.append("Inputs (\(inputNames.count)): \(inputNames.joined(separator: ", "))")
        lines.append("Steps: \(pipeline.steps.count)")
        if !paramSpecs.isEmpty {
            lines.append(""); lines.append("Parameters:")
            for key in paramSpecs.keys.sorted() {
                let spec = paramSpecs[key]!
                let def = spec.defaultValue.map { " [default: \($0.stringValue)]" } ?? " [required]"
                let desc = spec.description.map { " — \($0)" } ?? ""
                lines.append("  \(key)\(def)\(desc)")
            }
        }
        lines.append(""); lines.append("Steps:")
        for step in pipeline.steps {
            lines.append("  \(step.id) — \(step.type)\(step.name.map { " (\($0))" } ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    func runPipeline(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let pipelineID = args["pipeline_id"] as? String, !pipelineID.isEmpty else {
            throw ArchiveManagerError.missingArgument("pipeline_id")
        }
        let outputPath   = args["output_path"]   as? String
        let outputFormat = args["output_format"] as? String ?? "fits"

        guard let pipeline = PipelineRegistry.shared.get(id: pipelineID) else {
            throw ArchiveManagerError.missingArgument("Pipeline not found: '\(pipelineID)'. Call list_pipelines first.")
        }
        let expectedInputs = Array(Set(pipeline.steps.flatMap { step in
            step.dataInputs.compactMap { di in di.from.contains(".") ? nil : di.from }
        }))
        guard let device = AstrophotoKit.makeDefaultDevice() else {
            throw ArchiveManagerError.missingArgument("No Metal GPU device available.")
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw ArchiveManagerError.missingArgument("Failed to create Metal command queue.")
        }

        // Convert params
        let params = args["parameters"] as? [String: Any] ?? [:]
        var parameters: [String: Parameter] = [:]
        for (key, val) in params {
            switch val {
            case let i as Int:    parameters[key] = .int(i)
            case let d as Double: parameters[key] = .double(d)
            case let s as String:
                if let i = Int(s)         { parameters[key] = .int(i) }
                else if let d = Double(s) { parameters[key] = .double(d) }
                else                      { parameters[key] = .string(s) }
            default: parameters[key] = .string("\(val)")
            }
        }

        let inputFrameSetID = args["input_frameset_id"] as? String
        let inputFrameID    = args["input_frame_id"]    as? String
        let inputDir        = args["input_dir"]         as? String
        let inputPaths      = args["input_paths"]       as? [String]
        let inputPath       = args["input_path"]        as? String
        let inputName       = args["input_name"]        as? String

        let resolvedPaths: [String]? = try {
            guard let dir = inputDir else { return nil }
            let expanded = (dir as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
                throw ArchiveManagerError.missingArgument("input_dir not found or is not a directory: \(dir)")
            }
            let extensions = Set(["fits", "fit", "fts"])
            let files = try FileManager.default.contentsOfDirectory(atPath: expanded)
            let fits = files
                .filter { extensions.contains(($0 as NSString).pathExtension.lowercased()) }
                .sorted()
                .map { (expanded as NSString).appendingPathComponent($0) }
            guard !fits.isEmpty else {
                throw ArchiveManagerError.missingArgument("No FITS files found in directory: \(dir)")
            }
            return fits
        }()

        var pipelineInputs: [String: Any] = [:]

        if let frameSetID = inputFrameSetID {
            guard let uuid = UUID(uuidString: frameSetID) else {
                throw ArchiveManagerError.missingArgument("input_frameset_id must be a valid UUID")
            }
            guard try await archive.frameSet(id: uuid) != nil else {
                throw ArchiveManagerError.missingArgument("No frameset with id '\(frameSetID)' found.")
            }
            let archivedFrames = try await archive.frames(inFrameSet: uuid)
            guard !archivedFrames.isEmpty else {
                throw ArchiveManagerError.missingArgument("Frameset '\(frameSetID)' contains no frames.")
            }
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            let topLevelInputType = pipeline.steps.flatMap { $0.dataInputs }
                .first { !$0.from.contains(".") && $0.name == resolvedName }?.type
            if topLevelInputType == .frameSet {
                var frames: [Frame] = []
                for af in archivedFrames {
                    guard FileManager.default.fileExists(atPath: af.filePath) else { continue }
                    let fitsFile = try FITSFile(path: af.filePath)
                    let img = try fitsFile.readFITSImage()
                    frames.append(try Frame(fitsImage: img, device: device, filePath: af.filePath))
                }
                pipelineInputs[resolvedName] = FrameSet(frames: frames, outputProcess: nil, inputProcesses: [])
            } else {
                return try await runPipelinePerFrame(
                    pipelineID: pipelineID, pipeline: pipeline,
                    resolvedInputName: resolvedName, archivedFrames: archivedFrames,
                    parameters: parameters, device: device, commandQueue: commandQueue,
                    archive: archive)
            }
        } else if let frameID = inputFrameID {
            guard let uuid = UUID(uuidString: frameID) else {
                throw ArchiveManagerError.missingArgument("input_frame_id must be a valid UUID")
            }
            guard let af = try await archive.frame(id: uuid) else {
                throw ArchiveManagerError.missingArgument("No frame with id '\(frameID)' found.")
            }
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            let fitsFile = try FITSFile(path: af.filePath)
            let img = try fitsFile.readFITSImage()
            pipelineInputs[resolvedName] = try Frame(fitsImage: img, device: device, filePath: af.filePath)
        } else if let paths = resolvedPaths ?? inputPaths, !paths.isEmpty {
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            var frames: [Frame] = []
            for path in paths {
                let expanded = (path as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: expanded) else {
                    throw ArchiveManagerError.missingArgument("File not found: \(path)")
                }
                let fitsFile = try FITSFile(path: expanded)
                let img = try fitsFile.readFITSImage()
                frames.append(try Frame(fitsImage: img, device: device, filePath: expanded))
            }
            pipelineInputs[resolvedName] = FrameSet(frames: frames, outputProcess: nil, inputProcesses: [])
        } else if let path = inputPath {
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                throw ArchiveManagerError.missingArgument("File not found: \(path)")
            }
            let resolvedName = try resolveInputName(inputName, expectedInputs: expectedInputs, pipelineID: pipelineID)
            let fitsFile = try FITSFile(path: expanded)
            pipelineInputs[resolvedName] = try fitsFile.readFITSImage()
        } else {
            throw ArchiveManagerError.missingArgument(
                "Provide input_frameset_id, input_frame_id, input_path, input_paths, or input_dir for pipeline '\(pipelineID)'."
            )
        }

        let start = Date()
        let runner = PipelineRunner(pipeline: pipeline)
        let outputs = try await runner.execute(inputs: pipelineInputs, parameters: parameters,
                                               device: device, commandQueue: commandQueue)
        let elapsed = Date().timeIntervalSince(start)

        let tables = outputs.compactMap { $0 as? TableData }.filter { $0.isInstantiated }
        let frames = outputs.compactMap { $0 as? Frame }.filter { $0.isInstantiated }

        var savedNote = ""
        if let outPath = outputPath {
            if let firstFrame = frames.first, let firstTable = tables.first,
               let df = firstTable.dataFrame, outputFormat.lowercased() != "csv" {
                guard let texture = firstFrame.texture else {
                    throw ArchiveManagerError.missingArgument("Output frame has no texture data")
                }
                let w = texture.width, h = texture.height
                var pixels = [Float](repeating: 0, count: w * h)
                texture.getBytes(&pixels, bytesPerRow: w * MemoryLayout<Float>.size,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                let stackMethod  = parameters["method"]?.stringValue         ?? "average"
                let stackNorm    = parameters["normalisation"]?.stringValue   ?? "none"
                let stackRej     = parameters["pixel_rejection"]?.stringValue ?? "sigma_clip"
                let stackRejLow  = parameters["rejection_low"]?.doubleValue   ?? 3.0
                let stackRejHigh = parameters["rejection_high"]?.doubleValue  ?? 3.0
                let inputMeta    = unanimousFrameMetadata(from: pipelineInputs)
                try FITSTableWriter.writeStackedOutput(
                    pixelData: pixels, width: w, height: h, registrationTable: df,
                    method: stackMethod, normalisation: stackNorm, rejection: stackRej,
                    rejectionLow: stackRejLow, rejectionHigh: stackRejHigh,
                    objectName: inputMeta.objectName, camera: inputMeta.camera,
                    telescope: inputMeta.telescope, site: inputMeta.site, to: outPath)
                let inputFrameSet = pipelineInputs.values.compactMap { $0 as? FrameSet }.first
                let summary = stackSummaryLine(pixels: pixels, registrationTable: df, inputFrameSet: inputFrameSet)
                savedNote = "\nSaved stacked FITS to \(outPath).\(summary.map { "\n\($0)" } ?? "")"
            } else if let firstTable = tables.first, let df = firstTable.dataFrame {
                let fmt: FITSTableWriter.OutputFormat = (outputFormat.lowercased() == "csv") ? .csv : .fits
                try FITSTableWriter.writeRegistrationTable(df, to: outPath, format: fmt)
                savedNote = "\nSaved table to \(outPath) (\(outputFormat.lowercased()))."
            }
        }

        if !frames.isEmpty {
            if let note = await autoArchiveResults(frames: frames, pipelineID: pipelineID,
                                                   parameters: parameters, pipelineInputs: pipelineInputs,
                                                   existingOutputPath: (outputPath?.hasSuffix(".fits") == true || outputPath?.hasSuffix(".fit") == true) ? outputPath : nil,
                                                   archive: archive) {
                savedNote += "\n\(note)"
            }
        }
        if let note = await backUpdateQuality(tables: tables,
                                              inputFrameID: (args["input_frame_id"] as? String).flatMap { UUID(uuidString: $0) },
                                              inputFilePath: args["input_path"] as? String,
                                              archive: archive) {
            savedNote += "\n\(note)"
        }

        var lines = [
            "Pipeline '\(pipelineID)' completed in \(String(format: "%.2f", elapsed))s.",
            "\(frames.count) frame(s) produced, \(tables.count) table(s) produced.\(savedNote)"
        ]
        for (i, table) in tables.enumerated() {
            guard let df = table.dataFrame else { continue }
            let cols = df.columns.map { $0.name }
            lines.append("")
            lines.append("Table \(i + 1) — \(df.rows.count) rows, columns: \(cols.joined(separator: ", "))")
            for row in df.rows.prefix(50) {
                let entries = cols.compactMap { col -> String? in
                    guard let v = row[col] else { return nil }
                    if let d = v as? Double { return "\(col): \(String(format: "%.4f", d))" }
                    if let f = v as? Float  { return "\(col): \(String(format: "%.4f", f))" }
                    return "\(col): \(v)"
                }
                lines.append("  { \(entries.joined(separator: ", ")) }")
            }
            if df.rows.count > 50 { lines.append("  … \(df.rows.count - 50) more rows omitted.") }
        }
        return lines.joined(separator: "\n")
    }

    private func runPipelinePerFrame(
        pipelineID: String,
        pipeline: Pipeline,
        resolvedInputName: String,
        archivedFrames: [ArchivedFrame],
        parameters: [String: Parameter],
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        archive: Archive
    ) async throws -> String {
        let start = Date()
        var processedCount = 0, errorCount = 0
        var qualityNotes: [String] = []
        for af in archivedFrames {
            guard FileManager.default.fileExists(atPath: af.filePath) else { errorCount += 1; continue }
            do {
                let fitsFile = try FITSFile(path: af.filePath)
                let img = try fitsFile.readFITSImage()
                let frame = try Frame(fitsImage: img, device: device, filePath: af.filePath)
                let runner = PipelineRunner(pipeline: pipeline)
                let outputs = try await runner.execute(inputs: [resolvedInputName: frame],
                                                       parameters: parameters, device: device,
                                                       commandQueue: commandQueue)
                let tables = outputs.compactMap { $0 as? TableData }.filter { $0.isInstantiated }
                if let note = await backUpdateQuality(tables: tables, inputFrameID: af.id,
                                                      inputFilePath: nil, archive: archive) {
                    qualityNotes.append(note)
                }
                processedCount += 1
            } catch { errorCount += 1 }
        }
        let elapsed = Date().timeIntervalSince(start)
        var lines = [
            "Pipeline '\(pipelineID)' completed in \(String(format: "%.2f", elapsed))s.",
            "\(processedCount) frame(s) processed" + (errorCount > 0 ? ", \(errorCount) failed." : ".")
        ]
        if !qualityNotes.isEmpty { lines.append(contentsOf: qualityNotes) }
        return lines.joined(separator: "\n")
    }

    private func autoArchiveResults(
        frames: [Frame],
        pipelineID: String,
        parameters: [String: Parameter],
        pipelineInputs: [String: Any],
        existingOutputPath: String?,
        archive: Archive
    ) async -> String? {
        do {
            var runInputs: [ProcessingRunInputRef] = []
            var objectNamesSet: Set<String> = [], filterNamesSet: Set<String> = []
            var camerasSet: Set<String> = [], telescopesSet: Set<String> = [], sitesSet: Set<String> = []
            var pixelScalesSet: Set<Double> = [], focalLengthsSet: Set<Double> = []
            var totalExposure = 0.0, inputCount = 0
            var gainsSet: Set<Double> = [], offsetsSet: Set<Double> = []
            var temperatures: [Double] = [], timestamps: [Date] = []
            var refRA: Double? = nil, refDec: Double? = nil

            let stackFilter: String?
            for (name, value) in pipelineInputs.sorted(by: { $0.key < $1.key }) {
                let pathsAndFrames: [(String, Frame?)]
                if let fs = value as? FrameSet      { pathsAndFrames = fs.frames.compactMap { f in f.filePath.map { ($0, f) } } }
                else if let f = value as? Frame     { pathsAndFrames = f.filePath.map { [($0, f as Frame?)] } ?? [] }
                else                                { pathsAndFrames = [] }
                for (pos, (path, inputFrame)) in pathsAndFrames.enumerated() {
                    let af = try? await archive.frame(filePath: path)
                    runInputs.append(ProcessingRunInputRef(inputName: name, frameID: af?.id, filePath: path, position: pos))
                    if pos == 0 { refRA = af?.ra; refDec = af?.dec }
                    inputCount += 1
                    if let v = af?.objectName ?? inputFrame?.objectName { objectNamesSet.insert(v) }
                    let fn = af?.filter ?? inputFrame?.filterName; if let fn { filterNamesSet.insert(fn) }
                    let exp = af?.exposureTime ?? inputFrame?.exposureTime; if let exp { totalExposure += exp }
                    if let g = af?.gain ?? inputFrame?.gain { gainsSet.insert(g) }
                    if let o = af?.offset ?? inputFrame?.offset { offsetsSet.insert(o) }
                    if let t = af?.temperature { temperatures.append(t) }
                    if let ts = af?.timestamp ?? inputFrame?.timestamp { timestamps.append(ts) }
                    if let c = af?.camera ?? inputFrame?.camera { camerasSet.insert(c) }
                    if let tl = af?.telescope ?? inputFrame?.telescope { telescopesSet.insert(tl) }
                    if let s = af?.site ?? inputFrame?.site { sitesSet.insert(s) }
                    if let ps = af?.pixelScale { pixelScalesSet.insert(ps) }
                    if let fl = af?.focalLength { focalLengthsSet.insert(fl) }
                }
            }
            let stackObjectName  = objectNamesSet.count  == 1 ? objectNamesSet.first  : nil
            stackFilter          = filterNamesSet.count  == 1 ? filterNamesSet.first  : nil
            let stackCamera      = camerasSet.count      == 1 ? camerasSet.first      : nil
            let stackTelescope   = telescopesSet.count   == 1 ? telescopesSet.first   : nil
            let stackSite        = sitesSet.count        == 1 ? sitesSet.first        : nil
            let stackPixelScale  = pixelScalesSet.count  == 1 ? pixelScalesSet.first  : nil
            let stackFocalLength = focalLengthsSet.count == 1 ? focalLengthsSet.first : nil
            let stackExposure    = inputCount > 0 && totalExposure > 0 ? totalExposure : nil as Double?
            let stackGain        = gainsSet.count   == 1 ? gainsSet.first   : nil
            let stackOffset      = offsetsSet.count == 1 ? offsetsSet.first : nil
            let stackTempMean    = temperatures.isEmpty ? nil : temperatures.reduce(0, +) / Double(temperatures.count) as Double?
            let stackTempMin     = temperatures.isEmpty ? nil : temperatures.min()
            let stackTempMax     = temperatures.isEmpty ? nil : temperatures.max()

            let iso8601 = ISO8601DateFormatter(); iso8601.formatOptions = [.withInternetDateTime]
            let refDate  = timestamps.max().flatMap { iso8601.string(from: $0) }
            let dateBeg  = timestamps.min().flatMap { iso8601.string(from: $0) }
            let dateEnd  = timestamps.max().flatMap { iso8601.string(from: $0) }
            let paramMap = parameters.reduce(into: [String: String]()) { $0[$1.key] = $1.value.stringValue }
            let run      = try await archive.recordProcessingRun(pipelineID: pipelineID, parameters: paramMap, inputs: runInputs)

            var archivedIDs: [String] = []
            for frame in frames {
                guard let texture = frame.texture else { continue }
                let w = texture.width, h = texture.height
                var pixels = [Float](repeating: 0, count: w * h)
                texture.getBytes(&pixels, bytesPerRow: w * MemoryLayout<Float>.size,
                                 from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                let tempURL: URL?
                let fileToArchive: URL
                if let outPath = existingOutputPath, frames.count == 1 {
                    fileToArchive = URL(fileURLWithPath: outPath); tempURL = nil
                } else {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("navi_result_\(UUID().uuidString).fits")
                    try FITSTableWriter.writeResultFrame(
                        pixelData: pixels, width: w, height: h, pipelineID: pipelineID,
                        imageType: "Light Frame", filterName: stackFilter ?? frame.filterName,
                        stacked: pipelineID == "frame_stacking", nframes: inputCount > 0 ? inputCount : nil,
                        totalExposure: stackExposure, gain: stackGain, offset: stackOffset,
                        temperature: stackTempMean, objectName: stackObjectName, camera: stackCamera,
                        telescope: stackTelescope, site: stackSite, ra: refRA, dec: refDec,
                        pixelScale: stackPixelScale, focalLength: stackFocalLength,
                        tempMin: stackTempMin, tempMax: stackTempMax,
                        dateObs: refDate, dateBeg: dateBeg, dateEnd: dateEnd, to: tmp.path)
                    fileToArchive = tmp; tempURL = tmp
                }
                let (archived, _) = try await archive.add(fitsFile: fileToArchive, processingRunID: run.id)
                if let tmp = tempURL { try? FileManager.default.removeItem(at: tmp) }
                archivedIDs.append(archived.id.uuidString)
            }
            importVersion += 1
            if archivedIDs.isEmpty { return "Auto-archive: no frames could be read from GPU texture." }
            return "Archived result frame(s): \(archivedIDs.joined(separator: ", ")) (run: \(run.id))"
        } catch {
            return "Auto-archive failed: \(error.localizedDescription)"
        }
    }

    private func backUpdateQuality(
        tables: [TableData],
        inputFrameID: UUID?,
        inputFilePath: String?,
        archive: Archive
    ) async -> String? {
        let perFrame = ArchiveManager.extractPerFrameQuality(from: tables)
        if !perFrame.isEmpty {
            var notes: [String] = []
            do {
                for entry in perFrame {
                    let expanded = (entry.filePath as NSString).expandingTildeInPath
                    guard let af = try await archive.frame(filePath: expanded) else { continue }
                    try await archive.updateFrameQuality(id: af.id, starCount: entry.starCount,
                                                         medianFWHM: entry.medianFWHM,
                                                         medianEccentricity: entry.medianEccentricity)
                    var parts: [String] = []
                    if let v = entry.starCount          { parts.append("stars: \(v)") }
                    if let v = entry.medianFWHM         { parts.append(String(format: "FWHM: %.2fpx", v)) }
                    if let v = entry.medianEccentricity { parts.append(String(format: "ecc: %.3f", v)) }
                    if !parts.isEmpty { notes.append("\(af.id): \(parts.joined(separator: ", "))") }
                }
            } catch { return "Quality update failed: \(error.localizedDescription)" }
            return notes.isEmpty ? nil : "Quality metrics stored on \(notes.count) frame(s)."
        }
        let metrics = ArchiveManager.extractGlobalQuality(from: tables)
        guard metrics.starCount != nil || metrics.medianFWHM != nil || metrics.backgroundNoise != nil
                || metrics.medianEccentricity != nil || metrics.saturatedStarCount != nil
                || metrics.hotPixelCount != nil else { return nil }
        do {
            let targetID: UUID?
            if let id = inputFrameID { targetID = id }
            else if let path = inputFilePath {
                targetID = try await archive.frame(filePath: (path as NSString).expandingTildeInPath)?.id
            } else { targetID = nil }
            guard let id = targetID else { return nil }
            try await archive.updateFrameQuality(id: id, starCount: metrics.starCount,
                                                  medianFWHM: metrics.medianFWHM,
                                                  backgroundNoise: metrics.backgroundNoise,
                                                  medianEccentricity: metrics.medianEccentricity,
                                                  saturatedStarCount: metrics.saturatedStarCount,
                                                  hotPixelCount: metrics.hotPixelCount)
            var parts: [String] = []
            if let v = metrics.starCount          { parts.append("stars: \(v)") }
            if let v = metrics.saturatedStarCount { parts.append("sat: \(v)") }
            if let v = metrics.medianFWHM         { parts.append(String(format: "FWHM: %.2fpx", v)) }
            if let v = metrics.backgroundNoise    { parts.append(String(format: "bg: %.4f", v)) }
            if let v = metrics.medianEccentricity { parts.append(String(format: "ecc: %.3f", v)) }
            if let v = metrics.hotPixelCount      { parts.append("hot_px: \(v)") }
            return "Quality metrics stored on frame \(id): \(parts.joined(separator: ", "))."
        } catch { return "Quality update failed: \(error.localizedDescription)" }
    }

    static func extractPerFrameQuality(from tables: [TableData])
        -> [(filePath: String, starCount: Int?, medianFWHM: Double?, medianEccentricity: Double?)]
    {
        for table in tables {
            guard let df = table.dataFrame else { continue }
            let colNames = Set(df.columns.map { $0.name })
            guard colNames.contains("file_path"), colNames.contains("median_fwhm"),
                  colNames.contains("star_count") else { continue }
            return df.rows.compactMap { row -> (String, Int?, Double?, Double?)? in
                guard let path = row["file_path"] as? String, !path.isEmpty else { return nil }
                let starCount: Int? = (row["star_count"] as? Int32).map { Int($0) } ?? (row["star_count"] as? Int)
                return (path, starCount, row["median_fwhm"] as? Double, row["mean_eccentricity"] as? Double)
            }
        }
        return []
    }

    static func extractGlobalQuality(from tables: [TableData])
        -> (starCount: Int?, medianFWHM: Double?, backgroundNoise: Double?,
            backgroundNoiseIsADU: Bool, medianEccentricity: Double?,
            saturatedStarCount: Int?, hotPixelCount: Int?)
    {
        var starCount: Int? = nil, medianFWHM: Double? = nil, backgroundNoise: Double? = nil
        var backgroundNoiseIsADU = false, medianEccentricity: Double? = nil
        var saturatedStarCount: Int? = nil, hotPixelCount: Int? = nil
        for table in tables {
            guard let df = table.dataFrame else { continue }
            let colNames = Set(df.columns.map { $0.name })
            if colNames.contains("star_count") && colNames.contains("saturated_star_count"),
               let row = df.rows.first {
                if let v = row["star_count"]           as? Int  { starCount = v }
                if let v = row["saturated_star_count"] as? Int  { saturatedStarCount = v }
                if let v = row["median_fwhm"]          as? Double, v > 0 { medianFWHM = v }
                if let v = row["median_eccentricity"]  as? Double { medianEccentricity = v }
                if colNames.contains("background_level_adu"), let v = row["background_level_adu"] as? Double {
                    backgroundNoise = v; backgroundNoiseIsADU = true
                } else if let v = row["background_level"] as? Double { backgroundNoise = v }
            }
            if colNames.contains("noise_sigma") && colNames.contains("hot_pixel_count"),
               let row = df.rows.first {
                if let v = row["hot_pixel_count"] as? Int { hotPixelCount = v }
                if colNames.contains("noise_sigma_adu"), let v = row["noise_sigma_adu"] as? Double {
                    backgroundNoise = v; backgroundNoiseIsADU = true
                } else if let v = row["noise_sigma"] as? Double { backgroundNoise = v }
            }
            if colNames.contains("centroid_x") && colNames.contains("centroid_y") {
                if starCount == nil { starCount = df.rows.count }
                if medianEccentricity == nil {
                    let eccs = df.rows.compactMap { $0["eccentricity"] as? Double }.filter { !$0.isNaN }
                    if !eccs.isEmpty { medianEccentricity = eccs.reduce(0, +) / Double(eccs.count) }
                }
            }
            if colNames.contains("sigma_clipped_mean_fwhm_major"),
               colNames.contains("sigma_clipped_mean_fwhm_minor"),
               let row = df.rows.first,
               let major = row["sigma_clipped_mean_fwhm_major"] as? Double,
               let minor = row["sigma_clipped_mean_fwhm_minor"] as? Double,
               major > 0, medianFWHM == nil { medianFWHM = (major + minor) / 2.0 }
            if colNames.contains("background_level"), !colNames.contains("star_count"),
               let row = df.rows.first, backgroundNoise == nil {
                if colNames.contains("background_level_adu"), let v = row["background_level_adu"] as? Double {
                    backgroundNoise = v; backgroundNoiseIsADU = true
                } else if let v = row["background_level"] as? Double { backgroundNoise = v }
            }
            if colNames.contains("global_mean_eccentricity"), let row = df.rows.first,
               let ecc = row["global_mean_eccentricity"] as? Double, medianEccentricity == nil {
                medianEccentricity = ecc
            }
        }
        return (starCount, medianFWHM, backgroundNoise, backgroundNoiseIsADU, medianEccentricity, saturatedStarCount, hotPixelCount)
    }

    private func unanimousFrameMetadata(from inputs: [String: Any])
        -> (objectName: String?, camera: String?, telescope: String?, site: String?)
    {
        var objNames = Set<String>(), cams = Set<String>(), scopes = Set<String>(), sites = Set<String>()
        for value in inputs.values {
            let fs: [Frame]
            if let s = value as? FrameSet { fs = s.frames }
            else if let f = value as? Frame { fs = [f] }
            else { continue }
            for f in fs {
                if let v = f.objectName { objNames.insert(v) }
                if let v = f.camera     { cams.insert(v) }
                if let v = f.telescope  { scopes.insert(v) }
                if let v = f.site       { sites.insert(v) }
            }
        }
        return (objNames.count == 1 ? objNames.first : nil, cams.count == 1 ? cams.first : nil,
                scopes.count == 1 ? scopes.first : nil, sites.count == 1 ? sites.first : nil)
    }

    private func stackSummaryLine(pixels: [Float], registrationTable df: DataFrame, inputFrameSet: FrameSet?) -> String? {
        let skyNoises = df.rows.compactMap { $0["sky_noise"] as? Double }.filter { !$0.isNaN && $0 > 0 }
        guard !skyNoises.isEmpty else { return nil }
        let mean = skyNoises.reduce(0, +) / Double(skyNoises.count)
        return "Mean sky noise: \(String(format: "%.2f", mean)) ADU."
    }

    private func resolveInputName(_ name: String?, expectedInputs: [String], pipelineID: String) throws -> String {
        if let n = name { return n }
        if expectedInputs.count == 1 { return expectedInputs[0] }
        throw ArchiveManagerError.missingArgument(
            "Pipeline '\(pipelineID)' has multiple inputs: \(expectedInputs.sorted().joined(separator: ", ")). Specify input_name."
        )
    }
}

struct FITSImportResult {
    let added: Int
    let skipped: Int
    let failed: Int

    var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) \(added == 1 ? "frame" : "frames") added") }
        if skipped > 0 { parts.append("\(skipped) already in archive") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.isEmpty ? "No FITS files found" : parts.joined(separator: ", ")
    }
}

enum ArchiveManagerError: LocalizedError {
    case notConnected
    case missingArgument(String)
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Archive is not connected. Configure the Archive Path in Settings."
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        }
    }
}
