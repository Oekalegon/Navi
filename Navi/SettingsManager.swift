//
//  SettingsManager.swift
//  Navi
//
//  Created by Dieudonné Willems on 31/05/2026.
//

import Foundation
import Security
import OSLog
import Observation

@Observable
class SettingsManager {
    static let shared = SettingsManager()
    private let logger = Logger(subsystem: "org.oekalegon.Navi", category: "SettingsManager")

    var apiKey: String = "" {
        didSet { saveAPIKey(apiKey) }
    }
    var archivePath: String {
        didSet { UserDefaults.standard.set(archivePath, forKey: "archivePath") }
    }

    private let keychainService = "com.navi.anthropic"
    private let keychainAccount = "api-key"

    private init() {
        let savedPath = UserDefaults.standard.string(forKey: "archivePath")
        let envPath = ProcessInfo.processInfo.environment["ASTROARCHIVE_PATH"]
        let configFilePath = ("~/.config/astrophotokit/archive_path" as NSString).expandingTildeInPath
        let configPath = try? String(contentsOfFile: configFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.archivePath = savedPath ?? envPath ?? configPath ?? ""

        // Load API key last — didSet won't fire during init because the property
        // isn't fully initialised yet when the assignment happens in init bodies.
        // We suppress the keychain write by assigning directly via _apiKey access
        // is not possible with @Observable, so we use a temporary workaround:
        // load into a local, assign, then the didSet will fire but keychain write
        // is idempotent (writing the same value is harmless).
        self.apiKey = loadAPIKey() ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    }

    private func saveAPIKey(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clearAPIKey() { apiKey = "" }

    // MARK: - Security-Scoped Bookmarks

    func saveArchiveBookmark(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: "archiveBookmark")
        logger.info("Saved archive bookmark for: \(url.path)")
    }

    func loadArchiveBookmark() -> URL? { loadBookmark(key: "archiveBookmark") }

    private func loadBookmark(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
              !isStale else { return nil }
        return url
    }
}
