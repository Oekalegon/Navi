//
//  AstroKitMCPManager.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import OSLog
import Observation

@Observable
class AstroKitMCPManager {
    static let shared = AstroKitMCPManager()

    var isConnected = false
    var errorMessage: String?
    var availableTools: [[String: Any]] = []

    private var mcpClient: MCPClient?
    private let logger = Logger(subsystem: "com.navi.app", category: "MCP")
    private var mcpURL: URL?
    private var archiveURL: URL?

    private init() {}

    func connect(mcpPath: String, archivePath: String? = nil) async {
        logger.info("Connecting to MCP at path: \(mcpPath)")

        let settings = SettingsManager.shared

        if let bookmark = settings.loadMCPBookmark() {
            self.mcpURL = bookmark
            logger.info("Using security-scoped MCP bookmark: \(bookmark.path)")
        }

        if let bookmark = settings.loadArchiveBookmark() {
            self.archiveURL = bookmark
        }

        let mcpAccessing = self.mcpURL?.startAccessingSecurityScopedResource() ?? false
        let archiveAccessing = self.archiveURL?.startAccessingSecurityScopedResource() ?? false
        logger.info("MCP resource access started: \(mcpAccessing), Archive access started: \(archiveAccessing)")

        do {
            var env: [String: String] = [:]
            if let archivePath = archivePath {
                env["ASTROARCHIVE_PATH"] = archivePath
                logger.info("Setting ASTROARCHIVE_PATH to: \(archivePath)")
            }

            let executablePath = mcpURL?.path ?? mcpPath
            logger.info("Using executable path: \(executablePath)")

            mcpClient = MCPClient(executablePath: executablePath, environment: env, arguments: ["stdio"])
            try mcpClient?.start()
            logger.info("MCP process started")

            logger.info("Sending initialize request...")
            let initResponse = try await mcpClient?.sendRequest(method: "initialize", params: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]]
            ])
            logger.info("Initialize response received: \(String(describing: initResponse))")

            let toolsResponse = try await mcpClient?.sendRequest(method: "tools/list")
            logger.debug("Tools list response received")

            if let tools = toolsResponse?["tools"] as? [[String: Any]] {
                logger.info("Found \(tools.count) MCP tools")
                await MainActor.run {
                    self.availableTools = tools
                    self.isConnected = true
                    self.errorMessage = nil
                }
            } else {
                logger.error("No tools array found in MCP response")
                await MainActor.run { self.errorMessage = "No tools found in MCP response" }
            }
        } catch {
            logger.error("MCP connection error: \(error.localizedDescription)")
            await MainActor.run {
                self.isConnected = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func callTool(name: String, arguments: [String: Any] = [:]) async throws -> [String: Any] {
        guard let mcpClient = mcpClient else { throw MCPClientError.processNotRunning }
        return try await mcpClient.sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
    }

    func disconnect() {
        mcpClient?.stop()
        mcpClient = nil
        isConnected = false

        mcpURL?.stopAccessingSecurityScopedResource()
        mcpURL = nil
        archiveURL?.stopAccessingSecurityScopedResource()
        archiveURL = nil
    }

    deinit { disconnect() }
}
