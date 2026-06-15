//
//  ClaudeService.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import Observation

enum MessageType {
    case text
    case toolUse(toolName: String, arguments: [String: Any])
    case toolResult(toolName: String, resultSummary: String, fullContent: String, arguments: [String: Any])
}

struct Message: Identifiable, Codable {
    let id: UUID
    let role: String
    var content: String
    var messageType: MessageType?

    init(id: UUID = UUID(), role: String, content: String, messageType: MessageType? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.messageType = messageType
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content
    }
}

struct ClaudeResponse {
    let text: String?
    let toolUses: [ToolUse]
    let stopReason: String
}

struct ToolUse: Identifiable {
    let id: String
    let name: String
    let input: [String: Any]
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-4-6"
    case opus   = "claude-opus-4-8"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet: return "Claude Sonnet 4.6 (Recommended)"
        case .opus:   return "Claude Opus 4.8 (Most Capable)"
        }
    }
}

@Observable
class ClaudeService {
    private let apiKey: String
    private let apiURL = "https://api.anthropic.com/v1/messages"
    var selectedModel: ClaudeModel = .sonnet

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func sendMessage(apiMessages: [[String: Any]], tools: [[String: Any]]? = nil,
                     system: String? = nil) async throws -> ClaudeResponse {
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var requestBody: [String: Any] = [
            "model": selectedModel.rawValue,
            "max_tokens": 4096,
            "messages": apiMessages
        ]

        if let system = system, !system.isEmpty {
            requestBody["system"] = system
        }

        if let tools = tools, !tools.isEmpty {
            requestBody["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let errorType = error["type"] as? String,
               let errorMessage = error["message"] as? String {
                throw ClaudeError.apiError(statusCode: httpResponse.statusCode, type: errorType, message: errorMessage)
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ClaudeError.apiError(statusCode: httpResponse.statusCode, type: "unknown", message: errorMessage)
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let stopReason = json["stop_reason"] as? String else {
            throw ClaudeError.invalidResponse
        }

        var text: String?
        var toolUses: [ToolUse] = []

        for block in content {
            if let type = block["type"] as? String {
                if type == "text", let blockText = block["text"] as? String {
                    text = (text ?? "") + blockText
                } else if type == "tool_use",
                          let id = block["id"] as? String,
                          let name = block["name"] as? String,
                          let input = block["input"] as? [String: Any] {
                    toolUses.append(ToolUse(id: id, name: name, input: input))
                }
            }
        }

        return ClaudeResponse(text: text, toolUses: toolUses, stopReason: stopReason)
    }
}

enum ClaudeError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, type: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .apiError(let statusCode, let type, let message):
            switch type {
            case "rate_limit_error":
                return "⚠️ Rate Limit Exceeded\n\nYou've reached your API usage limit. Please wait a moment and try again.\n\nDetails: \(message)"
            case "invalid_request_error":
                return "⚠️ Invalid Request\n\n\(message)"
            case "authentication_error":
                return "🔑 Authentication Error\n\nYour API key may be invalid or expired. Please check your settings."
            case "permission_error":
                return "🚫 Permission Denied\n\n\(message)"
            default:
                return "⚠️ API Error (\(statusCode))\n\n\(message)"
            }
        }
    }
}
