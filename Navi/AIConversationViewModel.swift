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
    // Expose selectedModel so views can bind to it without chaining through claudeService.
    var selectedModel: ClaudeModel {
        get { claudeService.selectedModel }
        set { claudeService.selectedModel = newValue }
    }

    private let mcpManager = AstroKitMCPManager.shared

    init(apiKey: String) {
        self.claudeService = ClaudeService(apiKey: apiKey)
    }

    func updateAPIKey(_ apiKey: String) {
        self.claudeService = ClaudeService(apiKey: apiKey)
    }

    private let maxToolRounds = 10

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

    private func processConversationTurn(depth: Int = 0) async {
        guard depth < maxToolRounds else {
            errorMessage = "Reached maximum tool-call depth (\(maxToolRounds)). Stopping."
            isLoading = false
            toolCallStatus = nil
            return
        }
        do {
            let tools = mcpManager.availableTools.map { tool -> [String: Any] in
                [
                    "name": tool["name"] as? String ?? "",
                    "description": tool["description"] as? String ?? "",
                    "input_schema": tool["inputSchema"] as? [String: Any] ?? [:]
                ]
            }

            logger.info("Available MCP tools count: \(tools.count)")
            if tools.isEmpty {
                logger.warning("No MCP tools available — connected: \(self.mcpManager.isConnected)")
            }

            let response = try await claudeService.sendMessage(
                apiMessages: apiConversation,
                tools: tools.isEmpty ? nil : tools
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

                    do {
                        let result = try await mcpManager.callTool(name: toolUse.name, arguments: toolUse.input)

                        var contentText = ""
                        if let content = result["content"] as? [Any] {
                            for item in content {
                                if let block = item as? [String: Any],
                                   let text = block["text"] as? String {
                                    contentText += text
                                }
                            }
                        }

                        toolResultBlocks.append([
                            "type": "tool_result",
                            "tool_use_id": toolUse.id,
                            "content": contentText
                        ])

                        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[idx] = Message(
                                id: messageId, role: "assistant", content: contentText,
                                messageType: .toolResult(
                                    toolName: toolUse.name,
                                    resultSummary: String(contentText.prefix(100)),
                                    fullContent: contentText))
                        }
                    } catch {
                        toolResultBlocks.append([
                            "type": "tool_result",
                            "tool_use_id": toolUse.id,
                            "is_error": true,
                            "content": error.localizedDescription
                        ])
                        if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                            messages[idx] = Message(
                                id: messageId, role: "assistant", content: error.localizedDescription,
                                messageType: .toolResult(
                                    toolName: toolUse.name,
                                    resultSummary: "Error: \(error.localizedDescription)",
                                    fullContent: ""))
                        }
                    }
                }

                apiConversation.append(["role": "user", "content": toolResultBlocks])
                toolCallStatus = nil
                await processConversationTurn(depth: depth + 1)

            } else {
                if let text = response.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    messages.append(Message(role: "assistant", content: trimmed, messageType: .text))
                    apiConversation.append(["role": "assistant", "content": trimmed])
                }
                isLoading = false
                toolCallStatus = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            toolCallStatus = nil
        }
    }

    func clearConversation() {
        messages.removeAll()
        apiConversation.removeAll()
        errorMessage = nil
        toolCallStatus = nil
    }
}
