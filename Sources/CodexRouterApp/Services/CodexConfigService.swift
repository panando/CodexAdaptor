import Foundation
import CodexRouterCore

/// Service for managing Codex configuration.
/// config.toml: only Codex-native fields (base_url→proxy, wire_api, model_provider, model, model_catalog_json, experimental_bearer_token)
/// providers.json: proxy-internal data (upstream_base_url, upstream_wire_api, reasoning_config, model_catalog)
/// Follows EchoBird's pattern: proxy config lives in a separate file, config.toml stays clean.
public class CodexConfigService {
    public static let shared = CodexConfigService()

    private let home: String
    private let configPath: String
    private let providersPath: String
    private let modelsCachePath: String
    private let backupSuffix = ".bak.codexrouter"

    private static let templateSlug = "gpt-5.5"

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.home = home
        self.configPath = "\(home)/.codex/config.toml"
        self.providersPath = "\(home)/.codex-router/providers.json"
        self.modelsCachePath = "\(home)/.codex/models_cache.json"
    }

    private func modelCatalogPath(for providerId: String) -> String {
        "\(home)/.codex/\(providerId)-model-catalog.json"
    }

    public var configExists: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    // MARK: - Providers JSON (proxy-internal data)

    private func readProviderStore() -> ProviderStore {
        guard FileManager.default.fileExists(atPath: providersPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: providersPath)),
              let store = try? JSONDecoder().decode(ProviderStore.self, from: data) else {
            return ProviderStore()
        }
        return store
    }

    private func writeProviderStore(_ store: ProviderStore) throws {
        let directory = (providersPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(store)
        try data.write(to: URL(fileURLWithPath: providersPath))
    }

    // MARK: - Reading Upstream Provider (for proxy)

    /// Get current upstream provider config. Reads model_provider from config.toml, metadata from providers.json.
    public func getCurrentUpstreamProvider() throws -> UpstreamProvider? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        guard let providerId = extractValue(from: content, key: "model_provider") else {
            return nil
        }

        let store = readProviderStore()
        guard let meta = store.providers[providerId],
              let upstreamURL = meta.upstreamBaseURL else {
            return nil
        }

        let sectionContent = providerSectionContent(providerId: providerId, configContent: content)
        let name = sectionContent.flatMap { extractValue(from: $0, key: "name") } ?? providerId
        let bearerToken = sectionContent.flatMap { extractValue(from: $0, key: "experimental_bearer_token") }
        let usesChatCompletions = (meta.upstreamWireAPI ?? "chat").lowercased() == "chat"

        return UpstreamProvider(
            id: providerId,
            name: name,
            baseURL: upstreamURL,
            usesChatCompletions: usesChatCompletions,
            bearerToken: bearerToken,
            reasoningConfig: meta.reasoningConfig
        )
    }

    // MARK: - Reading Providers (for UI)

    /// Get all model providers enriched with metadata from providers.json.
    public func getModelProviders() throws -> [CodexModelProvider] {
        var providers: [CodexModelProvider] = []

        let configSections = try readConfigProviderSections()
        let store = readProviderStore()

        for (providerId, sectionContent) in configSections {
            let meta = store.providers[providerId]
            let name = extractValue(from: sectionContent, key: "name") ?? providerId
            let wireAPI = extractValue(from: sectionContent, key: "wire_api") ?? "responses"
            let apiKey = extractValue(from: sectionContent, key: "api_key")
            let bearerToken = extractValue(from: sectionContent, key: "experimental_bearer_token")

            let modelCatalog = (try? readModelCatalog(for: providerId))
                ?? meta?.modelCatalog

            let provider = CodexModelProvider(
                id: providerId,
                name: name,
                baseURL: meta?.upstreamBaseURL ?? extractValue(from: sectionContent, key: "base_url") ?? "",
                wireAPI: wireAPI,
                upstreamWireAPI: meta?.upstreamWireAPI ?? "chat",
                apiKey: apiKey,
                bearerToken: bearerToken,
                modelCatalog: modelCatalog,
                reasoningConfig: meta?.reasoningConfig
            )
            providers.append(provider)
        }

        return providers
    }

    public func getCurrentProvider() throws -> CodexModelProvider? {
        guard FileManager.default.fileExists(atPath: configPath) else { return nil }
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        guard let providerId = extractValue(from: content, key: "model_provider") else { return nil }
        let providers = try getModelProviders()
        return providers.first { $0.id == providerId }
    }

    public func getCurrentModel() throws -> String? {
        guard FileManager.default.fileExists(atPath: configPath) else { return nil }
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        return extractValue(from: content, key: "model")
    }

    /// Read model catalog from JSON file.
    public func readModelCatalog(for providerId: String? = nil) throws -> ModelCatalog? {
        let path: String
        if let providerId = providerId {
            path = modelCatalogPath(for: providerId)
        } else {
            guard let config = try? String(contentsOfFile: configPath, encoding: .utf8),
                  let catalogFile = extractValue(from: config, key: "model_catalog_json") else {
                return nil
            }
            path = "\(home)/.codex/\(catalogFile)"
        }

        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }

        var entries: [ModelCatalogEntry] = []
        for model in models {
            if let slug = model["slug"] as? String {
                entries.append(ModelCatalogEntry(
                    model: slug,
                    displayName: model["display_name"] as? String,
                    contextWindow: model["context_window"] as? UInt64
                ))
            }
        }
        return ModelCatalog(models: entries)
    }

    // MARK: - Reading config.toml provider sections (internal)

    /// Parse all [model_providers.xxx] sections from config.toml.
    private func readConfigProviderSections() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: configPath) else { return [:] }
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        var sections: [String: String] = [:]

        let pattern = #"\[model_providers\.([^\]]+)\]([^\[]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [:]
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        for match in matches {
            if let idRange = Range(match.range(at: 1), in: content),
               let sectionRange = Range(match.range(at: 2), in: content) {
                sections[String(content[idRange])] = String(content[sectionRange])
            }
        }
        return sections
    }

    /// Get the content of a specific provider section from config.toml.
    private func providerSectionContent(providerId: String, configContent: String) -> String? {
        let pattern = #"\[model_providers\.\#(providerId)\]([^\[]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: configContent, options: [], range: NSRange(configContent.startIndex..., in: configContent)),
              let sectionRange = Range(match.range(at: 1), in: configContent) else {
            return nil
        }
        return String(configContent[sectionRange])
    }

    // MARK: - Writing Codex Config

    public func switchProvider(to providerId: String, model: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        var content = try String(contentsOfFile: configPath, encoding: .utf8)

        let backupPath = configPath + backupSuffix
        if !FileManager.default.fileExists(atPath: backupPath) {
            try content.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        content = try updateValue(in: content, key: "model_provider", newValue: providerId)
        if let model = model {
            content = try updateValue(in: content, key: "model", newValue: model)
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Save a provider: config.toml gets Codex-native fields, providers.json gets proxy metadata.
    public func saveProvider(_ provider: CodexModelProvider) throws {
        // 1. Write Codex-native section to config.toml
        var content: String
        if FileManager.default.fileExists(atPath: configPath) {
            content = try String(contentsOfFile: configPath, encoding: .utf8)
        } else {
            content = generateDefaultConfig()
        }

        let sectionHeader = "[model_providers.\(provider.id)]"
        if content.contains(sectionHeader) {
            content = try updateProviderSection(content, provider: provider)
        } else {
            content = try addProviderSection(content, provider: provider)
        }

        let configDir = (configPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)

        // Model catalog
        if let catalog = provider.modelCatalog, !catalog.models.isEmpty {
            try generateModelCatalogJSON(from: catalog, providerId: provider.id)
            content = try ensureModelCatalogField(content, providerId: provider.id)
        } else {
            content = removeModelCatalogField(content)
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)

        // 2. Write proxy metadata to providers.json
        var store = readProviderStore()
        store.providers[provider.id] = ProviderMetaEntry(
            upstreamBaseURL: provider.baseURL.isEmpty ? nil : provider.baseURL,
            upstreamWireAPI: provider.upstreamWireAPI.isEmpty ? "chat" : provider.upstreamWireAPI,
            reasoningConfig: provider.reasoningConfig,
            modelCatalog: store.providers[provider.id]?.modelCatalog ?? provider.modelCatalog
        )
        try writeProviderStore(store)
    }

    public func deleteProvider(id: String) throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        var content = try String(contentsOfFile: configPath, encoding: .utf8)

        // If deleting current provider, switch to another
        if let currentId = extractValue(from: content, key: "model_provider"), currentId == id {
            let otherProviders = try getModelProviders().filter { $0.id != id }
            if let first = otherProviders.first {
                content = try updateValue(in: content, key: "model_provider", newValue: first.id)
                if let firstModel = first.modelCatalog?.models.first?.model {
                    content = try updateValue(in: content, key: "model", newValue: firstModel)
                }
            } else {
                content = try updateValue(in: content, key: "model_provider", newValue: "")
            }
        }

        // Remove section from config.toml
        let pattern = #"\[model_providers\.\#(id)\][^\[]*"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)

        // Remove from providers.json
        var store = readProviderStore()
        store.providers.removeValue(forKey: id)
        try writeProviderStore(store)
    }

    public func setProxyURL(_ proxyURL: String = "http://127.0.0.1:15721/v1") throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)

        let backupPath = configPath + backupSuffix
        if !FileManager.default.fileExists(atPath: backupPath) {
            try content.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        guard let providerId = extractValue(from: content, key: "model_provider") else {
            throw CodexConfigError.parseError("No model_provider found")
        }

        let pattern = #"(\[model_providers\.\#(providerId)\][^\[]*base_url\s*=\s*)"[^"]*""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            let newContent = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "$1\"\(proxyURL)\"")
            try newContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        }
    }

    public func restoreOriginalConfig() throws {
        let backupPath = configPath + backupSuffix
        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw CodexConfigError.backupNotFound
        }
        let originalContent = try String(contentsOfFile: backupPath, encoding: .utf8)
        try originalContent.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Config.toml section builders (Codex-native fields only)

    /// Write a provider section with only Codex-native fields.
    /// Proxy-internal data (upstream URL, reasoning) lives in providers.json.
    private func updateProviderSection(_ content: String, provider: CodexModelProvider) throws -> String {
        let sectionPattern = #"(\[model_providers\.\#(provider.id)\][^\[]*)"#
        guard let sectionRegex = try? NSRegularExpression(pattern: sectionPattern, options: [.dotMatchesLineSeparators]) else {
            throw CodexConfigError.parseError("Failed to find provider section")
        }

        var newSection = "[model_providers.\(provider.id)]\n"
        newSection += "name = \"\(provider.name)\"\n"
        newSection += "base_url = \"http://127.0.0.1:15721/v1\"\n"
        newSection += "wire_api = \"responses\"\n"
        newSection += "requires_openai_auth = true\n"
        if let bearerToken = provider.bearerToken, !bearerToken.isEmpty {
            newSection += "experimental_bearer_token = \"\(bearerToken)\"\n"
        }

        return sectionRegex.stringByReplacingMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content), withTemplate: newSection)
    }

    private func addProviderSection(_ content: String, provider: CodexModelProvider) throws -> String {
        var newSection = "\n[model_providers.\(provider.id)]\n"
        newSection += "name = \"\(provider.name)\"\n"
        newSection += "base_url = \"http://127.0.0.1:15721/v1\"\n"
        newSection += "wire_api = \"responses\"\n"
        newSection += "requires_openai_auth = true\n"
        if let bearerToken = provider.bearerToken, !bearerToken.isEmpty {
            newSection += "experimental_bearer_token = \"\(bearerToken)\"\n"
        }

        // Insert after existing provider sections or at end
        if content.contains("[model_providers.") {
            let pattern = #"\[model_providers\.[^\]]+\][^\[]*"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, options: [], range: range)
                if let lastMatch = matches.last, let lastRange = Range(lastMatch.range, in: content) {
                    var newContent = content
                    newContent.insert(contentsOf: newSection, at: content.index(after: lastRange.upperBound))
                    return newContent
                }
            }
        }

        return content + "\n" + newSection
    }

    // MARK: - Model Catalog Generation

    private func generateModelCatalogJSON(from catalog: ModelCatalog, providerId: String) throws {
        guard let template = try loadModelCatalogTemplate() else {
            throw CodexConfigError.parseError("Failed to load gpt-5.5 template for model catalog")
        }

        let defaultContextWindow = extractTopLevelU64("model_context_window") ?? 128000

        let entries = catalog.models.enumerated().map { (index, entry) -> [String: Any] in
            let displayName = entry.displayName ?? entry.model
            let contextWindow = entry.contextWindow ?? defaultContextWindow
            return generateModelCatalogEntry(
                from: template,
                model: entry.model,
                displayName: displayName,
                contextWindow: contextWindow,
                priority: index
            )
        }

        let catalogJSON: [String: Any] = ["models": entries]
        let jsonData = try JSONSerialization.data(withJSONObject: catalogJSON, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: URL(fileURLWithPath: modelCatalogPath(for: providerId)))
    }

    private func generateModelCatalogEntry(
        from template: [String: Any],
        model: String,
        displayName: String,
        contextWindow: UInt64,
        priority: Int
    ) -> [String: Any] {
        var entry = template
        entry["slug"] = model
        entry["display_name"] = displayName
        entry["description"] = displayName
        entry["context_window"] = contextWindow
        entry["max_context_window"] = contextWindow
        entry["priority"] = 1000 + priority
        entry["additional_speed_tiers"] = [] as [String]
        entry["service_tiers"] = [] as [String]
        entry["availability_nux"] = NSNull()
        entry["upgrade"] = NSNull()
        return entry
    }

    // MARK: - Template Loading

    private func loadModelCatalogTemplate() throws -> [String: Any]? {
        if let template = try loadTemplateFromModelsCache() { return template }
        if let template = loadTemplateFromCodexCLI() { return template }
        return staticTemplateFallback()
    }

    private func loadTemplateFromModelsCache() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: modelsCachePath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: modelsCachePath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        return models.first { ($0["slug"] as? String) == Self.templateSlug }
    }

    private func loadTemplateFromCodexCLI() -> [String: Any]? {
        for candidate in codexCLICandidates() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: candidate)
            process.arguments = ["debug", "models", "--bundled"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { continue }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else { continue }
                if let found = models.first(where: { ($0["slug"] as? String) == Self.templateSlug }) {
                    return found
                }
            } catch { continue }
        }
        return nil
    }

    private func codexCLICandidates() -> [String] {
        var candidates = ["codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        for dir in [".nvm/current/bin", ".volta/bin", ".asdf/shims", ".local/bin"] {
            candidates.append("\(home)/\(dir)/codex")
        }
        return candidates
    }

    private func staticTemplateFallback() -> [String: Any] {
        return [
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                ["effort": "low", "description": "Fast responses with lighter reasoning"],
                ["effort": "medium", "description": "Balances speed and reasoning depth for everyday tasks"],
                ["effort": "high", "description": "Greater reasoning depth for complex problems"]
            ],
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": true,
            "additional_speed_tiers": [] as [String],
            "service_tiers": [] as [String],
            "availability_nux": NSNull(),
            "upgrade": NSNull(),
            "base_instructions": "You are Codex, a coding agent.",
            "model_messages": [
                "instructions_template": "You are Codex, a coding agent. {{ personality }}",
                "instructions_variables": [
                    "personality_default": "",
                    "personality_friendly": "You are helpful and friendly.\n",
                    "personality_pragmatic": "You are a deeply pragmatic software engineer.\n"
                ]
            ] as [String: Any],
            "supports_reasoning_summaries": true,
            "default_reasoning_summary": "none",
            "support_verbosity": true,
            "default_verbosity": "low",
            "apply_patch_tool_type": "freeform",
            "web_search_tool_type": "text_and_image",
            "truncation_policy": ["mode": "tokens", "limit": 10000] as [String: Any],
            "supports_parallel_tool_calls": true,
            "supports_image_detail_original": true,
            "effective_context_window_percent": 95,
            "experimental_supported_tools": [] as [String],
            "input_modalities": ["text", "image"],
            "supports_search_tool": true
        ]
    }

    // MARK: - TOML Helpers

    private func extractValue(from content: String, key: String) -> String? {
        let pattern = #"^\s*\#(key)\s*=\s*"([^"]*)""#
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

    private func extractTopLevelU64(_ key: String) -> UInt64? {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
        let pattern = #"^\s*\#(key)\s*=\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]),
              let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
              let valueRange = Range(match.range(at: 1), in: content),
              let value = UInt64(String(content[valueRange])) else { return nil }
        return value
    }

    private func updateValue(in content: String, key: String, newValue: String) throws -> String {
        let pattern = #"^(\s*\#(key)\s*=\s*)"[^"]*""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            throw CodexConfigError.parseError("Failed to create regex for key: \(key)")
        }
        let newContent = regex.stringByReplacingMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content), withTemplate: "$1\"\(newValue)\"")
        if newContent == content {
            return "\(key) = \"\(newValue)\"\n" + content
        }
        return newContent
    }

    private func ensureModelCatalogField(_ content: String, providerId: String) throws -> String {
        let fieldName = "model_catalog_json"
        let fieldValue = "\(providerId)-model-catalog.json"

        if content.contains("\(fieldName) = \"\(fieldValue)\"") { return content }

        let existingPattern = #"^\s*model_catalog_json\s*=\s*"[^"]*""#
        if let regex = try? NSRegularExpression(pattern: existingPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "\(fieldName) = \"\(fieldValue)\"")
            }
        }

        var lines = content.components(separatedBy: "\n")
        var insertIndex = 0
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("model =") || line.hasPrefix("wire_api =") {
                insertIndex = index + 1
            }
        }
        lines.insert("\(fieldName) = \"\(fieldValue)\"", at: insertIndex)
        return lines.joined(separator: "\n")
    }

    private func removeModelCatalogField(_ content: String) -> String {
        let pattern = #"^model_catalog_json\s*=\s*"[^"]*"\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return content
        }
        return regex.stringByReplacingMatches(in: content, options: [], range: NSRange(content.startIndex..., in: content), withTemplate: "")
    }

    private func generateDefaultConfig() -> String {
        return """
        model_provider = "custom"
        model = "gpt-4"

        [model_providers]

        """
    }
}

// MARK: - Providers JSON Model

/// Root of ~/.codex-router/providers.json
struct ProviderStore: Codable {
    var providers: [String: ProviderMetaEntry] = [:]
}

/// Proxy-internal metadata for a provider. Mirrors echoBird's ~/.echobird/codex.json pattern.
struct ProviderMetaEntry: Codable {
    var upstreamBaseURL: String?
    var upstreamWireAPI: String?
    var reasoningConfig: ReasoningConfig?
    var modelCatalog: ModelCatalog?
}

// MARK: - Public Types

/// Codex model provider configuration (for UI).
public struct CodexModelProvider: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: String
    public var wireAPI: String
    public var upstreamWireAPI: String
    public var apiKey: String?
    public var bearerToken: String?
    public var modelCatalog: ModelCatalog?
    public var reasoningConfig: ReasoningConfig?

    public init(
        id: String,
        name: String,
        baseURL: String,
        wireAPI: String = "responses",
        upstreamWireAPI: String = "chat",
        apiKey: String? = nil,
        bearerToken: String? = nil,
        modelCatalog: ModelCatalog? = nil,
        reasoningConfig: ReasoningConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.wireAPI = wireAPI
        self.upstreamWireAPI = upstreamWireAPI
        self.apiKey = apiKey
        self.bearerToken = bearerToken
        self.modelCatalog = modelCatalog
        self.reasoningConfig = reasoningConfig
    }

    public var isUsingProxy: Bool {
        baseURL.contains("15721")
    }

    public static func == (lhs: CodexModelProvider, rhs: CodexModelProvider) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.baseURL == rhs.baseURL &&
        lhs.wireAPI == rhs.wireAPI &&
        lhs.upstreamWireAPI == rhs.upstreamWireAPI &&
        lhs.apiKey == rhs.apiKey &&
        lhs.bearerToken == rhs.bearerToken &&
        lhs.modelCatalog == rhs.modelCatalog &&
        lhs.reasoningConfig == rhs.reasoningConfig
    }
}

public enum CodexConfigError: Error, LocalizedError {
    case configNotFound
    case backupNotFound
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .configNotFound: return "Codex config file not found"
        case .backupNotFound: return "Backup config file not found"
        case .parseError(let message): return "Failed to parse config: \(message)"
        }
    }
}

/// Upstream provider configuration for RequestHandler.
public struct UpstreamProvider: Sendable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let usesChatCompletions: Bool
    public let bearerToken: String?
    public let reasoningConfig: ReasoningConfig?

    public init(
        id: String,
        name: String,
        baseURL: String,
        usesChatCompletions: Bool,
        bearerToken: String? = nil,
        reasoningConfig: ReasoningConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.usesChatCompletions = usesChatCompletions
        self.bearerToken = bearerToken
        self.reasoningConfig = reasoningConfig
    }
}
