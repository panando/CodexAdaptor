import Foundation
import CodexRouterCore

/// Migrates configuration from cc-switch to CodexRouter.
public struct ConfigMigrator {

    private let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// Migrate providers from cc-switch config.
    public func migrateFromCCSwitch(configPath: String = "~/.cc-switch/config.json") throws -> Int {
        let expandedPath = (configPath as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw ConfigMigrationError.sourceNotFound
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var migratedCount = 0

        // Parse providers from cc-switch format
        if let providers = json["providers"] as? [[String: Any]] {
            let providerDAO = ProviderDAO(database)

            for providerDict in providers {
                guard let id = providerDict["id"] as? String,
                      let name = providerDict["name"] as? String else {
                    continue
                }

                // Only migrate codex-type providers
                if let appType = providerDict["app_type"] as? String, appType != "codex" {
                    continue
                }

                var settingsConfig: [String: AnyCodable] = [:]

                if let settings = providerDict["settings_config"] as? [String: Any] {
                    for (key, value) in settings {
                        settingsConfig[key] = AnyCodable(value)
                    }
                }

                var meta: ProviderMeta?
                if let metaDict = providerDict["meta"] as? [String: Any] {
                    meta = ProviderMeta(
                        apiFormat: metaDict["api_format"] as? String ?? metaDict["apiFormat"] as? String,
                        customUserAgent: metaDict["custom_user_agent"] as? String ?? metaDict["customUserAgent"] as? String
                    )
                }

                let provider = Provider(
                    id: id,
                    name: name,
                    settingsConfig: settingsConfig,
                    category: providerDict["category"] as? String,
                    meta: meta
                )

                try providerDAO.save(provider, appType: "codex")
                migratedCount += 1
            }
        }

        // Migrate failover queue
        if let failoverQueue = json["failover_queue"] as? [[String: Any]] {
            let failoverDAO = FailoverDAO(database)

            for entry in failoverQueue {
                guard let providerId = entry["provider_id"] as? String,
                      let priority = entry["priority"] as? Int else {
                    continue
                }

                try failoverDAO.addToQueue(providerId: providerId, appType: "codex", priority: priority)
            }
        }

        return migratedCount
    }

    /// Export current configuration to cc-switch compatible format.
    public func exportToCCSwitch(configPath: String = "~/.cc-switch/config.json") throws {
        let expandedPath = (configPath as NSString).expandingTildeInPath

        let providerDAO = ProviderDAO(database)
        let providers = try providerDAO.getAll(appType: "codex")

        let failoverDAO = FailoverDAO(database)
        let failoverQueue = try failoverDAO.getQueue(appType: "codex")

        var providersArray: [[String: Any]] = []
        for provider in providers {
            var dict: [String: Any] = [
                "id": provider.id,
                "name": provider.name,
                "app_type": "codex",
                "settings_config": provider.settingsConfig.mapValues { $0.value },
                "in_failover_queue": failoverQueue.contains { $0.id == provider.id }
            ]

            if let category = provider.category {
                dict["category"] = category
            }
            if let meta = provider.meta {
                dict["meta"] = [
                    "api_format": meta.apiFormat as Any,
                    "custom_user_agent": meta.customUserAgent as Any
                ].compactMapValues { $0 }
            }

            providersArray.append(dict)
        }

        var failoverArray: [[String: Any]] = []
        for (index, provider) in failoverQueue.enumerated() {
            failoverArray.append([
                "provider_id": provider.id,
                "priority": index
            ])
        }

        let config: [String: Any] = [
            "providers": providersArray,
            "failover_queue": failoverArray
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: expandedPath))
    }
}

/// Configuration migration errors.
public enum ConfigMigrationError: Error, LocalizedError {
    case sourceNotFound
    case invalidFormat
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Source configuration not found"
        case .invalidFormat:
            return "Invalid configuration format"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        }
    }
}
