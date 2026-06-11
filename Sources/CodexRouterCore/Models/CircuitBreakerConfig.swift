import Foundation

/// Configuration for circuit breaker behavior.
public struct CircuitBreakerConfig: Codable, Equatable {
    public var failureThreshold: UInt
    public var successThreshold: UInt
    public var timeoutSeconds: UInt
    public var errorRateThreshold: Double?
    public var minRequests: UInt?

    public init(
        failureThreshold: UInt = 5,
        successThreshold: UInt = 3,
        timeoutSeconds: UInt = 60,
        errorRateThreshold: Double? = nil,
        minRequests: UInt? = nil
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.timeoutSeconds = timeoutSeconds
        self.errorRateThreshold = errorRateThreshold
        self.minRequests = minRequests
    }

    public static let `default` = CircuitBreakerConfig()
}
