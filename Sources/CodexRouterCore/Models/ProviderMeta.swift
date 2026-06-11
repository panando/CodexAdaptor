import Foundation

/// Provider metadata for advanced configuration.
public struct ProviderMeta: Codable, Equatable {
    public var apiFormat: String?
    public var codexChatReasoning: ReasoningConfig?
    public var customUserAgent: String?
    public var providerType: String?

    public init(
        apiFormat: String? = nil,
        codexChatReasoning: ReasoningConfig? = nil,
        customUserAgent: String? = nil,
        providerType: String? = nil
    ) {
        self.apiFormat = apiFormat
        self.codexChatReasoning = codexChatReasoning
        self.customUserAgent = customUserAgent
        self.providerType = providerType
    }

    public static func == (lhs: ProviderMeta, rhs: ProviderMeta) -> Bool {
        lhs.apiFormat == rhs.apiFormat &&
        lhs.codexChatReasoning == rhs.codexChatReasoning &&
        lhs.customUserAgent == rhs.customUserAgent &&
        lhs.providerType == rhs.providerType
    }
}
