//
//  MCPClient.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import os

struct MCPRequest: Codable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]?
}

struct MCPResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: MCPError?
}

struct MCPError: Codable {
    let code: Int
    let message: String
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}

class MCPClient {
    private let process = Process()
    private let logger = Logger(subsystem: "com.navi.app", category: "MCPClient")

    private struct State {
        var nextRequestID = 0
        var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    }
    // OSAllocatedUnfairLock is safe to call from both sync and async contexts.
    private let state = OSAllocatedUnfairLock(initialState: State())

    // Accumulates bytes from stdout until complete newline-terminated lines arrive.
    // Only ever accessed from the readabilityHandler, which fires serially per pipe.
    private var readBuffer = Data()

    init(executablePath: String, environment: [String: String] = [:], arguments: [String] = []) {
        let execURL = URL(fileURLWithPath: executablePath)
        logger.info("Initializing MCP client with executable: \(executablePath)")
        logger.info("Arguments: \(arguments)")
        logger.info("File exists check: \(FileManager.default.fileExists(atPath: executablePath))")
        logger.info("File is readable: \(FileManager.default.isReadableFile(atPath: executablePath))")
        logger.info("File is executable: \(FileManager.default.isExecutableFile(atPath: executablePath))")

        process.executableURL = execURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }

    func start() throws {
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Log stderr from the MCP server.
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self?.logger.error("MCP stderr: \(text)")
            }
        }

        // Continuously read stdout and deliver complete JSON lines to waiting requests.
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.receive(data)
        }

        logger.info("About to run process...")
        do {
            try process.run()
            logger.info("Process started successfully, PID: \(self.process.processIdentifier)")
        } catch {
            logger.error("Failed to start process: \(error.localizedDescription)")
            throw error
        }
    }

    // Called from the readabilityHandler on an arbitrary background thread.
    private func receive(_ data: Data) {
        readBuffer.append(data)

        // A JSON-RPC server sends one response per line. Process all complete lines.
        while let newlinePos = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = readBuffer[readBuffer.startIndex...newlinePos]
            readBuffer.removeSubrange(readBuffer.startIndex...newlinePos)

            guard !lineData.allSatisfy({ $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) else {
                continue // skip blank lines
            }

            if let responseStr = String(data: lineData, encoding: .utf8) {
                logger.info("Response: \(responseStr.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            do {
                let response = try JSONDecoder().decode(MCPResponse.self, from: lineData)
                guard let id = response.id else { continue } // notification, ignore

                let continuation = state.withLock { $0.pendingRequests.removeValue(forKey: id) }

                guard let continuation = continuation else { continue }

                if let error = response.error {
                    continuation.resume(throwing: MCPClientError.serverError(code: error.code, message: error.message))
                } else if let result = response.result?.value as? [String: Any] {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: MCPClientError.invalidResponse)
                }
            } catch {
                logger.error("Failed to parse MCP response line: \(error.localizedDescription)")
            }
        }
    }

    func sendRequest(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard process.isRunning else {
            throw MCPClientError.processNotRunning
        }
        guard let inputPipe = process.standardInput as? Pipe else {
            throw MCPClientError.processNotRunning
        }

        let id = state.withLock { s -> Int in
            s.nextRequestID += 1
            return s.nextRequestID
        }

        let request = MCPRequest(id: id, method: method,
                                 params: params?.mapValues { AnyCodable($0) })
        let requestData = try JSONEncoder().encode(request)
        let jsonLine = requestData + Data([UInt8(ascii: "\n")])

        logger.info("Encoding request for method: \(method)")
        logger.info("Request JSON: \(String(data: requestData, encoding: .utf8) ?? "")")

        return try await withCheckedThrowingContinuation { continuation in
            // Register before sending so the response can never arrive before we're ready.
            state.withLock { $0.pendingRequests[id] = continuation }

            logger.info("Writing request to stdin...")
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: jsonLine)
                logger.info("Request written successfully")
            } catch {
                _ = state.withLock { $0.pendingRequests.removeValue(forKey: id) }
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        let abandoned = state.withLock { s -> [Int: CheckedContinuation<[String: Any], Error>] in
            let all = s.pendingRequests
            s.pendingRequests = [:]
            return all
        }
        for (_, continuation) in abandoned {
            continuation.resume(throwing: MCPClientError.processNotRunning)
        }
        process.terminate()
    }
}

enum MCPClientError: LocalizedError {
    case processNotRunning
    case invalidResponse
    case serverError(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .processNotRunning:
            return "MCP server process is not running"
        case .invalidResponse:
            return "Invalid response from MCP server"
        case .serverError(let code, let message):
            return "MCP server error (\(code)): \(message)"
        }
    }
}
