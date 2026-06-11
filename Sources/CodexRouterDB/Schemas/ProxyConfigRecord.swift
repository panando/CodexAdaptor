import Foundation
import GRDB
import CodexRouterCore

/// Database record for ProxyConfig.
public struct ProxyConfigRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "proxy_config"

    public var appType: String
    public var autoFailoverEnabled: Bool
    public var maxRetries: Int
    public var circuitFailureThreshold: Int
    public var circuitSuccessThreshold: Int
    public var circuitTimeoutSeconds: Int
    public var streamingFirstByteTimeout: Int
    public var streamingIdleTimeout: Int

    enum CodingKeys: String, CodingKey {
        case appType = "app_type"
        case autoFailoverEnabled = "auto_failover_enabled"
        case maxRetries = "max_retries"
        case circuitFailureThreshold = "circuit_failure_threshold"
        case circuitSuccessThreshold = "circuit_success_threshold"
        case circuitTimeoutSeconds = "circuit_timeout_seconds"
        case streamingFirstByteTimeout = "streaming_first_byte_timeout"
        case streamingIdleTimeout = "streaming_idle_timeout"
    }

    public init(from config: ProxyConfig) {
        self.appType = config.appType
        self.autoFailoverEnabled = config.autoFailoverEnabled
        self.maxRetries = Int(config.maxRetries)
        self.circuitFailureThreshold = Int(config.circuitBreaker.failureThreshold)
        self.circuitSuccessThreshold = Int(config.circuitBreaker.successThreshold)
        self.circuitTimeoutSeconds = Int(config.circuitBreaker.timeoutSeconds)
        self.streamingFirstByteTimeout = Int(config.streamingFirstByteTimeout)
        self.streamingIdleTimeout = Int(config.streamingIdleTimeout)
    }

    public func toProxyConfig() -> ProxyConfig {
        ProxyConfig(
            appType: appType,
            enabled: true,
            autoFailoverEnabled: autoFailoverEnabled,
            maxRetries: UInt(maxRetries),
            streamingFirstByteTimeout: UInt(streamingFirstByteTimeout),
            streamingIdleTimeout: UInt(streamingIdleTimeout),
            circuitBreaker: CircuitBreakerConfig(
                failureThreshold: UInt(circuitFailureThreshold),
                successThreshold: UInt(circuitSuccessThreshold),
                timeoutSeconds: UInt(circuitTimeoutSeconds)
            )
        )
    }
}
