import Foundation
import CodexRouterCore

/// Service for managing Codex configuration file.
/// This is the SINGLE source of truth for CodexRouter configuration.
/// Follows cc-switch's approach for model catalog generation.
public class CodexConfigService {
    public static let shared = CodexConfigService()

    private let configPath: String
    private let modelCatalogPath: String
    private let modelsCachePath: String
    private let backupSuffix = ".bak.codexrouter"

    /// Template slug used by cc-switch for generating catalog entries.
    private static let templateSlug = "gpt-5.5"

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.configPath = "\(home)/.codex/config.toml"
        self.modelCatalogPath = "\(home)/.codex/cc-switch-model-catalog.json"
        self.modelsCachePath = "\(home)/.codex/models_cache.json"
    }

    /// Check if Codex config exists.
    public var configExists: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    // MARK: - Reading Codex Config (Single Source of Truth)

    /// Get current upstream provider configuration.
    /// This is the ONLY method RequestHandler should use to get provider info.
    public func getCurrentUpstreamProvider() throws -> UpstreamProvider? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Get current provider ID
        guard let providerId = extractValue(from: content, key: "model_provider") else {
            return nil
        }

        // Find the provider section
        let sectionPattern = #"\[model_providers\.\#(providerId)\]([^\[]*)"#
        guard let sectionRegex = try? NSRegularExpression(pattern: sectionPattern, options: [.dotMatchesLineSeparators]),
              let sectionMatch = sectionRegex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
              let sectionRange = Range(sectionMatch.range(at: 1), in: content) else {
            return nil
        }

        let sectionContent = String(content[sectionRange])

        // Extract provider info
        let name = extractValue(from: sectionContent, key: "name") ?? providerId
        // Prefer upstream_base_url (actual API endpoint) over base_url (which may point to proxy)
        let upstreamBaseURL = extractValue(from: sectionContent, key: "upstream_base_url")
            ?? extractValue(from: sectionContent, key: "base_url")
            ?? extractValue(from: sectionContent, key: "baseURL")
        let bearerToken = extractValue(from: sectionContent, key: "experimental_bearer_token")

        // Determine upstream API format
        // upstream_wire_api specifies the format the upstream API uses (defaults to "chat" for most providers)
        // wire_api specifies the format Codex uses (should be "responses" for this proxy)
        let upstreamWireAPI = extractValue(from: sectionContent, key: "upstream_wire_api") ?? "chat"
        let usesChatCompletions = upstreamWireAPI.lowercased() == "chat"

        guard let baseURL = upstreamBaseURL else {
            return nil
        }

        return UpstreamProvider(
            id: providerId,
            name: name,
            baseURL: baseURL,
            usesChatCompletions: usesChatCompletions,
            bearerToken: bearerToken
        )
    }

    /// Get all model providers from Codex config.
    public func getModelProviders() throws -> [CodexModelProvider] {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return []
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        var providers: [CodexModelProvider] = []

        // Find all [model_providers.xxx] sections
        let pattern = #"\[model_providers\.([^\]]+)\]([^\[]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            if let idRange = Range(match.range(at: 1), in: content),
               let sectionRange = Range(match.range(at: 2), in: content) {
                let providerId = String(content[idRange])
                let sectionContent = String(content[sectionRange])

                let name = extractValue(from: sectionContent, key: "name")
                let baseURL = extractValue(from: sectionContent, key: "upstream_base_url")
                    ?? extractValue(from: sectionContent, key: "base_url")
                    ?? extractValue(from: sectionContent, key: "baseURL")
                    ?? ""
                let wireAPI = extractValue(from: sectionContent, key: "wire_api") ?? "responses"
                let apiKey = extractValue(from: sectionContent, key: "api_key") ?? extractValue(from: sectionContent, key: "apiKey")
                let bearerToken = extractValue(from: sectionContent, key: "experimental_bearer_token")

                // Read model catalog if exists (from separate JSON file)
                let modelCatalog = try? readModelCatalog()

                let provider = CodexModelProvider(
                    id: providerId,
                    name: name ?? providerId,
                    baseURL: baseURL,
                    wireAPI: wireAPI,
                    apiKey: apiKey,
                    bearerToken: bearerToken,
                    modelCatalog: modelCatalog
                )
                providers.append(provider)
            }
        }

        return providers
    }

    /// Get current model provider (the one set in model_provider field).
    public func getCurrentProvider() throws -> CodexModelProvider? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Get current provider ID
        guard let providerId = extractValue(from: content, key: "model_provider") else {
            return nil
        }

        let providers = try getModelProviders()
        return providers.first { $0.id == providerId }
    }

    /// Get current model name.
    public func getCurrentModel() throws -> String? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        return extractValue(from: content, key: "model")
    }

    /// Read model catalog from JSON file (simplified format for UI).
    public func readModelCatalog() throws -> ModelCatalog? {
        guard FileManager.default.fileExists(atPath: modelCatalogPath) else {
            return nil
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: modelCatalogPath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return nil
        }

        var entries: [ModelCatalogEntry] = []
        for model in models {
            if let slug = model["slug"] as? String {
                // Convert from catalog format to user-facing format
                let entry = ModelCatalogEntry(
                    model: slug,
                    displayName: model["display_name"] as? String,
                    contextWindow: model["context_window"] as? UInt64
                )
                entries.append(entry)
            }
        }

        return ModelCatalog(models: entries)
    }

    // MARK: - Writing Codex Config

    /// Switch to a different model provider.
    public func switchProvider(to providerId: String, model: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        var content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Backup if not already backed up
        let backupPath = configPath + backupSuffix
        if !FileManager.default.fileExists(atPath: backupPath) {
            try content.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        // Update model_provider
        content = try updateValue(in: content, key: "model_provider", newValue: providerId)

        // Update model if provided
        if let model = model {
            content = try updateValue(in: content, key: "model", newValue: model)
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Save a model provider with its model catalog configuration.
    /// This generates the model catalog JSON file from the user's configuration.
    public func saveProvider(_ provider: CodexModelProvider) throws {
        var content: String

        if FileManager.default.fileExists(atPath: configPath) {
            content = try String(contentsOfFile: configPath, encoding: .utf8)
        } else {
            content = generateDefaultConfig()
        }

        // Check if provider section exists
        let sectionHeader = "[model_providers.\(provider.id)]"
        if content.contains(sectionHeader) {
            content = try updateProviderSection(content, provider: provider)
        } else {
            content = try addProviderSection(content, provider: provider)
        }

        // Ensure directory exists
        let directory = (configPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Generate model catalog JSON from user configuration (following cc-switch's approach)
        // This is the key part: generate catalog from provider.modelCatalog.models
        if let catalog = provider.modelCatalog, !catalog.models.isEmpty {
            try generateModelCatalogJSON(from: catalog)
            // Add model_catalog_json field to config
            content = try ensureModelCatalogField(content)
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Delete a model provider from config.
    public func deleteProvider(id: String) throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        var content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Remove the provider section
        let pattern = #"\[model_providers\.\#(id)\][^\[]*"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        }

        try content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Configure Codex to use the proxy.
    public func setProxyURL(_ proxyURL: String = "http://127.0.0.1:15721") throws {
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw CodexConfigError.configNotFound
        }

        let content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Backup original config
        let backupPath = configPath + backupSuffix
        if !FileManager.default.fileExists(atPath: backupPath) {
            try content.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }

        // Get current provider ID
        guard let providerId = extractValue(from: content, key: "model_provider") else {
            throw CodexConfigError.parseError("No model_provider found")
        }

        // Replace base_url in the provider section
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
        guard let config = try getCurrentProvider() else {
            return false
        }
        return config.baseURL.contains("15721")
    }

    // MARK: - Model Catalog Generation (following cc-switch's approach)

    /// Generate model catalog JSON from user's modelCatalog configuration.
    /// This follows cc-switch's codex_model_catalog_from_settings logic.
    private func generateModelCatalogJSON(from catalog: ModelCatalog) throws {
        // Load template following cc-switch's priority:
        // 1. models_cache.json (created by Codex when it connects to OpenAI)
        // 2. codex CLI (debug models --bundled)
        // 3. Static fallback
        guard let template = try loadModelCatalogTemplate() else {
            throw CodexConfigError.parseError("Failed to load gpt-5.5 template for model catalog")
        }

        // Get default context window from config
        let defaultContextWindow = extractTopLevelU64("model_context_window") ?? 128000

        // Generate catalog entries from user's model configuration
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
        try jsonData.write(to: URL(fileURLWithPath: modelCatalogPath))
    }

    /// Generate a single model catalog entry from the template.
    /// Follows cc-switch's codex_catalog_model_entry function.
    private func generateModelCatalogEntry(
        from template: [String: Any],
        model: String,
        displayName: String,
        contextWindow: UInt64,
        priority: Int
    ) -> [String: Any] {
        // Clone the template
        var entry = template

        // Override with model-specific values (as per cc-switch's codex_catalog_model_entry)
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

    // MARK: - Template Loading (following cc-switch's approach)

    /// Load the gpt-5.5 template for model catalog entries.
    /// Priority: models_cache.json > codex CLI > static fallback.
    private func loadModelCatalogTemplate() throws -> [String: Any]? {
        // 1. Try models_cache.json
        if let template = try loadTemplateFromModelsCache() {
            NSLog("[CodexRouter] Loaded model template from models_cache.json")
            return template
        }

        // 2. Try codex CLI
        if let template = loadTemplateFromCodexCLI() {
            NSLog("[CodexRouter] Loaded model template from codex CLI")
            return template
        }

        // 3. Use static fallback
        NSLog("[CodexRouter] Using static model template fallback")
        return staticTemplateFallback()
    }

    /// Load template from ~/.codex/models_cache.json.
    private func loadTemplateFromModelsCache() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: modelsCachePath) else {
            return nil
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: modelsCachePath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return nil
        }

        // Find gpt-5.5 template
        for model in models {
            if let slug = model["slug"] as? String, slug == Self.templateSlug {
                return model
            }
        }

        return nil
    }

    /// Load template from codex CLI using `codex debug models --bundled`.
    private func loadTemplateFromCodexCLI() -> [String: Any]? {
        let candidates = codexCLICandidates()

        for candidate in candidates {
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
                      let models = json["models"] as? [[String: Any]] else {
                    continue
                }

                // Find gpt-5.5 template
                for model in models {
                    if let slug = model["slug"] as? String, slug == Self.templateSlug {
                        return model
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    /// Get list of codex CLI candidate paths.
    private func codexCLICandidates() -> [String] {
        var candidates: [String] = [
            "codex",  // PATH
            "/opt/homebrew/bin/codex",  // macOS Apple Silicon
            "/usr/local/bin/codex",  // macOS Intel / Linux
        ]

        // Add common home directory locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homeCandidates = [
            "\(home)/.nvm/current/bin/codex",
            "\(home)/.volta/bin/codex",
            "\(home)/.asdf/shims/codex",
            "\(home)/.local/bin/codex",
        ]
        candidates.append(contentsOf: homeCandidates)

        return candidates
    }

    /// Static fallback template (last resort, matches cc-switch's gpt5_5_template.json).
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
            "base_instructions": "You are Codex, a coding agent. You and the user share one workspace, and your job is to collaborate with them until their goal is genuinely handled.",
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

    // MARK: - Private Helpers

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
        guard FileManager.default.fileExists(atPath: configPath) else { return nil }
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
        let pattern = #"^\s*\#(key)\s*=\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: content),
              let value = UInt64(String(content[valueRange])) else {
            return nil
        }
        return value
    }

    private func updateValue(in content: String, key: String, newValue: String) throws -> String {
        let pattern = #"^(\s*\#(key)\s*=\s*)"[^"]*""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            throw CodexConfigError.parseError("Failed to create regex for key: \(key)")
        }

        let range = NSRange(content.startIndex..., in: content)
        let newContent = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "$1\"\(newValue)\"")

        // If the key doesn't exist, add it at the top
        if newContent == content {
            return "\(key) = \"\(newValue)\"\n" + content
        }

        return newContent
    }

    private func updateProviderSection(_ content: String, provider: CodexModelProvider) throws -> String {
        var result = content

        // Find the provider section
        let sectionPattern = #"(\[model_providers\.\#(provider.id)\][^\[]*)"#
        guard let sectionRegex = try? NSRegularExpression(pattern: sectionPattern, options: [.dotMatchesLineSeparators]) else {
            throw CodexConfigError.parseError("Failed to find provider section")
        }

        let contentRange = NSRange(content.startIndex..., in: content)

        // Build new section content (following cc-switch's format)
        var newSection = "[model_providers.\(provider.id)]\n"
        newSection += "name = \"\(provider.name)\"\n"
        newSection += "base_url = \"http://127.0.0.1:15721/v1\"\n"
        newSection += "upstream_base_url = \"\(provider.baseURL)\"\n"
        newSection += "wire_api = \"\(provider.wireAPI)\"\n"
        newSection += "upstream_wire_api = \"\(provider.wireAPI)\"\n"
        newSection += "requires_openai_auth = true\n"  // Required by cc-switch
        if let apiKey = provider.apiKey, !apiKey.isEmpty {
            newSection += "api_key = \"\(apiKey)\"\n"
        }
        if let bearerToken = provider.bearerToken, !bearerToken.isEmpty {
            newSection += "experimental_bearer_token = \"\(bearerToken)\"\n"
        }

        result = sectionRegex.stringByReplacingMatches(in: result, options: [], range: contentRange, withTemplate: newSection)

        return result
    }

    private func addProviderSection(_ content: String, provider: CodexModelProvider) throws -> String {
        // Build new section content (following cc-switch's format)
        var newSection = "\n[model_providers.\(provider.id)]\n"
        newSection += "name = \"\(provider.name)\"\n"
        newSection += "base_url = \"http://127.0.0.1:15721/v1\"\n"
        newSection += "upstream_base_url = \"\(provider.baseURL)\"\n"
        newSection += "wire_api = \"\(provider.wireAPI)\"\n"
        newSection += "upstream_wire_api = \"\(provider.wireAPI)\"\n"
        newSection += "requires_openai_auth = true\n"  // Required by cc-switch
        if let apiKey = provider.apiKey, !apiKey.isEmpty {
            newSection += "api_key = \"\(apiKey)\"\n"
        }
        if let bearerToken = provider.bearerToken, !bearerToken.isEmpty {
            newSection += "experimental_bearer_token = \"\(bearerToken)\"\n"
        }

        // Find where to insert (after [model_providers] if exists, otherwise at end)
        if content.contains("[model_providers]") {
            return content.replacingOccurrences(of: "[model_providers]", with: "[model_providers]" + newSection)
        } else if content.contains("[model_providers.") {
            // Find the last model_providers section
            let pattern = #"\[model_providers\.[^\]]+\][^\[]*"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, options: [], range: range)
                if let lastMatch = matches.last,
                   let lastRange = Range(lastMatch.range, in: content) {
                    let insertIndex = content.index(after: lastRange.upperBound)
                    var newContent = content
                    newContent.insert(contentsOf: newSection, at: insertIndex)
                    return newContent
                }
            }
        }

        // Add at end
        return content + "\n[model_providers]\n" + newSection
    }

    /// Ensure model_catalog_json field exists in config.
    private func ensureModelCatalogField(_ content: String) throws -> String {
        let fieldName = "model_catalog_json"
        let fieldValue = "cc-switch-model-catalog.json"

        // Check if field already exists with correct value
        if content.contains("\(fieldName) = \"\(fieldValue)\"") {
            return content
        }

        // Check if field exists with wrong value
        let existingPattern = #"^\s*model_catalog_json\s*=\s*"[^"]*""#
        if let regex = try? NSRegularExpression(pattern: existingPattern, options: [.anchorsMatchLines]) {
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                // Update existing field
                return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "\(fieldName) = \"\(fieldValue)\"")
            }
        }

        // Add field after the model line
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

    private func generateDefaultConfig() -> String {
        return """
        model_provider = "custom"
        model = "gpt-4"

        [model_providers]

        """
    }
}

/// Codex model provider configuration.
public struct CodexModelProvider: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var baseURL: String
    public var wireAPI: String
    public var apiKey: String?
    public var bearerToken: String?
    /// User's model catalog configuration (from settings.modelCatalog)
    public var modelCatalog: ModelCatalog?

    public init(
        id: String,
        name: String,
        baseURL: String,
        wireAPI: String = "responses",
        apiKey: String? = nil,
        bearerToken: String? = nil,
        modelCatalog: ModelCatalog? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.wireAPI = wireAPI
        self.apiKey = apiKey
        self.bearerToken = bearerToken
        self.modelCatalog = modelCatalog
    }

    public var isUsingProxy: Bool {
        baseURL.contains("15721")
    }

    public static func == (lhs: CodexModelProvider, rhs: CodexModelProvider) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.baseURL == rhs.baseURL &&
        lhs.wireAPI == rhs.wireAPI &&
        lhs.apiKey == rhs.apiKey &&
        lhs.bearerToken == rhs.bearerToken &&
        lhs.modelCatalog == rhs.modelCatalog
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

/// Upstream provider configuration for RequestHandler.
/// This is a simplified struct that contains only what the proxy needs.
public struct UpstreamProvider: Sendable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let usesChatCompletions: Bool
    public let bearerToken: String?

    public init(
        id: String,
        name: String,
        baseURL: String,
        usesChatCompletions: Bool,
        bearerToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.usesChatCompletions = usesChatCompletions
        self.bearerToken = bearerToken
    }
}
