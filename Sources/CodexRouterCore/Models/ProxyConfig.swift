import Foundation

/// Per-application proxy configuration.
public struct ProxyConfig: Codable, Equatable {
    public var appType: String
    public var enabled: Bool
    public var autoFailoverEnabled: Bool
    public var maxRetries: UInt
    public var streamingFirstByteTimeout: UInt
    public var streamingIdleTimeout: UInt
    public var nonStreamingTimeout: UInt
    public var circuitBreaker: CircuitBreakerConfig

    public init(
        appType: String = "codex",
        enabled: Bool = true,
        autoFailoverEnabled: Bool = false,
        maxRetries: UInt = 3,
        streamingFirstByteTimeout: UInt = 60,
        streamingIdleTimeout: UInt = 120,
        nonStreamingTimeout: UInt = 600,
        circuitBreaker: CircuitBreakerConfig = .default
    ) {
        self.appType = appType
        self.enabled = enabled
        self.autoFailoverEnabled = autoFailoverEnabled
        self.maxRetries = maxRetries
        self.streamingFirstByteTimeout = streamingFirstByteTimeout
        self.streamingIdleTimeout = streamingIdleTimeout
        self.nonStreamingTimeout = nonStreamingTimeout
        self.circuitBreaker = circuitBreaker
    }

    public static let `default` = ProxyConfig()
}
