import Foundation

/// Provider configuration compatible with cc-switch format.
public struct Provider: Codable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var settingsConfig: [String: AnyCodable]
    public var websiteUrl: String?
    public var category: String?
    public var createdAt: Date?
    public var sortIndex: Int?
    public var notes: String?
    public var meta: ProviderMeta?
    public var icon: String?
    public var iconColor: String?
    public var inFailoverQueue: Bool

    public init(
        id: String,
        name: String,
        settingsConfig: [String: AnyCodable] = [:],
        websiteUrl: String? = nil,
        category: String? = nil,
        meta: ProviderMeta? = nil
    ) {
        self.id = id
        self.name = name
        self.settingsConfig = settingsConfig
        self.websiteUrl = websiteUrl
        self.category = category
        self.createdAt = Date()
        self.sortIndex = nil
        self.notes = nil
        self.meta = meta
        self.icon = nil
        self.iconColor = nil
        self.inFailoverQueue = false
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Provider, rhs: Provider) -> Bool {
        lhs.id == rhs.id
    }

    /// Extract base URL from settings config.
    public var baseURL: String? {
        if let url = settingsConfig["base_url"]?.value as? String {
            return url
        }
        if let url = settingsConfig["baseURL"]?.value as? String {
            return url
        }
        return nil
    }

    /// Extract API key from settings config.
    public var apiKey: String? {
        if let env = settingsConfig["env"]?.value as? [String: Any],
           let key = env["OPENAI_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        if let auth = settingsConfig["auth"]?.value as? [String: Any],
           let key = auth["OPENAI_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        return nil
    }

    /// Check if provider uses Chat Completions API format.
    public var usesChatCompletions: Bool {
        guard let apiFormat = meta?.apiFormat ??
              (settingsConfig["api_format"]?.value as? String) ??
              (settingsConfig["apiFormat"]?.value as? String) else {
            return false
        }
        return ["chat", "chat_completions", "openai_chat"].contains(apiFormat.lowercased())
    }

    /// Map a model name to the provider's actual model name.
    public func mapModel(_ model: String) -> String {
        if let mapping = meta?.modelMappings?[model] {
            return mapping
        }
        return model
    }
}
