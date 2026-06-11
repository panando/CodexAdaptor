import Foundation
import TOMLKit

/// Service for managing Codex configuration file.
public class CodexConfigService {
    public static let shared = CodexConfigService()

    private let configPath: String
    private let backupSuffix = ".bak.codexrouter"

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = "\(home)/.codex/config.toml"
    }

    /// Check if Codex config exists.
    public var configExists: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    /// Get current Codex configuration.
    public func getCurrentConfig() throws -> CodexProviderConfig? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let content = try String(contentsOfFile: configPath, encoding: String.Encoding.utf8)
        let table = try TOMLTable(string: content)

        // Parse model_provider name
        let modelProvider = table["model_provider"]?.string ?? "custom"

        // Parse model_providers section
        guard let providersTable = table["model_providers"]?.table,
              let providerTable = providersTable[modelProvider]?.table else {
            return nil
        }

        let name = providerTable["name"]?.string ?? ""
        let baseURL = providerTable["base_url"]?.string ?? ""
        let wireAPI = providerTable["wire_api"]?.string ?? "responses"
        let bearerToken = providerTable["experimental_bearer_token"]?.string

        return CodexProviderConfig(
            providerId: modelProvider,
            name: name,
            baseURL: baseURL,
            wireAPI: wireAPI,
            bearerToken: bearerToken
        )
    }

    /// Update Codex config to use proxy.
    public func setProxyURL(_ proxyURL: String = "http://127.0.0.1:15721") throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        let content = try String(contentsOfFile: configPath, encoding: String.Encoding.utf8)
        var table = try TOMLTable(string: content)

        // Get current model provider
        let modelProvider = table["model_provider"]?.string ?? "custom"

        // Backup original config
        let backupPath = configPath + backupSuffix
        if !FileManager.default.fileExists(atPath: backupPath) {
            try content.write(toFile: backupPath, atomically: true, encoding: String.Encoding.utf8)
        }

        // Update base_url in model_providers section
        if var providersTable = table["model_providers"]?.table,
           var providerTable = providersTable[modelProvider]?.table {
            providerTable["base_url"] = proxyURL
            providersTable[modelProvider] = .table(providerTable)
            table["model_providers"] = .table(providersTable)
        }

        // Write updated config
        let updatedContent = table.description
        try updatedContent.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
    }

    /// Restore original Codex config (remove proxy).
    public func restoreOriginalConfig() throws {
        let backupPath = configPath + backupSuffix

        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw CodexConfigError.backupNotFound
        }

        let originalContent = try String(contentsOfFile: backupPath, encoding: String.Encoding.utf8)
        try originalContent.write(toFile: configPath, atomically: true, encoding: String.Encoding.utf8)
    }

    /// Check if proxy is currently configured.
    public func isProxyConfigured() throws -> Bool {
        guard let config = try getCurrentConfig() else {
            return false
        }
        return config.baseURL.contains("15721")
    }
}

/// Codex provider configuration.
public struct CodexProviderConfig {
    public let providerId: String
    public let name: String
    public let baseURL: String
    public let wireAPI: String
    public let bearerToken: String?

    public var isUsingProxy: Bool {
        baseURL.contains("15721")
    }
}

/// Codex config errors.
public enum CodexConfigError: Error, LocalizedError {
    case configNotFound
    case backupNotFound
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "Codex config file not found"
        case .backupNotFound:
            return "Backup config file not found"
        case .parseError(let message):
            return "Failed to parse config: \(message)"
        }
    }
}
