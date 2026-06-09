//
//  AIAssistantView.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import SwiftUI
import MarkdownUI

struct AIAssistantView: View {
    var pane: SplitPane
    @Environment(PaneManager.self) private var paneManager
    @Environment(SettingsManager.self) private var settings
    @State private var viewModel = AIConversationViewModel(apiKey: "")
    @State private var archiveManager = ArchiveManager.shared

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.clearConversation() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if settings.apiKey.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "key.slash")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.orange)
                                Text("No API Key Set")
                                    .font(.headline)
                                Text("Click the gear icon in the toolbar to add your Anthropic API key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                            .padding(.horizontal)
                        } else if let archiveError = archiveManager.errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "externaldrive.badge.exclamationmark")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.orange)
                                Text("Archive Not Connected")
                                    .font(.headline)
                                Text(archiveError)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                            .padding(.horizontal)
                        } else if viewModel.messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("Start a conversation with Claude")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(viewModel.toolCallStatus ?? "Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }

                        if let error = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    TextField("Ask me anything...", text: $vm.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .lineLimit(1...5)
                        .onSubmit { viewModel.sendMessage() }

                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.apiKey.isEmpty ||
                              viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              viewModel.isLoading)
                }

                HStack {
                    Text("Model:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $vm.selectedModel) {
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 160)

                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            .padding()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            viewModel.updateAPIKey(settings.apiKey)
            viewModel.paneManager = paneManager
            Task { await ArchiveManager.shared.connect(archivePath: settings.archivePath) }
        }
        .onChange(of: settings.apiKey) {
            viewModel.updateAPIKey(settings.apiKey)
        }
        .onChange(of: settings.archivePath) {
            Task { await ArchiveManager.shared.connect(archivePath: settings.archivePath) }
        }
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        if message.role == "user" {
            Text(message.content)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.cyan.opacity(0.3),
                                     Color.yellow.opacity(0.3), Color.red.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.cyan.opacity(0.2),
                                     Color.yellow.opacity(0.2), Color.red.opacity(0.2)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .blur(radius: 8).padding(-4))
                .padding(.horizontal, 4)
        } else if let messageType = message.messageType {
            switch messageType {
            case .toolUse(let toolName, _):
                ToolUseCard(toolName: toolName)
            case .toolResult(let toolName, let summary, let fullContent, let arguments):
                ToolResultCard(toolName: toolName, summary: summary, fullContent: fullContent, arguments: arguments)
            case .text:
                AssistantMessageView(content: message.content)
            }
        } else {
            AssistantMessageView(content: message.content)
        }
    }
}

struct AssistantMessageView: View {
    let content: String

    var body: some View {
        Markdown(content)
            .textSelection(.enabled)
            .markdownTheme(.gitHub.text { FontSize(13) })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct ToolUseCard: View {
    let toolName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Using tool: \(toolName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 4)
    }
}

struct ToolResultCard: View {
    let toolName: String
    let summary: String
    let fullContent: String
    let arguments: [String: Any]
    @Environment(PaneManager.self) private var paneManager

    private var isArchiveTool: Bool { toolName.hasPrefix("archive_") }
    private var hasContent: Bool { !fullContent.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool result: \(toolName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }

            if isArchiveTool && hasContent {
                Button(action: openArchiveBrowser) {
                    Label("Browse in Archive", systemImage: archiveIcon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 4)
    }

    private var archiveIcon: String {
        toolName.hasPrefix("archive_frameset") ? "rectangle.stack" : "rectangle"
    }

    private func openArchiveBrowser() {
        let content = ArchiveViewerContent.parse(toolName: toolName, content: fullContent)
        let filter = ArchiveFilter.from(toolName: toolName, arguments: arguments)
        paneManager.showArchiveViewer(content: content, filter: filter)
    }
}
