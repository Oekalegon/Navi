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
import AstrophotoToolsKit
import Metal
import OSLog
import Observation

@MainActor
@Observable
final class ArchiveManager {
    static let shared = ArchiveManager()

    var isConnected = false
    var errorMessage: String?

    private var archive: Archive?
    private var archiveBookmarkURL: URL?
    private let logger = Logger(subsystem: "com.navi.app", category: "Archive")
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

    // MARK: - Typed archive accessors

    func frames(matching query: FrameQuery) async throws -> [ArchivedFrame] {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.frames(matching: query)
    }

    func members(inFrameSet id: UUID) async throws -> [FrameSetMember] {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.members(inFrameSet: id)
    }

    func frames(inSession id: UUID) async throws -> [ArchivedFrame] {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.frames(inSession: id)
    }

    func frameSets(matching query: FrameSetQuery) async throws -> [ArchivedFrameSet] {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.frameSets(matching: query)
    }

    func recentActivity(limit: Int?) async throws -> [RecentEntry] {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.recentActivity(limit: limit)
    }

    func listObjects() async throws -> [(name: String, count: Int)] {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.listObjects()
    }

    func session(id: UUID) async throws -> ObservingSession? {
        guard let archive else { throw ArchiveManagerError.notConnected }
        return try await archive.session(id: id)
    }

    // MARK: - Tools exposed to Claude (string-based dispatch for AI use)

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let archive else { throw ArchiveManagerError.notConnected }
        switch name {
        // Shared archive tools via AstrophotoToolsKit.
        case let n where n.hasPrefix("archive_"):
            let result = try await ArchiveToolHandler(archive: archive).call(name: name, arguments: arguments)
            if name == "archive_remove" { Task { await self.refreshDiskUsage() } }
            if name == "archive_add"    { importVersion += 1 }
            return result
        // Pipeline tools.
        case "list_pipelines":   return listPipelines()
        case "inspect_pipeline": return try inspectPipeline(arguments)
        case "run_pipeline":     return try await runPipeline(arguments, archive: archive)
        default: throw ArchiveManagerError.unknownTool(name)
        }
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
