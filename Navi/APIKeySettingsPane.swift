//
//  APIKeySettingsPane.swift
//  Navi
//
//  The Settings "API Key" tab: the Anthropic Claude API key, split out of GeneralSettingsPane
//  into its own tab since it's a distinct concern from the archive path.
//

import SwiftUI

struct APIKeySettingsPane: View {
    @Environment(SettingsManager.self) private var settings
    @State private var apiKeyInput: String = ""
    @State private var showingKey: Bool = false

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 12) {
            Text("Anthropic API Key")
                .font(.headline)
            Text("Enter your Claude API key from console.anthropic.com")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if showingKey {
                    TextField("sk-ant-api03-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("sk-ant-api03-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { showingKey.toggle() }) {
                    Image(systemName: showingKey ? "eye.slash" : "eye")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !settings.apiKey.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("API key saved").font(.caption).foregroundStyle(.secondary)
                }
            }

            Button("Clear") { settings.clearAPIKey(); apiKeyInput = "" }
                .disabled(settings.apiKey.isEmpty)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { apiKeyInput = settings.apiKey }
        .onDisappear { commitAPIKeyIfChanged() }
    }

    /// The key stages in `apiKeyInput` rather than binding straight to `settings.apiKey` (which
    /// writes to Keychain on every `didSet`) so typing doesn't hit Keychain on every character.
    /// Committing on disappear (tab switch or window close) means a typed-but-unsaved key still
    /// gets persisted rather than silently discarded.
    private func commitAPIKeyIfChanged() {
        guard !apiKeyInput.isEmpty, apiKeyInput != settings.apiKey else { return }
        settings.apiKey = apiKeyInput
    }
}
