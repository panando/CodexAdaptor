import Foundation
import GRDB
import CodexRouterCore

/// Database record for Provider.
public struct ProviderRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "providers"

    public var id: String
    public var name: String
    public var appType: String
    public var settingsConfig: String
    public var category: String?
    public var meta: String?
    public var sortIndex: Int?
    public var inFailoverQueue: Bool
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case appType = "app_type"
        case settingsConfig = "settings_config"
        case category
        case meta
        case sortIndex = "sort_index"
        case inFailoverQueue = "in_failover_queue"
        case createdAt = "created_at"
    }

    public init(from provider: Provider, appType: String = "codex") throws {
        self.id = provider.id
        self.name = provider.name
        self.appType = appType
        self.settingsConfig = try JSONEncoder().encode(provider.settingsConfig).base64EncodedString()
        self.category = provider.category
        if let meta = provider.meta {
            self.meta = try JSONEncoder().encode(meta).base64EncodedString()
        }
        self.sortIndex = provider.sortIndex
        self.inFailoverQueue = provider.inFailoverQueue
        self.createdAt = provider.createdAt
    }

    public func toProvider() throws -> Provider {
        guard let configData = Data(base64Encoded: settingsConfig) else {
            throw NSError(domain: "ProviderRecord", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid settings config"])
        }
        let config = try JSONDecoder().decode([String: AnyCodable].self, from: configData)

        var meta: ProviderMeta?
        if let metaString = self.meta, let metaData = Data(base64Encoded: metaString) {
            meta = try JSONDecoder().decode(ProviderMeta.self, from: metaData)
        }

        return Provider(
            id: id,
            name: name,
            settingsConfig: config,
            category: category,
            meta: meta
        )
    }
}
