import Foundation
import TOMLKit

/// Codex TOML configuration structure.
public struct CodexConfig: Codable, Equatable {
    public var providers: [String: CodexProviderConfig]

    public init(providers: [String: CodexProviderConfig] = [:]) {
        self.providers = providers
    }
}

/// Provider configuration in Codex TOML format.
public struct CodexProviderConfig: Codable, Equatable {
    public var name: String?
    public var baseURL: String?
    public var apiKey: String?
    public var model: String?

    public init(name: String? = nil, baseURL: String? = nil, apiKey: String? = nil, model: String? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

/// Parses and writes Codex TOML configuration files.
public struct TOMLConfigParser {

    /// Default Codex config path.
    public static let defaultConfigPath = "~/.codex/config.toml"

    public init() {}

    /// Parse Codex TOML configuration file.
    public func parse(path: String) throws -> CodexConfig {
        let expandedPath = (path as NSString).expandingTildeInPath
        let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
        return try parse(content: content)
    }

    /// Parse Codex TOML configuration from string.
    public func parse(content: String) throws -> CodexConfig {
        let table = try TOMLTable(string: content)
        var providers: [String: CodexProviderConfig] = [:]

        // Parse providers table
        if let providersTable = table["providers"]?.table {
            for (key, value) in providersTable {
                if let providerTable = value.table {
                    var config = CodexProviderConfig()

                    config.name = providerTable["name"]?.string
                    config.baseURL = providerTable["base_url"]?.string ?? providerTable["baseURL"]?.string
                    config.apiKey = providerTable["api_key"]?.string ?? providerTable["apiKey"]?.string
                    config.model = providerTable["model"]?.string

                    providers[key] = config
                }
            }
        }

        return CodexConfig(providers: providers)
    }

    /// Write Codex TOML configuration to file.
    public func write(config: CodexConfig, path: String) throws {
        let expandedPath = (path as NSString).expandingTildeInPath

        // Ensure directory exists
        let directory = (expandedPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let content = try serialize(config: config)
        try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
    }

    /// Serialize Codex configuration to TOML string.
    public func serialize(config: CodexConfig) throws -> String {
        var table = TOMLTable()

        // Create providers table
        var providersTable = TOMLTable()
        for (key, provider) in config.providers {
            var providerTable = TOMLTable()
            if let name = provider.name {
                providerTable["name"] = name
            }
            if let baseURL = provider.baseURL {
                providerTable["base_url"] = baseURL
            }
            if let apiKey = provider.apiKey {
                providerTable["api_key"] = apiKey
            }
            if let model = provider.model {
                providerTable["model"] = model
            }
            providersTable[key] = providerTable
        }
        table["providers"] = providersTable

        return table.convert()
    }

    /// Convert Codex config to Provider objects.
    public func toProviders(config: CodexConfig) -> [Provider] {
        var providers: [Provider] = []

        for (id, codexProvider) in config.providers {
            var settingsConfig: [String: AnyCodable] = [:]

            if let baseURL = codexProvider.baseURL {
                settingsConfig["base_url"] = AnyCodable(baseURL)
            }
            if let apiKey = codexProvider.apiKey {
                settingsConfig["env"] = AnyCodable(["OPENAI_API_KEY": apiKey])
            }

            let provider = Provider(
                id: id,
                name: codexProvider.name ?? id,
                settingsConfig: settingsConfig
            )
            providers.append(provider)
        }

        return providers
    }

    /// Backup original Codex config.
    public func backup(path: String) throws -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        let backupPath = expandedPath + ".backup.\(Int(Date().timeIntervalSince1970))"

        if FileManager.default.fileExists(atPath: expandedPath) {
            try FileManager.default.copyItem(atPath: expandedPath, toPath: backupPath)
        }

        return backupPath
    }
}
