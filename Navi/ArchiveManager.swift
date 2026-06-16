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

    var importVersion: Int = 0

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
            let scopeGranted = url.startAccessingSecurityScopedResource()
            if scopeGranted {
                logger.info("Archive security scope started: \(url.path)")
            } else {
                logger.warning("Security scope access denied for archive bookmark — bookmark may be stale: \(url.path)")
            }
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

    // Archive disk usage for the archive pane status bar (NAVI-25).
    // Cached because statistics() walks the archive directory to sum file sizes.
    struct DiskUsage {
        var archiveBytes: Int64
        var availableBytes: Int64
        var totalBytes: Int64
        var frameCount: Int
        // Space taken by everything else on the volume holding the archive.
        var otherBytes: Int64 { max(0, totalBytes - availableBytes - archiveBytes) }
    }

    private(set) var diskUsage: DiskUsage?
    private var isRefreshingDiskUsage = false

    func refreshDiskUsage() async {
        guard !isRefreshingDiskUsage else { return }
        isRefreshingDiskUsage = true
        defer { isRefreshingDiskUsage = false }
        guard let archive, let stats = try? await archive.statistics() else {
            diskUsage = nil
            return
        }
        diskUsage = DiskUsage(
            archiveBytes: stats.usedBytes,
            availableBytes: stats.availableBytes,
            totalBytes: stats.totalBytes,
            frameCount: stats.frameCount
        )
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

    func pipelineDefaultParameters(id: String) -> [String: String] {
        guard let pipeline = PipelineRegistry.shared.get(id: id) else { return [:] }
        let paramSpecs: [String: ParameterSpec] = pipeline.steps
            .flatMap { $0.parameters }
            .filter { $0.from != nil }
            .reduce(into: [:]) { acc, spec in if acc[spec.from!] == nil { acc[spec.from!] = spec } }
        return paramSpecs.compactMapValues { $0.defaultValue?.stringValue }
    }

    func processingRun(for frame: ArchivedFrame) async -> (run: ArchivedProcessingRun, inputs: [ProcessingRunInputRef])? {
        do {
            return try await archive?.processingRun(for: frame)
        } catch {
            logger.error("Failed to fetch processing run for frame \(frame.id): \(error)")
            return nil
        }
    }

    func frameSetIDs(forFrame frameID: UUID) async -> [UUID] {
        do {
            return try await archive?.frameSetIDs(forFrame: frameID) ?? []
        } catch {
            logger.error("Failed to fetch frameset IDs for frame \(frameID): \(error)")
            return []
        }
    }

    func frameDiff(_ frame: ArchivedFrame, predecessor: ArchivedFrame) async -> FrameDiff? {
        do {
            guard let archive else { return nil }
            return try await archive.diff(frame, predecessor: predecessor)
        } catch {
            logger.error("Failed to compute frame diff: \(error)")
            return nil
        }
    }

    func fullVersionChain(for frame: ArchivedFrame) async -> [ArchivedFrame] {
        do {
            guard let archive else { return [frame] }
            var head = frame
            var visited = Set<UUID>([frame.id])
            while true {
                let nexts = try await archive.successors(of: head)
                guard let next = nexts.first, !visited.contains(next.id) else { break }
                visited.insert(next.id)
                head = next
            }
            return try await archive.lineage(of: head)
        } catch {
            return [frame]
        }
    }

    func frameSet(id: UUID) async -> ArchivedFrameSet? {
        do {
            return try await archive?.frameSet(id: id)
        } catch {
            logger.error("Failed to fetch frameset \(id): \(error)")
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
        case "archive_session_get":         return try await archiveSessionGet(arguments, archive: archive)
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
        // The tool contract uses 0 or negative for "all frames"; the kit API expresses that as nil.
        let limit = args["limit"] as? Int ?? 15
        let frames = try await archive.recentFrames(limit: limit > 0 ? limit : nil, rejectionFilter: .includeAll)
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

    private func archiveSessionGet(_ args: [String: Any], archive: Archive) async throws -> String {
        guard let idStr = args["id"] as? String, let uuid = UUID(uuidString: idStr) else {
            throw ArchiveManagerError.missingArgument("id")
        }
        guard let session = try await archive.session(id: uuid) else {
            throw ArchiveManagerError.missingArgument("No session found with id \(idStr)")
        }
        let sortDate = session.startTime ?? session.date
        return try encodeJSON([
            "id": session.id.uuidString,
            "name": session.name,
            "is_night": session.isNight,
            "frame_count": session.frameCount,
            "sort_date": tableDate.string(from: sortDate)
        ] as [String: Any])
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
        if let sid = f.sessionID { d["session_id"] = sid.uuidString }
        if f.stacked, let beg = f.sessionBeg {
            d["date"] = tableDateRange(from: beg, to: f.sessionEnd ?? beg)
        } else if let obsDate = f.timestamp ?? f.fileDate {
            d["date"] = tableDate.string(from: obsDate)
        } else {
            d["date"] = "—"
        }
        if let v = f.exposureTime        { d["exp"] = v }
        if let v = f.temperature         { d["temp"] = v }
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
