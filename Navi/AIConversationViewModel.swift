//
//  AIConversationViewModel.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import OSLog
import Observation

@MainActor
@Observable
class AIConversationViewModel {
    private let logger = Logger(subsystem: "com.navi.app", category: "AI")

    var messages: [Message] = []
    private var apiConversation: [[String: Any]] = []
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var toolCallStatus: String?

    var claudeService: ClaudeService
    var selectedModel: ClaudeModel {
        get { claudeService.selectedModel }
        set { claudeService.selectedModel = newValue }
    }

    var paneManager: PaneManager?

    private let archiveManager = ArchiveManager.shared
    private let maxToolRounds = 10

    // MARK: - System prompt

    private let systemPrompt = """
        You are an AI astrophotography assistant running inside Navi, a macOS app for managing \
        astrophotography archives and viewing astronomical images.

        The app has three panels:
        - AI Assistant (this panel): your chat interface with the user
        - Archive Browser: displays archive query results as a sortable table
        - FITS Viewer: renders FITS astronomical images with adjustable stretch controls

        The archive stores individual frames and framesets. Each frame has:
        - type: light (science frames), dark, flat, bias
        - level: raw or stacked (stacked = master calibration frame or integrated light stack)
        - file: absolute path to the FITS file on disk (pass this directly to open_fits_viewer)

        You have access to AstroKit archive tools to search and manage the archive. \
        You also have the open_fits_viewer tool to display any FITS file in the viewer panel. \
        When the user asks to view, open, display, or inspect a FITS file or image, use \
        open_fits_viewer. If you don't have the file path yet, query the archive first \
        (e.g. archive_search, archive_get) to retrieve it, then open it.
        """

    // MARK: - Local tools

    private let localTools: [[String: Any]] = [
        [
            "name": "open_fits_viewer",
            "description": "Opens a FITS image file in the app's built-in FITS viewer panel. Use this when the user asks to view, display, open, or inspect a FITS file or astronomical image. If the file path is not yet known, first query the archive to find the frame.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description": "Absolute file path to the FITS file on disk"
                    ] as [String: Any]
                ],
                "required": ["path"]
            ] as [String: Any]
        ]
    ]

    // MARK: - Init

    init(apiKey: String) {
        self.claudeService = ClaudeService(apiKey: apiKey)
    }

    func updateAPIKey(_ apiKey: String) {
        self.claudeService = ClaudeService(apiKey: apiKey)
    }

    // MARK: - Messaging

    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let text = inputText
        inputText = ""
        isLoading = true
        errorMessage = nil

        messages.append(Message(role: "user", content: text))
        apiConversation.append(["role": "user", "content": text])

        Task { await processConversationTurn() }
    }

    private func processConversationTurn() async {
        for _ in 0..<maxToolRounds {
            do {
                // ArchiveToolDefinitions uses "inputSchema" (MCP wire format);
                // the Claude API requires "input_schema".
                let archiveTools = archiveManager.availableTools.map { tool -> [String: Any] in
                    [
                        "name": tool["name"] as? String ?? "",
                        "description": tool["description"] as? String ?? "",
                        "input_schema": tool["inputSchema"] as? [String: Any] ?? [:]
                    ]
                }
                let allTools = localTools + archiveTools

                logger.info("Tools: \(allTools.count) (\(self.localTools.count) local + \(archiveTools.count) archive, connected: \(self.archiveManager.isConnected))")

                let response = try await claudeService.sendMessage(
                    apiMessages: apiConversation,
                    tools: allTools.isEmpty ? nil : allTools,
                    system: systemPrompt
                )

                if !response.toolUses.isEmpty {
                    toolCallStatus = "Executing \(response.toolUses.count) tool(s)..."

                    var assistantContent: [[String: Any]] = []
                    if let text = response.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        assistantContent.append(["type": "text", "text": text])
                        messages.append(Message(role: "assistant",
                                                content: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                                messageType: .text))
                    }
                    for toolUse in response.toolUses {
                        assistantContent.append([
                            "type": "tool_use",
                            "id": toolUse.id,
                            "name": toolUse.name,
                            "input": toolUse.input
                        ])
                    }
                    apiConversation.append(["role": "assistant", "content": assistantContent])

                    var toolResultBlocks: [[String: Any]] = []
                    for toolUse in response.toolUses {
                        let msg = Message(role: "assistant", content: "",
                                          messageType: .toolUse(toolName: toolUse.name, arguments: toolUse.input))
                        messages.append(msg)
                        let messageId = msg.id

                        let (resultText, isError) = await executeToolCall(toolUse)

                        toolResultBlocks.append([
                            "type": "tool_result",
                            "tool_use_id": toolUse.id,
                            "is_error": isError,
                            "content": resultText
                        ])

                        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[idx] = Message(
                                id: messageId, role: "assistant", content: resultText,
                                messageType: .toolResult(
                                    toolName: toolUse.name,
                                    resultSummary: isError ? "Error: \(resultText)" : String(resultText.prefix(100)),
                                    fullContent: isError ? "" : resultText,
                                    arguments: toolUse.input))
                        }
                    }

                    apiConversation.append(["role": "user", "content": toolResultBlocks])
                    toolCallStatus = nil

                } else {
                    if let text = response.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        messages.append(Message(role: "assistant", content: trimmed, messageType: .text))
                        apiConversation.append(["role": "assistant", "content": trimmed])
                    }
                    isLoading = false
                    toolCallStatus = nil
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
                toolCallStatus = nil
                return
            }
        }
        errorMessage = "Reached maximum tool-call depth (\(maxToolRounds)). Stopping."
        isLoading = false
        toolCallStatus = nil
    }

    // Returns (resultText, isError). Local tools are handled here; MCP tools are forwarded.
    private func executeToolCall(_ toolUse: ToolUse) async -> (String, Bool) {
        switch toolUse.name {
        case "open_fits_viewer":
            guard let path = toolUse.input["path"] as? String, !path.isEmpty else {
                return ("No file path provided.", true)
            }
            let url = URL(fileURLWithPath: path)
            paneManager?.showFITSViewer(url: url)
            logger.info("Opening FITS viewer: \(path)")
            return ("Opened \(url.lastPathComponent) in the FITS viewer.", false)

        default:
            do {
                let result = try await archiveManager.callTool(name: toolUse.name, arguments: toolUse.input)
                return (result, false)
            } catch {
                return (error.localizedDescription, true)
            }
        }
    }

    func clearConversation() {
        messages.removeAll()
        apiConversation.removeAll()
        errorMessage = nil
        toolCallStatus = nil
    }
}
