import Foundation

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

        let content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Parse using simple string matching
        let providerId = extractValue(from: content, key: "model_provider") ?? "custom"
        let name = extractModelProviderValue(from: content, providerId: providerId, key: "name") ?? ""
        let baseURL = extractModelProviderValue(from: content, providerId: providerId, key: "base_url") ?? ""
        let wireAPI = extractModelProviderValue(from: content, providerId: providerId, key: "wire_api") ?? "responses"
        let bearerToken = extractModelProviderValue(from: content, providerId: providerId, key: "experimental_bearer_token")

        return CodexProviderConfig(
            providerId: providerId,
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

        var content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Backup original config
        let backupPath = configPath + backupSuffix
        if !FileManager.default.fileExists(atPath: backupPath) {
            try content.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        // Get current provider ID
        let providerId = extractValue(from: content, key: "model_provider") ?? "custom"

        // Replace base_url in the provider section
        // Pattern: base_url = "old_url" within [model_providers.providerId] section
        let pattern = #"(\[model_providers\.\#(providerId)\][^\[]*base_url\s*=\s*)"[^"]*""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            let newContent = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "$1\"\(proxyURL)\"")
            try newContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        }
    }

    /// Restore original Codex config (remove proxy).
    public func restoreOriginalConfig() throws {
        let backupPath = configPath + backupSuffix

        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw CodexConfigError.backupNotFound
        }

        let originalContent = try String(contentsOfFile: backupPath, encoding: .utf8)
        try originalContent.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Check if proxy is currently configured.
    public func isProxyConfigured() throws -> Bool {
        guard let config = try getCurrentConfig() else {
            return false
        }
        return config.baseURL.contains("15721")
    }

    // MARK: - Private Helpers

    private func extractValue(from content: String, key: String) -> String? {
        let pattern = #"^\#(key)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[valueRange])
    }

    private func extractModelProviderValue(from content: String, providerId: String, key: String) -> String? {
        // Find the [model_providers.providerId] section
        let sectionPattern = #"\[model_providers\.\#(providerId)\]([^\[]*)"#
        guard let sectionRegex = try? NSRegularExpression(pattern: sectionPattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }

        let contentRange = NSRange(content.startIndex..., in: content)
        guard let sectionMatch = sectionRegex.firstMatch(in: content, options: [], range: contentRange),
              let sectionRange = Range(sectionMatch.range(at: 1), in: content) else {
            return nil
        }

        let sectionContent = String(content[sectionRange])

        // Find the key in the section
        let keyPattern = #"^\#(key)\s*=\s*"([^"]*)""#
        guard let keyRegex = try? NSRegularExpression(pattern: keyPattern, options: [.anchorsMatchLines]) else {
            return nil
        }

        let sectionNSRange = NSRange(sectionContent.startIndex..., in: sectionContent)
        guard let keyMatch = keyRegex.firstMatch(in: sectionContent, options: [], range: sectionNSRange),
              let valueRange = Range(keyMatch.range(at: 1), in: sectionContent) else {
            return nil
        }

        return String(sectionContent[valueRange])
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
